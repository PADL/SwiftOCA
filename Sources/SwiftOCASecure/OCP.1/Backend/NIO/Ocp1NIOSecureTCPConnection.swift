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

#if SwiftNIOBackend

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import NIOCore
import NIOPosix
import NIOSSL
import SocketAddress
@_spi(SwiftOCAPrivate)
import SwiftOCA
import Synchronization

/// OCP.1 TLS-secured TCP connection backed by SwiftNIO + NIOSSL. Cert-only —
/// PSK / `SecIdentity` / revocation throw at construction; see the
/// `SwiftNIOBackend` section of `Documentation/TLS.md`.
public final class Ocp1NIOSecureTCPConnection: Ocp1Connection, Ocp1MutableConnection {
  private let _credential: Ocp1TLSCredential
  private let _hostname: String?
  private let _trustRoots: Ocp1TLSTrustRoots?
  private let _revocation: Ocp1TLSRevocationOptions
  private let _verifyPeer: Bool
  private let _eventLoopGroup: any EventLoopGroup
  private let _deviceAddress: Mutex<AnySocketAddress>
  private let _channel: Mutex<(any Channel)?> = .init(nil)
  private let _bridge: Mutex<Ocp1NIOByteBufferBridge?> = .init(nil)

  override public var connectionPrefix: String {
    "\(OcaSecureTcpConnectionPrefix)/\(_deviceAddress.withLock { $0._presentationAddress })"
  }

  override public var isDatagram: Bool { false }
  override public var hasTransportLayerSecurity: Bool { true }

  /// - Parameter eventLoopGroup: Injected so callers can share a group with
  ///   the rest of their Swift-on-Server stack. Defaults to the process-wide
  ///   `MultiThreadedEventLoopGroup.singleton`.
  public init(
    deviceAddress: Data,
    credential: Ocp1TLSCredential,
    hostname: String? = nil,
    trustRoots: Ocp1TLSTrustRoots? = nil,
    revocation: Ocp1TLSRevocationOptions = .disabled,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions(),
    eventLoopGroup: any EventLoopGroup = MultiThreadedEventLoopGroup.singleton
  ) throws {
    try credential.validate()
    _credential = credential
    _hostname = hostname
    _trustRoots = trustRoots
    _revocation = revocation
    _verifyPeer = !options.flags.contains(.disableCertificateVerification)
    _eventLoopGroup = eventLoopGroup
    _deviceAddress = Mutex(try AnySocketAddress(bytes: Array(deviceAddress)))
    super.init(options: options)
  }

  public nonisolated var deviceAddress: Data {
    get {
      _deviceAddress.withLock { $0.data }
    }
    set {
      do {
        try _deviceAddress.withLock {
          $0 = try AnySocketAddress(bytes: Array(newValue))
          Task { [weak self] in await self?.deviceAddressDidChange() }
        }
      } catch {}
    }
  }

  override public func connectDevice() async throws {
    let context = try Ocp1NIOTLSConfiguration.makeClientContext(
      credential: _credential,
      trustRoots: _trustRoots,
      revocation: _revocation,
      hostname: _hostname,
      verifyPeer: _verifyPeer
    )
    let nioAddress = try _deviceAddress.withLock { try Self._makeNIOAddress(from: $0) }

    let bridge = Ocp1NIOByteBufferBridge()
    let hostname = _hostname
    let bootstrap = ClientBootstrap(group: _eventLoopGroup)
      .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .channelInitializer { channel in
        // `syncOperations` runs on the channel's event loop and accepts
        // non-Sendable handlers (NIOSSL handlers aren't Sendable).
        channel.eventLoop.makeCompletedFuture {
          let sslHandler = try NIOSSLClientHandler(
            context: context,
            serverHostname: hostname
          )
          try channel.pipeline.syncOperations.addHandlers([sslHandler, bridge])
        }
      }

    let channel: any Channel
    do {
      channel = try await bootstrap.connect(to: nioAddress).get()
    } catch {
      bridge.close()
      throw Ocp1Error.notConnected
    }

    _channel.withLock { $0 = channel }
    _bridge.withLock { $0 = bridge }
    try await super.connectDevice()
  }

  override public func disconnectDevice() async throws {
    let channel = _channel.withLock { (slot: inout (any Channel)?) -> (any Channel)? in
      let c = slot
      slot = nil
      return c
    }
    let bridge = _bridge.withLock { (slot: inout Ocp1NIOByteBufferBridge?) -> Ocp1NIOByteBufferBridge? in
      let b = slot
      slot = nil
      return b
    }
    bridge?.close()
    if let channel {
      try? await channel.close(mode: .all).get()
    }
    try await super.disconnectDevice()
  }

  override public func read(_ length: Int) async throws -> Data {
    guard let bridge = _bridge.withLock({ $0 }) else {
      throw Ocp1Error.notConnected
    }
    return try await bridge.read(length)
  }

  override public func write(_ data: Data) async throws -> Int {
    guard let channel = _channel.withLock({ $0 }) else {
      throw Ocp1Error.notConnected
    }
    var buffer = channel.allocator.buffer(capacity: data.count)
    buffer.writeBytes(data)
    do {
      try await channel.writeAndFlush(buffer).get()
    } catch {
      throw Ocp1Error.notConnected
    }
    return data.count
  }

  /// Reconstruct a `NIOCore.SocketAddress` from PADL's address wrapper.
  /// IP families round-trip through `presentationAddressNoPort` + `port`,
  /// avoiding manual sockaddr layout games.
  static func _makeNIOAddress(from any: AnySocketAddress) throws -> NIOCore.SocketAddress {
    switch Int32(any.family) {
    case AF_INET, AF_INET6:
      return try NIOCore.SocketAddress(
        ipAddress: try any.presentationAddressNoPort,
        port: Int(any.port)
      )
    case AF_LOCAL:
      return try NIOCore.SocketAddress(unixDomainSocketPath: any.presentationAddressNoPort)
    default:
      throw Ocp1Error.status(.parameterError)
    }
  }
}

#endif
