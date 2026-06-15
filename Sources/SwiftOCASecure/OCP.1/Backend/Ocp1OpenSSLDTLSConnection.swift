//
// Copyright (c) 2026 PADL Software Pty Ltd
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

#if canImport(COpenSSL) && canImport(IORing)

import COpenSSL
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Glibc
public import IORing
internal import IORingUtils
import SocketAddress
@_spi(SwiftOCAPrivate)
import SwiftOCA
import Synchronization
import struct SystemPackage.Errno

fileprivate extension Errno {
  var mappedError: Error {
    switch self {
    case .connectionRefused, .connectionReset, .brokenPipe:
      Ocp1Error.notConnected
    case .canceled:
      Ocp1Error.retryOperation
    default:
      self
    }
  }
}

/// OCP.1 DTLS-secured UDP connection. Connected SOCK_DGRAM socket so each
/// receive returns one peer datagram, which we deposit into the engine's
/// rbio for SSL_read to drain one DTLS record at a time.
public final class Ocp1OpenSSLDTLSConnection: Ocp1Connection, Ocp1MutableSocketAddressConnection {
  private let _ring: IORing
  package let _deviceAddresses: Mutex<[AnySocketAddress]>
  package let _connectedDeviceAddress = Mutex<AnySocketAddress?>(nil)
  private let _socket: Mutex<Socket?> = .init(nil)
  private let _credential: Ocp1TLSCredential
  private let _engine: Ocp1OpenSSLEngine

  override public var connectionPrefix: String {
    "\(OcaSecureUdpConnectionPrefix)/\(_currentPresentationAddress)"
  }

  override public var isDatagram: Bool { true }
  override public var hasTransportLayerSecurity: Bool { true }

  override public var heartbeatTime: Duration { .seconds(1) }

  private init(
    socketAddresses: [any SocketAddress],
    credential: Ocp1TLSCredential,
    hostname: String?,
    trustRoots: Ocp1TLSTrustRoots?,
    revocation: Ocp1TLSRevocationOptions,
    options: Ocp1ConnectionOptions,
    ring: IORing
  ) throws {
    _deviceAddresses = Mutex(socketAddresses.map { AnySocketAddress($0) })
    _ring = ring
    _credential = credential
    let verifyPeer = !options.flags.contains(.disableCertificateVerification)
    _engine = try Ocp1OpenSSLEngine(
      mode: .client,
      credential: credential,
      transport: .datagram,
      verifyPeer: verifyPeer,
      hostname: hostname,
      trustRoots: trustRoots,
      revocation: revocation
    )
    super.init(options: options)
  }

  public convenience init(
    deviceAddress: Data,
    credential: Ocp1TLSCredential,
    hostname: String? = nil,
    trustRoots: Ocp1TLSTrustRoots? = nil,
    revocation: Ocp1TLSRevocationOptions = .disabled,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions(),
    ring: IORing = .shared
  ) throws {
    try self.init(
      socketAddresses: [deviceAddress.socketAddress],
      credential: credential,
      hostname: hostname,
      trustRoots: trustRoots,
      revocation: revocation,
      options: options,
      ring: ring
    )
  }

  public convenience init(
    deviceAddresses: [Data],
    credential: Ocp1TLSCredential,
    hostname: String? = nil,
    trustRoots: Ocp1TLSTrustRoots? = nil,
    revocation: Ocp1TLSRevocationOptions = .disabled,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions(),
    ring: IORing = .shared
  ) throws {
    try self.init(
      socketAddresses: deviceAddresses.compactMap { try? $0.socketAddress },
      credential: credential,
      hostname: hostname,
      trustRoots: trustRoots,
      revocation: revocation,
      options: options,
      ring: ring
    )
  }

  override public var localAddress: Data? {
    guard let socket = _socket.withLock({ $0 }) else { return nil }
    return try? AnySocketAddress(socket.localAddress).data
  }

  override public func connectDevice() async throws {
    try await _connectFirstReachableDeviceAddress()
    try await super.connectDevice()
  }

  package func _connectDevice(to deviceAddress: AnySocketAddress) async throws {
    await _engine.reset()
    let socket = try Socket(
      ring: _ring,
      domain: deviceAddress.family,
      type: Glibc.SOCK_DGRAM,
      protocol: 0
    )
    do {
      try await socket.connect(to: deviceAddress)
    } catch let error as Errno {
      throw error.mappedError
    }
    _socket.withLock { $0 = socket }

    let (read, write) = Self.makeTransportClosures(socket)
    // DTLS over a memory BIO has no internal scheduler — pair the handshake
    // with a ticker that drives the engine's retransmit timer.
    let engine = _engine
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          try await engine.handshake(read: read, write: write)
        }
        group.addTask {
          while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
            if await engine.isHandshakeComplete { return }
            _ = try? await engine.handleDatagramTimeout(write: write)
          }
        }
        // The handshake task finishes first; cancel the watchdog and
        // surface the handshake's result.
        try await group.next()
        group.cancelAll()
      }
    } catch {
      _socket.withLock { $0 = nil }
      throw error
    }
  }

  override public func disconnectDevice() async throws {
    let socket = _socket.withLock { (slot: inout Socket?) -> Socket? in
      let s = slot
      slot = nil
      return s
    }
    if let socket {
      let (read, write) = Self.makeTransportClosures(socket)
      try? await _engine.shutdown(read: read, write: write)
    }
    try await super.disconnectDevice()
  }

  override public func read(_ length: Int) async throws -> Data {
    guard let socket = _socket.withLock({ $0 }) else {
      throw Ocp1Error.notConnected
    }
    let (read, write) = Self.makeTransportClosures(socket)
    do {
      return try await _engine.readDatagram(read: read, write: write)
    } catch let error as Errno {
      throw error.mappedError
    }
  }

  override public func write(_ data: Data) async throws -> Int {
    guard let socket = _socket.withLock({ $0 }) else {
      throw Ocp1Error.notConnected
    }
    let (read, write) = Self.makeTransportClosures(socket)
    do {
      return try await _engine.write(data, read: read, write: write)
    } catch let error as Errno {
      throw error.mappedError
    }
  }

  /// Datagram transport closures. `awaitingAllRead: false` truncates the
  /// buffer to the actual datagram length — DTLS is strict about record
  /// framing and would alert on trailing garbage.
  private static func makeTransportClosures(
    _ socket: Socket
  ) -> (
    read: @Sendable (Int) async throws -> Data,
    write: @Sendable (Data) async throws -> Void
  ) {
    let read: @Sendable (Int) async throws -> Data = { _ in
      try await Data(socket.read(
        count: Ocp1MaximumDatagramPduSize,
        awaitingAllRead: false
      ))
    }
    let write: @Sendable (Data) async throws -> Void = { data in
      try await socket.send(Array(data))
    }
    return (read, write)
  }
}

#endif
