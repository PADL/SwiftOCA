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

open class Ocp1NWConnection: Ocp1Connection, Ocp1MutableSocketAddressConnection {
  package let _deviceAddresses: Mutex<[AnySocketAddress]>
  package let _connectedDeviceAddress = Mutex<AnySocketAddress?>(nil)
  package var _queue: DispatchQueue!
  package var _nwConnection: NWConnection!

  open var parameters: NWParameters {
    fatalError("must be implemented by subclass")
  }

  /// Shared TCP options factory so plaintext and TLS subclasses stay in sync.
  package func makeTCPOptions() -> NWProtocolTCP.Options {
    let options = NWProtocolTCP.Options()
    options.noDelay = true
    options.enableFastOpen = true
    options.connectionTimeout = Int(self.options.connectionTimeout.seconds)
    return options
  }

  package init(
    deviceAddresses: [AnySocketAddress],
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    _deviceAddresses = Mutex(deviceAddresses)
    super.init(options: options)
    _nwConnection = try NWConnection(to: nwEndpoint, using: parameters)
    Self._installPostReadyStateHandler(_nwConnection) { [weak self] in
      try await self?.disconnect()
    }
    _queue = DispatchQueue(label: connectionPrefix, attributes: .concurrent)
  }

  /// Long-lived state handler installed once `connectDevice` has resolved
  /// the initial `.ready`/`.failed` race; only `.cancelled` matters here.
  /// Post-ready `.failed` surfaces via the next read/write.
  fileprivate static func _installPostReadyStateHandler(
    _ connection: NWConnection,
    onCancelled: @Sendable @escaping () async throws -> Void
  ) {
    connection.stateUpdateHandler = { state in
      if state == .cancelled {
        Task { try await onCancelled() }
      }
    }
  }

  public convenience init(
    deviceAddress: Data,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    let deviceAddress = try AnySocketAddress(bytes: Array(deviceAddress))
    try self.init(deviceAddresses: [deviceAddress], options: options)
  }

  public convenience init(
    deviceAddresses: [Data],
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    try self.init(
      deviceAddresses: deviceAddresses.compactMap { try? AnySocketAddress(bytes: Array($0)) },
      options: options
    )
  }

  public convenience init(
    path: String,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    let deviceAddress = try AnySocketAddress(
      family: sa_family_t(AF_LOCAL),
      presentationAddress: path
    )
    try self.init(deviceAddresses: [deviceAddress], options: options)
  }

  private func _cleanupConnection() throws {
    _nwConnection.stateUpdateHandler = nil
    _nwConnection.cancel()
    _nwConnection = try NWConnection(to: nwEndpoint, using: parameters)
    Self._installPostReadyStateHandler(_nwConnection) { [weak self] in
      try await self?.disconnect()
    }
  }

  override public func connectDevice() async throws {
    if _nwConnection.state != .setup {
      try _cleanupConnection()
    }
    try await _connectFirstReachableDeviceAddress()
    try await super.connectDevice()
  }

  package func _connectDevice(to deviceAddress: AnySocketAddress) async throws {
    // Rebuild the connection for this specific candidate; NW is given a resolved
    // endpoint, so each candidate needs its own `NWConnection`.
    let endpoint = try deviceAddress.asNWEndpoint()
    _nwConnection = try NWConnection(to: endpoint, using: parameters)
    let connection = _nwConnection!
    do {
      // Wait for `.ready`/`.failed` before completing connect — without this
      // any TLS handshake error is invisible until the first read/write.
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
          // Guard against double-resume from transient state toggling.
          let resumed = Mutex(false)
          connection.stateUpdateHandler = { state in
            let outcome: Result<Void, Error>?
            switch state {
            case .ready:
              outcome = .success(())
            case let .failed(error):
              outcome = .failure(error)
            case let .waiting(error):
              // TLS auth failures surface as `.waiting` (NW retries forever);
              // treat as terminal during connect rather than hanging.
              outcome = .failure(error)
            case .cancelled:
              outcome = .failure(Ocp1Error.notConnected)
            default:
              outcome = nil
            }
            guard let outcome else { return }
            let claimed = resumed.withLock { flag -> Bool in
              if flag { return false }
              flag = true
              return true
            }
            if claimed { cont.resume(with: outcome) }
          }
          connection.start(queue: _queue)
        }
      } onCancel: {
        // When the per-candidate timeout (or any cancellation) fires, drive the
        // connection to `.cancelled` so the continuation above resumes instead
        // of leaving the awaiting task parked forever.
        connection.cancel()
      }
    } catch {
      // Tear down this candidate's connection before the next is tried.
      connection.stateUpdateHandler = nil
      connection.cancel()
      throw error
    }
    Self._installPostReadyStateHandler(connection) { [weak self] in
      try await self?.disconnect()
    }
  }

  override public func disconnectDevice() async throws {
    try _cleanupConnection()
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

  override public var localAddress: Data? {
    guard let localEndpoint = _nwConnection?.currentPath?.localEndpoint else { return nil }
    switch localEndpoint {
    case let .hostPort(host, port):
      let address: (any SocketAddress)? = switch host {
      case let .ipv4(ipv4):
        try? sockaddr_in(
          family: sa_family_t(AF_INET),
          presentationAddress: "\(ipv4):\(port.rawValue)"
        )
      case let .ipv6(ipv6):
        try? sockaddr_in6(
          family: sa_family_t(AF_INET6),
          presentationAddress: "[\(ipv6)]:\(port.rawValue)"
        )
      default:
        nil
      }
      return address.map { AnySocketAddress($0).data }
    default:
      return nil
    }
  }

  /// The endpoint for the *preferred* (first) candidate, used to seed the
  /// initial connection in `init`/`_cleanupConnection`. The actual connect in
  /// `_connectDevice(to:)` builds an endpoint per candidate.
  open nonisolated var nwEndpoint: NWEndpoint {
    get throws {
      guard let first = _deviceAddresses.criticalValue.first else {
        throw Ocp1Error.notConnected
      }
      return try first.asNWEndpoint()
    }
  }

  package nonisolated var presentationAddress: String {
    _currentPresentationAddress
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

  override public var parameters: NWParameters {
    let options = NWProtocolUDP.Options()
    return NWParameters(dtls: nil, udp: options)
  }
}

public final class Ocp1NWTCPConnection: Ocp1NWConnection {
  override public var connectionPrefix: String {
    "\(OcaTcpConnectionPrefix)/\(presentationAddress)"
  }

  override public var isDatagram: Bool { false }

  override public var parameters: NWParameters {
    NWParameters(tls: nil, tcp: makeTCPOptions())
  }
}

#endif
