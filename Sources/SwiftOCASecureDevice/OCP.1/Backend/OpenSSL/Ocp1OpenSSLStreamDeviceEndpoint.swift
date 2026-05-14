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

import AsyncAlgorithms
@preconcurrency
import AsyncExtensions
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Glibc

public import IORing
internal import IORingUtils

import Logging
import SocketAddress
@_spi(SwiftOCAPrivate)
import SwiftOCADevice
import SwiftOCASecure
@_spi(SwiftOCAPrivate)
import SwiftOCA
import struct SystemPackage.Errno

/// TLS-secured OCP.1 stream device endpoint backed by OpenSSL on Linux.
/// Sibling of `Ocp1NWSecureTCPDeviceEndpoint`. PSKs come from
/// `device.securityManager` and the provider is held by reference, so
/// runtime additions take effect on the next handshake.
@OcaDevice
public final class Ocp1OpenSSLStreamDeviceEndpoint: Ocp1IORingDeviceEndpoint,
  @preconcurrency OcaDeviceEndpointPrivate
{
  package typealias ControllerType = Ocp1OpenSSLStreamController

  private let serverCredential: Ocp1TLSCredential?
  /// Non-nil enables mTLS.
  private let clientCertificateTrustRoots: Ocp1TLSTrustRoots?
  private let _revocation: Ocp1TLSRevocationOptions
  private let _maxConnections: Int
  private let _handshakeTimeout: Duration
  let firstMessageDeadline: Duration
  private var _serverPSKProvider: (any OcaPreSharedKeyProvider)?
  private var _controllers: [Ocp1OpenSSLStreamController] = []
  /// Counted against `maxConnections` along with completed controllers so
  /// slow-loris peers can't exhaust the engine/fd budget mid-handshake.
  private var _pendingHandshakes: Int = 0

  override public var controllers: [OcaController] { _controllers }

  /// Binds the listening socket eagerly so callers passing port 0 can read
  /// the kernel-assigned port via the inherited `port` property after init.
  public init(
    address: any SocketAddress,
    credential: Ocp1TLSCredential? = nil,
    clientCertificateTrustRoots: Ocp1TLSTrustRoots? = nil,
    revocation: Ocp1TLSRevocationOptions = .disabled,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCASecureDevice.Ocp1OpenSSLStreamDeviceEndpoint"),
    maxConnections: Int = 1024,
    handshakeTimeout: Duration = .seconds(10),
    firstMessageDeadline: Duration = .seconds(30),
    ring: IORing = .shared
  ) async throws {
    if let credential {
      try credential.validate()
    }
    try Ocp1OpenSSLEngine.validateTrustRoots(clientCertificateTrustRoots)
    serverCredential = credential
    self.clientCertificateTrustRoots = clientCertificateTrustRoots
    _revocation = revocation
    _maxConnections = maxConnections
    _handshakeTimeout = handshakeTimeout
    self.firstMessageDeadline = firstMessageDeadline

    let socket = try Socket(
      ring: ring,
      domain: address.family,
      type: Glibc.SOCK_STREAM,
      protocol: 0
    )
    switch Int32(address.family) {
    case AF_INET6:
      try socket.setIPv6Only()
      fallthrough
    case AF_INET:
      try socket.setReuseAddr()
      try socket.setTcpNoDelay()
    default:
      break
    }
    try socket.bind(to: address)
    let boundAddress = try socket.localAddress

    try await super.init(
      address: boundAddress,
      timeout: timeout,
      device: device,
      logger: logger,
      ring: ring
    )
    self.socket = socket
  }

  public convenience init(
    port: UInt16,
    credential: Ocp1TLSCredential? = nil,
    clientCertificateTrustRoots: Ocp1TLSTrustRoots? = nil,
    revocation: Ocp1TLSRevocationOptions = .disabled,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCASecureDevice.Ocp1OpenSSLStreamDeviceEndpoint"),
    maxConnections: Int = 1024,
    handshakeTimeout: Duration = .seconds(10),
    firstMessageDeadline: Duration = .seconds(30),
    ring: IORing = .shared
  ) async throws {
    var sin = sockaddr_in()
    sin.sin_family = sa_family_t(AF_INET)
    sin.sin_port = port.bigEndian
    sin.sin_addr.s_addr = UInt32(0).bigEndian // INADDR_ANY
    try await self.init(
      address: sin,
      credential: credential,
      clientCertificateTrustRoots: clientCertificateTrustRoots,
      revocation: revocation,
      timeout: timeout,
      device: device,
      logger: logger,
      maxConnections: maxConnections,
      handshakeTimeout: handshakeTimeout,
      firstMessageDeadline: firstMessageDeadline,
      ring: ring
    )
  }

  override public func run() async throws {
    logger.info("starting \(type(of: self)) on \(address._presentationAddress)")
    if clientCertificateTrustRoots != nil {
      logger.info("\(type(of: self)) requires client certificates (mTLS)")
    }
    try await super.run()
    _serverPSKProvider = await device.securityManager

    guard let socket else {
      throw Ocp1Error.notConnected
    }
    try socket.listen()

    repeat {
      do {
        let clients: AnyAsyncSequence<Socket> = try await socket.accept()
        do {
          for try await client in clients {
            Task { [weak self] in
              guard let self else { return }
              await self.runAccepted(client: client)
            }
          }
        } catch let error where error as? Errno == Errno.invalidArgument {
          logger.warning(
            "invalid argument when accepting connections, check kernel version supports multishot accept with io_uring"
          )
          break
        }
      } catch let error where error as? Errno == Errno.canceled {
        logger.debug("received cancelation, trying to accept() again")
      } catch {
        logger.info("received error \(error), bailing")
        break
      }
      if Task.isCancelled {
        logger.info("\(type(of: self)) cancelled, stopping")
        break
      }
    } while true

    self.socket = nil
    try await device.remove(endpoint: self)
  }

  /// Per-connection handshake + controller handoff. Each accepted socket
  /// gets its own engine so one handshake failure doesn't poison the listener.
  private func runAccepted(client: Socket) async {
    if _controllers.count + _pendingHandshakes >= _maxConnections {
      logger.warning(
        "TLS connection cap (\(_maxConnections)) reached (in-flight handshakes: \(_pendingHandshakes)); refusing new client"
      )
      return
    }
    _pendingHandshakes += 1
    defer { _pendingHandshakes -= 1 }
    let engine: Ocp1OpenSSLEngine
    do {
      engine = try Ocp1OpenSSLEngine(
        mode: .server,
        credential: serverCredential,
        serverPSKProvider: _serverPSKProvider,
        clientTrustRoots: clientCertificateTrustRoots,
        revocation: _revocation
      )
    } catch {
      logger.warning("could not initialize TLS engine: \(error)")
      return
    }

    let peerAddress: AnySocketAddress
    do {
      peerAddress = try AnySocketAddress(client.peerAddress)
    } catch {
      logger.warning("could not read peer address from accepted socket: \(error)")
      return
    }

    let stream: any Ocp1ByteStream = IORingByteStream(socket: client)

    // Bound the handshake so a peer that stalls mid-flight doesn't pin
    // engine state until the connection drops.
    do {
      try await withThrowingTimeout(of: _handshakeTimeout, clock: .continuous) {
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
      }
    } catch {
      logger.warning("TLS handshake failed or timed out: \(error)")
      return
    }

    do {
      let controller = try await Ocp1OpenSSLStreamController(
        endpoint: self,
        stream: stream,
        peerAddress: peerAddress,
        engine: engine
      )
      await controller.handle(for: self)
    } catch {
      logger.warning("controller setup failed: \(error)")
    }
  }

  #if canImport(dnssd)
  override public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    .tcpSecure
  }
  #endif

  package func add(controller: Ocp1OpenSSLStreamController) async {
    _controllers.append(controller)
  }

  package func remove(controller: Ocp1OpenSSLStreamController) async {
    _controllers.removeAll(where: { $0 == controller })
  }
}

#endif
