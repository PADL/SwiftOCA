//
// Copyright (c) 2025 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#if canImport(Network)

import AsyncAlgorithms
import AsyncExtensions

#if swift(>=6.0)
internal import CoreFoundation
#else
@preconcurrency
@_implementationOnly import CoreFoundation
#endif
import Foundation
import Network
import SocketAddress
import SystemPackage
#if canImport(Synchronization)
import Synchronization
#endif

private extension SocketAddress {
  private func _asNWEndpointHost() throws -> NWEndpoint.Host {
    if family == AF_LOCAL {
      try NWEndpoint.Host.name(presentationAddress, nil)
    } else {
      try withSockAddr { sa, _ in
        switch Int32(family) {
        case AF_INET:
          return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
            let ipv4Address = IPv4Address(withUnsafeBytes(of: sin.pointee.sin_addr) { Data($0) })!
            return NWEndpoint.Host.ipv4(ipv4Address)
          }
        case AF_INET6:
          return sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
            let ipv6Address = IPv6Address(withUnsafeBytes(of: sin6.pointee.sin6_addr) { Data($0) })!
            return NWEndpoint.Host.ipv6(ipv6Address)
          }
        default:
          throw Errno.addressFamilyNotSupported
        }
      }
    }
  }

  private func _asNWEndpointPort() throws -> NWEndpoint.Port {
    try NWEndpoint.Port(integerLiteral: port)
  }

  func asNWEndpoint() throws -> NWEndpoint {
    try NWEndpoint.hostPort(host: _asNWEndpointHost(), port: _asNWEndpointPort())
  }
}

public class Ocp1NWConnection: Ocp1Connection, Ocp1MutableConnection {
  fileprivate let _deviceAddress: Mutex<AnySocketAddress>
  fileprivate var _queue: DispatchQueue!
  fileprivate var _nwConnection: NWConnection!

  fileprivate var parameters: NWParameters {
    fatalError("must be implemented by subclass")
  }

  private init(
    deviceAddress: AnySocketAddress,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    _deviceAddress = Mutex(deviceAddress)
    super.init(options: options)
    _nwConnection = try NWConnection(to: nwEndpoint, using: parameters)
    _nwConnection.stateUpdateHandler = { [weak self] state in
      if let self, state == .cancelled {
        Task { try await self.disconnect() }
      }
    }
    _queue = DispatchQueue(label: connectionPrefix, attributes: .concurrent)
  }

  public convenience init(
    deviceAddress: Data,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    let deviceAddress = try AnySocketAddress(bytes: Array(deviceAddress))
    try self.init(deviceAddress: deviceAddress, options: options)
  }

  public convenience init(
    path: String,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    let deviceAddress = try AnySocketAddress(
      family: sa_family_t(AF_LOCAL),
      presentationAddress: path
    )
    try self.init(deviceAddress: deviceAddress, options: options)
  }

  public nonisolated var deviceAddress: Data {
    get {
      AnySocketAddress(_deviceAddress.criticalValue).data
    }
    set {
      do {
        try _deviceAddress.withLock {
          $0 = try AnySocketAddress(bytes: Array(newValue))
          Task { await deviceAddressDidChange() }
        }
      } catch {}
    }
  }

  override public func connectDevice() async throws {
    _nwConnection.start(queue: _queue)
    try await super.connectDevice()
  }

  override public func disconnectDevice() async throws {
    _nwConnection.stateUpdateHandler = nil
    _nwConnection.cancel()
    try await super.disconnectDevice()
  }

  override public func read(_ length: Int) async throws -> Data {
    try await withUnsafeThrowingContinuation { continuation in
      _nwConnection.receive(
        minimumIncompleteLength: length,
        maximumLength: Ocp1MaximumDatagramPduSize
      ) { data, _, _, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: data ?? .init())
        }
      }
    }
  }

  override public func write(_ data: Data) async throws -> Int {
    let isDatagram = isDatagram
    return try await withUnsafeThrowingContinuation { continuation in
      _nwConnection.send(
        content: data,
        isComplete: isDatagram,
        completion: .contentProcessed { error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: data.count)
          }
        }
      )
    }
  }

  fileprivate nonisolated var nwEndpoint: NWEndpoint {
    get throws {
      try _deviceAddress.criticalValue.asNWEndpoint()
    }
  }

  fileprivate nonisolated var presentationAddress: String {
    _deviceAddress.criticalValue.unsafelyUnwrappedPresentationAddress
  }
}

public final class Ocp1NWUDPConnection: Ocp1NWConnection {
  override public var heartbeatTime: Duration {
    .seconds(1)
  }

  override public var connectionPrefix: String {
    "\(OcaUdpConnectionPrefix)/\(presentationAddress)"
  }

  override public var isDatagram: Bool { true }

  override var parameters: NWParameters {
    let options = NWProtocolUDP.Options()
    return NWParameters(dtls: nil, udp: options)
  }
}

public final class Ocp1NWTCPConnection: Ocp1NWConnection {
  override public var connectionPrefix: String {
    "\(OcaTcpConnectionPrefix)/\(presentationAddress)"
  }

  override public var isDatagram: Bool { false }

  override var parameters: NWParameters {
    let options = NWProtocolTCP.Options()
    options.noDelay = true
    options.enableFastOpen = true
    options.connectionTimeout = Int(self.options.connectionTimeout.seconds)
    return NWParameters(tls: nil, tcp: options)
  }
}

#endif
