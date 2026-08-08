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

import AsyncAlgorithms
@preconcurrency
import AsyncExtensions
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
import Logging
import NIOCore
import NIOPosix
import NIOSSL
import NIOTLS
@_spi(SwiftOCAPrivate)
import SwiftOCADevice
import SwiftOCASecure
@_spi(SwiftOCAPrivate)
import SwiftOCA
import Synchronization

/// TLS-secured OCP.1 stream device endpoint backed by SwiftNIO + NIOSSL.
/// Opt-in via the `SwiftNIOBackend` package trait. Cert credentials only —
/// PSK and `SecIdentity` throw at construction time; DTLS isn't offered.
///
/// This endpoint owns its own `EventLoopGroup`-bound `ServerBootstrap`; it
/// does **not** inherit from `Ocp1IORingDeviceEndpoint`, since NIO drives the
/// accept loop itself rather than sharing an IORing socket.
@OcaDevice
public final class Ocp1NIOSecureTCPDeviceEndpoint: OcaDeviceEndpointPrivate,
  OcaBonjourRegistrableDeviceEndpoint,
  CustomStringConvertible
{
  package typealias ControllerType = Ocp1NIOSecureTCPController

  public var controllers: [OcaController] { _controllers }

  package let timeout: Duration
  package let device: OcaDevice
  package nonisolated let logger: Logger
  package nonisolated(unsafe) var enableMessageTracing = false

  private let serverCredential: Ocp1TLSCredential?
  /// Non-nil enables mTLS.
  private let clientCertificateTrustRoots: Ocp1TLSTrustRoots?
  private let revocation: Ocp1TLSRevocationOptions
  private let _maxConnections: Int
  private let _handshakeTimeout: Duration
  let firstMessageDeadline: Duration
  private let _eventLoopGroup: any EventLoopGroup

  private let _bindPort: Int
  /// `0` until the server channel binds; updated once and used by Bonjour.
  private let _boundPort = Mutex<UInt16>(0)
  private var _serverChannel: (any Channel)?
  private var _controllers: [Ocp1NIOSecureTCPController] = []
  /// Counted against `maxConnections` along with completed controllers so
  /// slow-loris peers can't exhaust the channel budget mid-handshake.
  private var _pendingHandshakes: Int = 0
  #if canImport(dnssd)
  private var _endpointRegistrarTask: Task<(), Error>?
  #endif

  public nonisolated var description: String {
    "\(type(of: self))(port: \(_bindPort), timeout: \(timeout))"
  }

  public nonisolated var port: UInt16 {
    let bound = _boundPort.withLock { $0 }
    return bound != 0 ? bound : UInt16(_bindPort)
  }

  public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    .tcpSecure
  }

  public init(
    port: UInt16,
    credential: Ocp1TLSCredential? = nil,
    clientCertificateTrustRoots: Ocp1TLSTrustRoots? = nil,
    revocation: Ocp1TLSRevocationOptions = .disabled,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCASecureDevice.Ocp1NIOSecureTCPDeviceEndpoint"),
    maxConnections: Int = 1024,
    handshakeTimeout: Duration = .seconds(10),
    firstMessageDeadline: Duration = .seconds(30),
    eventLoopGroup: any EventLoopGroup = MultiThreadedEventLoopGroup.singleton
  ) async throws {
    if let credential {
      try credential.validate()
    }
    serverCredential = credential
    self.clientCertificateTrustRoots = clientCertificateTrustRoots
    self.revocation = revocation
    self.timeout = timeout
    self.device = device
    self.logger = logger
    _maxConnections = maxConnections
    _handshakeTimeout = handshakeTimeout
    self.firstMessageDeadline = firstMessageDeadline
    _eventLoopGroup = eventLoopGroup
    _bindPort = Int(port)

    try await device.add(endpoint: self)
  }

  public func run() async throws {
    guard let serverCredential else {
      logger.error("\(type(of: self)) cannot start without a server credential")
      throw Ocp1Error.notConnected
    }
    let context = try Ocp1NIOTLSConfiguration.makeServerContext(
      credential: serverCredential,
      clientCertificateTrustRoots: clientCertificateTrustRoots,
      revocation: revocation
    )

    let acceptedStream = AsyncStream<AcceptedChannel>.makeStream()
    let bootstrap = ServerBootstrap(group: _eventLoopGroup)
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
      .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .childChannelInitializer { channel in
        let handshakePromise = channel.eventLoop.makePromise(of: Void.self)
        let bridge = Ocp1NIOByteBufferBridge()
        // `syncOperations` runs on the channel's event loop and accepts
        // non-Sendable handlers (NIOSSLServerHandler isn't Sendable).
        return channel.eventLoop.makeCompletedFuture {
          let sslHandler = NIOSSLServerHandler(context: context)
          let handshakeHandler = Ocp1NIOHandshakeCompletionHandler(promise: handshakePromise)
          try channel.pipeline.syncOperations.addHandlers([
            sslHandler, handshakeHandler, bridge,
          ])
        }.map { _ in
          acceptedStream.continuation.yield(
            AcceptedChannel(
              channel: channel,
              bridge: bridge,
              handshakeCompleted: handshakePromise.futureResult
            )
          )
        }
      }

    logger.info("starting \(type(of: self)) on port \(_bindPort)")
    if clientCertificateTrustRoots != nil {
      logger.info("\(type(of: self)) requires client certificates (mTLS)")
    }

    let server: any Channel
    do {
      server = try await bootstrap.bind(host: "0.0.0.0", port: _bindPort).get()
    } catch {
      acceptedStream.continuation.finish()
      logger.critical("listener bind failed: \(error)")
      throw error
    }
    _serverChannel = server
    if let boundPort = server.localAddress?.port {
      _resolveBoundPort(UInt16(boundPort))
    }

    // Server channel closes when `disconnect()` is called or on fatal error;
    // tie the accept stream lifetime to it so the accept loop drains.
    server.closeFuture.whenComplete { _ in
      acceptedStream.continuation.finish()
    }

    await withDiscardingTaskGroup { group in
      for await accepted in acceptedStream.stream {
        group.addTask { [weak self] in
          guard let self else { return }
          await self.handle(accepted: accepted)
        }
      }
    }

    _serverChannel = nil
    try? await device.remove(endpoint: self)
  }

  private func handle(accepted: AcceptedChannel) async {
    if _controllers.count + _pendingHandshakes >= _maxConnections {
      logger.warning(
        "TLS connection cap (\(_maxConnections)) reached (in-flight handshakes: \(_pendingHandshakes)); refusing new client"
      )
      accepted.bridge.close()
      try? await accepted.channel.close(mode: .all).get()
      return
    }
    _pendingHandshakes += 1
    defer { _pendingHandshakes -= 1 }

    // Block on handshake completion before constructing a controller —
    // otherwise mTLS verification failures would only surface inside the
    // controller's receive loop as `.notConnected`, with no log trace.
    do {
      try await withThrowingTimeout(of: _handshakeTimeout, clock: .continuous) {
        try await accepted.handshakeCompleted.get()
      }
    } catch {
      logger.warning("TLS handshake failed or timed out: \(error)")
      accepted.bridge.close()
      try? await accepted.channel.close(mode: .all).get()
      return
    }

    let peerAddress = accepted.channel.remoteAddress?.description ?? "unknown"
    let peerCert: NIOSSLCertificate?
    do {
      peerCert = try await accepted.channel.nioSSL_peerCertificate().get()
    } catch {
      peerCert = nil
    }
    let peerIdentity = Ocp1NIOExtractPeerIdentity(from: peerCert)

    do {
      let controller = try await Ocp1NIOSecureTCPController(
        endpoint: self,
        channel: accepted.channel,
        bridge: accepted.bridge,
        peerIdentity: peerIdentity,
        identifier: peerAddress
      )
      await controller.handle(for: self)
    } catch {
      logger.warning("controller setup failed: \(error)")
      accepted.bridge.close()
      try? await accepted.channel.close(mode: .all).get()
    }
  }

  private func _resolveBoundPort(_ port: UInt16) {
    _boundPort.withLock { $0 = port }
    #if canImport(dnssd)
    // makeBonjourRegistrarTask reads `port` synchronously, so kick off only
    // after the bound port is known.
    if _endpointRegistrarTask == nil {
      _endpointRegistrarTask = makeBonjourRegistrarTask(for: device)
    }
    #endif
  }

  package func add(controller: Ocp1NIOSecureTCPController) async {
    _controllers.append(controller)
  }

  package func remove(controller: Ocp1NIOSecureTCPController) async {
    _controllers.removeAll(where: { $0 == controller })
  }

  deinit {
    #if canImport(dnssd)
    _endpointRegistrarTask?.cancel()
    #endif
    if let server = _serverChannel {
      _ = server.close(mode: .all)
    }
  }
}

