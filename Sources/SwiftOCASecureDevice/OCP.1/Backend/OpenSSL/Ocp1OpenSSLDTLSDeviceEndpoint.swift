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

/// DTLS-secured OCP.1 datagram device endpoint backed by OpenSSL on Linux.
/// A single bound SOCK_DGRAM socket; inbound datagrams are demultiplexed by
/// peer address into per-peer engines. HelloVerifyRequest cookie exchange
/// runs in the engine but allocates per-peer state on the first ClientHello;
/// `maxPeers`, the per-source rate limit, and the optional source-address
/// filter below contain that exposure. We do *not* implement a stateless
/// pre-cookie path — see Documentation/TLS.md for the rationale.
public struct Ocp1OpenSSLDTLSEndpointOptions: Sendable {
  /// Peers that don't finish the DTLS handshake within this window are
  /// evicted by the GC sweep.
  public var handshakeDeadline: Duration

  /// Silence ceiling — peers evicted after this long without an inbound
  /// datagram. GC floors against `heartbeatTime × 3` so a deployment with
  /// long heartbeats doesn't trip on jitter.
  public var idleTimeout: Duration

  /// Soft cap on simultaneous peer engines; backstops the pre-cookie
  /// ClientHello state-pinning vector.
  public var maxPeers: Int

  /// Pre-cookie source-address gate. Called once per new peer before any
  /// per-peer engine is allocated; returning `false` drops the datagram.
  /// `nil` accepts every source. The closure receives the raw `sockaddr`
  /// bytes of the inbound peer so callers can implement subnet allowlists
  /// or AF-specific rules.
  public var sourceAddressFilter: (@Sendable (Data) -> Bool)?

  /// IORing receive buffer pool size; `nil` uses the IORing default.
  public var bufferCount: Int?

  public init(
    handshakeDeadline: Duration = .seconds(10),
    idleTimeout: Duration = .seconds(300),
    maxPeers: Int = 256,
    sourceAddressFilter: (@Sendable (Data) -> Bool)? = nil,
    bufferCount: Int? = nil
  ) {
    self.handshakeDeadline = handshakeDeadline
    self.idleTimeout = idleTimeout
    self.maxPeers = maxPeers
    self.sourceAddressFilter = sourceAddressFilter
    self.bufferCount = bufferCount
  }
}

@OcaDevice
public final class Ocp1OpenSSLDTLSDeviceEndpoint: Ocp1IORingDeviceEndpoint,
  @preconcurrency OcaDeviceEndpointPrivate
{
  package typealias ControllerType = Ocp1OpenSSLDTLSController

  private let serverCredential: Ocp1TLSCredential?
  private let clientCertificateTrustRoots: Ocp1TLSTrustRoots?
  private let _revocation: Ocp1TLSRevocationOptions
  private var _serverPSKProvider: (any OcaPreSharedKeyProvider)?
  private var _controllers: [AnySocketAddress: Ocp1OpenSSLDTLSController] = [:]
  private let _options: Ocp1OpenSSLDTLSEndpointOptions
  private let _firstMessageDeadline: Duration
  private var _gcTask: Task<Void, Never>?

  /// Per-source-IP engine allocation count for the current window — throttles
  /// spoofed-source ClientHello floods, since OpenSSL allocates engine state
  /// before its HelloVerifyRequest cookie callback fires. Keyed on IP only
  /// (not IP+port) so attackers can't bypass by rotating source ports.
  private var _perSourceAllocations: [String: Int] = [:]
  private var _allocationWindowStart: ContinuousClock.Instant = .now
  private static let allocationWindow: Duration = .seconds(10)
  /// A legitimate peer only needs one allocation per window (it retries the
  /// same flight inside the existing engine after cookie verify); 2 leaves
  /// a small jitter margin for restart-and-reconnect races.
  private static let maxAllocationsPerSourcePerWindow: Int = 2

  override public var controllers: [OcaController] {
    Array(_controllers.values)
  }

  public init(
    address: any SocketAddress,
    credential: Ocp1TLSCredential? = nil,
    clientCertificateTrustRoots: Ocp1TLSTrustRoots? = nil,
    revocation: Ocp1TLSRevocationOptions = .disabled,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCASecureDevice.Ocp1OpenSSLDTLSDeviceEndpoint"),
    options: Ocp1OpenSSLDTLSEndpointOptions = Ocp1OpenSSLDTLSEndpointOptions(),
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
    _options = options
    _firstMessageDeadline = firstMessageDeadline

    let socket = try Socket(
      ring: ring,
      domain: address.family,
      type: Glibc.SOCK_DGRAM,
      protocol: 0
    )
    if address.family == sa_family_t(AF_INET6) {
      try socket.setIPv6Only()
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
    logger: Logger = Logger(label: "com.padl.SwiftOCASecureDevice.Ocp1OpenSSLDTLSDeviceEndpoint"),
    options: Ocp1OpenSSLDTLSEndpointOptions = Ocp1OpenSSLDTLSEndpointOptions(),
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
      options: options,
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

    startGCSweep()

    let receiveBufferSize = Ocp1MaximumDatagramPduSize

    repeat {
      do {
        let messagePdus = try await socket.receiveMessages(
          count: receiveBufferSize,
          capacity: _options.bufferCount
        )
        for try await messagePdu in messagePdus {
          let peerAddress = try AnySocketAddress(bytes: messagePdu.name)
          let payload = Data(messagePdu.buffer)
          guard let controller = try? controller(for: peerAddress) else { continue }
          spawnPeerIngest(payload: payload, controller: controller, peerAddress: peerAddress)
        }
      } catch let error as Errno {
        guard error == .canceled || error == .noBufferSpace else { throw error }
      } catch {
        logger.error(
          "unexpected error \(error) in \(type(of: self)) on \(address._presentationAddress); no longer servicing"
        )
        throw error
      }
    } while !Task.isCancelled

    _gcTask?.cancel()
    _gcTask = nil
    self.socket = nil
    try await device.remove(endpoint: self)
  }

  /// Outbound datagram fan-in. Per-peer engines drain `wbio` through here.
  func sendDatagram(_ data: Data, to peer: AnySocketAddress) async throws {
    guard let socket else {
      throw Ocp1Error.notConnected
    }
    try await socket.sendMessage(Message(address: peer, buffer: [UInt8](data)))
  }

  /// Spawn a Task that hands one datagram to its controller (serialised
  /// there) and routes decrypted output back through the endpoint.
  private nonisolated func spawnPeerIngest(
    payload: Data,
    controller: Ocp1OpenSSLDTLSController,
    peerAddress: AnySocketAddress
  ) {
    Task { [weak self] in
      guard let self else { return }
      do {
        let plaintext = try await controller.ingestDatagram(payload)
        if let plaintext {
          try await self.handle(messagePduData: plaintext, from: controller)
        }
      } catch {
        await self.peerErrored(
          controller: controller,
          peerAddress: peerAddress,
          error: error
        )
      }
    }
  }

  private func controller(
    for peerAddress: AnySocketAddress
  ) throws -> Ocp1OpenSSLDTLSController? {
    if let existing = _controllers[peerAddress] {
      return existing
    }
    // Pre-cookie source filter — cheaper than per-source rate limiting,
    // and runs before any allocation slot is consumed.
    if let filter = _options.sourceAddressFilter, !filter(peerAddress.data) {
      return nil
    }
    if !permitAllocation(for: peerAddress) {
      logger.warning(
        "DTLS allocation rate limit hit for \(peerAddress._presentationAddress); refusing"
      )
      return nil
    }
    if _controllers.count >= _options.maxPeers {
      logger.warning(
        "DTLS peer table at cap (\(_options.maxPeers)); refusing \(peerAddress._presentationAddress)"
      )
      creditAllocation(for: peerAddress)
      return nil
    }
    let engine: Ocp1OpenSSLEngine
    do {
      engine = try Ocp1OpenSSLEngine(
        mode: .server,
        credential: serverCredential,
        transport: .datagram,
        serverPSKProvider: _serverPSKProvider,
        clientTrustRoots: clientCertificateTrustRoots,
        revocation: _revocation,
        // Binds the HelloVerifyRequest cookie to the source address.
        peerAddressBytes: peerAddress.data
      )
    } catch {
      logger.warning("could not initialize DTLS engine for \(peerAddress._presentationAddress): \(error)")
      creditAllocation(for: peerAddress)
      return nil
    }
    let controller = Ocp1OpenSSLDTLSController(
      endpoint: self,
      peerAddress: peerAddress,
      engine: engine,
      datagramChannel: _EndpointDatagramChannel(endpoint: self, peer: peerAddress)
    )
    _controllers[peerAddress] = controller
    Task { await controller.startRetransmitWatchdog() }
    logger.info("DTLS controller added", controller: controller)
    return controller
  }

  /// Returns `false` and refuses allocation when this source has exceeded
  /// `maxAllocationsPerSourcePerWindow` within the current window. Fixed-
  /// window rollover. Callers MUST `creditAllocation` when a successful
  /// permit doesn't lead to an allocation (engine init throws, cap hit).
  private func permitAllocation(for peerAddress: AnySocketAddress) -> Bool {
    let now = ContinuousClock.now
    if now - _allocationWindowStart >= Self.allocationWindow {
      _perSourceAllocations.removeAll(keepingCapacity: true)
      _allocationWindowStart = now
    }
    let key = allocationKey(for: peerAddress)
    let current = _perSourceAllocations[key, default: 0]
    if current >= Self.maxAllocationsPerSourcePerWindow {
      return false
    }
    _perSourceAllocations[key] = current + 1
    return true
  }

  /// Refund a slot consumed by `permitAllocation` when the allocation
  /// didn't go through. Bounded at zero against stale post-rollover credits.
  private func creditAllocation(for peerAddress: AnySocketAddress) {
    let key = allocationKey(for: peerAddress)
    if let current = _perSourceAllocations[key], current > 0 {
      _perSourceAllocations[key] = current - 1
    }
  }

  private func allocationKey(for peerAddress: AnySocketAddress) -> String {
    (try? peerAddress.presentationAddressNoPort)
      ?? (try? peerAddress.presentationAddress)
      ?? ""
  }

  /// Log, remove the controller, and release any held resources via
  /// `unlockAndRemove`.
  private func peerErrored(
    controller: Ocp1OpenSSLDTLSController,
    peerAddress: AnySocketAddress,
    error: Error
  ) async {
    logger.warning("DTLS peer \(peerAddress._presentationAddress) error: \(error)")
    await unlockAndRemove(controller: controller)
    _controllers.removeValue(forKey: peerAddress)
  }

  /// Periodic sweep: evicts peers stuck mid-handshake, authenticated peers
  /// that never sent a KeepAlive, and peers that have gone silent. Cadence
  /// is tied to `handshakeDeadline` so a stuck slot is reclaimed within
  /// ~1.5× the deadline rather than the prior fixed 30 s (which was
  /// 3× the new 10 s default).
  private func startGCSweep() {
    _gcTask?.cancel()
    // Floor at 1 s so a misconfigured tiny deadline doesn't burn CPU.
    let cadence = max(_options.handshakeDeadline / 2, .seconds(1))
    _gcTask = Task<Void, Never> { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: cadence)
        if Task.isCancelled { return }
        await self?.runGCSweep()
      }
    }
  }

  private enum EvictionReason: String {
    case handshakeDeadline = "handshake-deadline"
    case firstMessageDeadline = "first-message-deadline"
    case idleTimeout = "idle-timeout"
  }

  private struct EvictionCandidate {
    let peer: AnySocketAddress
    let controller: Ocp1OpenSSLDTLSController
    let reason: EvictionReason
  }

  private func runGCSweep() async {
    let now = ContinuousClock.now
    var victims: [EvictionCandidate] = []
    for (peer, controller) in _controllers {
      let completed = await controller.handshakeComplete()
      let isOpen = await controller.isOpen
      let lastSeen = await controller.lastSeen
      let heartbeat = await controller.heartbeatTime
      let createdAt = controller.createdAt
      // Floor on three heartbeats so one missed heartbeat + jitter doesn't
      // trip eviction.
      let effectiveIdleTimeout = max(_options.idleTimeout, heartbeat * 3)
      let reason: EvictionReason?
      if !completed, now - createdAt >= _options.handshakeDeadline {
        reason = .handshakeDeadline
      } else if completed, !isOpen, now - createdAt >= _firstMessageDeadline {
        reason = .firstMessageDeadline
      } else if now - lastSeen >= effectiveIdleTimeout {
        reason = .idleTimeout
      } else {
        reason = nil
      }
      if let reason {
        victims.append(EvictionCandidate(peer: peer, controller: controller, reason: reason))
      }
    }
    for victim in victims {
      logger.info(
        "DTLS GC evicting peer \(victim.peer._presentationAddress) (\(victim.reason.rawValue))"
      )
      await unlockAndRemove(controller: victim.controller)
      _controllers.removeValue(forKey: victim.peer)
    }
  }

  #if canImport(dnssd)
  override public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    .udpSecure
  }
  #endif

  package func add(controller: Ocp1OpenSSLDTLSController) async {
    // Insertion happens in `controller(for:)`; this just satisfies the
    // protocol surface.
    _controllers[controller.peerAddress] = controller
  }

  package func remove(controller: Ocp1OpenSSLDTLSController) async {
    _controllers.removeValue(forKey: controller.peerAddress)
  }
}

#endif