/// Carrier for the per-child-channel state produced by the
/// `childChannelInitializer` and consumed by the accept loop.
private struct AcceptedChannel: @unchecked Sendable {
  let channel: any Channel
  let bridge: Ocp1NIOByteBufferBridge
  let handshakeCompleted: EventLoopFuture<Void>
}

/// Listens for `TLSUserEvent.handshakeCompleted` so the accept loop can wait
/// on handshake completion before constructing a controller, and fail-fast on
/// mTLS verification errors instead of swallowing them in the read loop.
private final class Ocp1NIOHandshakeCompletionHandler: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = ByteBuffer

  private let promise: EventLoopPromise<Void>
  private var fulfilled = false

  init(promise: EventLoopPromise<Void>) {
    self.promise = promise
  }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    if !fulfilled, let tlsEvent = event as? TLSUserEvent {
      if case .handshakeCompleted = tlsEvent {
        fulfilled = true
        promise.succeed(())
      }
    }
    context.fireUserInboundEventTriggered(event)
  }

  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    if !fulfilled {
      fulfilled = true
      promise.fail(error)
    }
    context.fireErrorCaught(error)
  }

  func channelInactive(context: ChannelHandlerContext) {
    if !fulfilled {
      fulfilled = true
      promise.fail(Ocp1Error.notConnected)
    }
    context.fireChannelInactive()
  }
}

#endif
