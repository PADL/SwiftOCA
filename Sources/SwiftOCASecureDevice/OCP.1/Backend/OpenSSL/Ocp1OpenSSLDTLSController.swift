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

import AsyncExtensions
public import IORing
internal import IORingUtils
import SocketAddress
@_spi(SwiftOCAPrivate)
import SwiftOCADevice
import SwiftOCASecure
@_spi(SwiftOCAPrivate)
import SwiftOCA
import struct SystemPackage.Errno
import Synchronization

/// Per-peer DTLS controller. The endpoint demuxes inbound datagrams by peer
/// address and pushes each through `ingestDatagram`; the shared UDP socket
/// is owned by the endpoint, so there's no per-controller receive loop.
package actor Ocp1OpenSSLDTLSController: Ocp1ControllerInternal,
  Ocp1ControllerDatagramSemantics,
  CustomStringConvertible
{
  package nonisolated let flags: OcaControllerFlags
  package nonisolated let connectionPrefix: String
  package nonisolated let identifier: String
  package nonisolated let peerAddress: AnySocketAddress
  /// DTLS controllers are constructed before the handshake, so identity
  /// starts `.anonymous` and is filled once `isHandshakeComplete` flips.
  private let _peerIdentity = Mutex<OcaPeerIdentity>(.anonymous)
  package nonisolated var peerIdentity: OcaPeerIdentity {
    _peerIdentity.withLock { $0 }
  }

  package var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  package var keepAliveTask: Task<(), Error>?
  package var lastMessageReceivedTime = ContinuousClock.recentPast
  package var lastMessageSentTime = ContinuousClock.recentPast
  package private(set) var isOpen: Bool = false
  package weak var endpoint: Ocp1OpenSSLDTLSDeviceEndpoint?

  /// Used by the endpoint's idle GC; DTLS over UDP has no close signal,
  /// so without it each touched peer would pin engine state forever.
  private(set) var lastSeen: ContinuousClock.Instant = .now
  /// Bounds how long a never-completed handshake can squat on a slot.
  let createdAt: ContinuousClock.Instant = .now

  private let engine: Ocp1OpenSSLEngine
  private let datagramChannel: any Ocp1DatagramChannel
  private var retransmitTask: Task<Void, Never>?

  /// Endpoint feeds messages directly via `handle(messagePduData:from:)`;
  /// no per-controller stream to consume.
  package var messages: AnyAsyncSequence<Ocp1MessageList> {
    AsyncEmptySequence<Ocp1MessageList>().eraseToAnyAsyncSequence()
  }

  package var heartbeatTime = Duration.seconds(1) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  init(
    endpoint: Ocp1OpenSSLDTLSDeviceEndpoint,
    peerAddress: AnySocketAddress,
    engine: Ocp1OpenSSLEngine,
    datagramChannel: any Ocp1DatagramChannel
  ) {
    self.endpoint = endpoint
    self.peerAddress = peerAddress
    self.engine = engine
    self.datagramChannel = datagramChannel
    flags = [.supportsLocking, .hasTransportLayerSecurity]
    connectionPrefix = OcaSecureUdpConnectionPrefix
    identifier = (try? peerAddress.presentationAddress) ?? "unknown"
  }

  /// Poll the engine's DTLS retransmit timer until handshake completion,
  /// so a peer that goes silent mid-handshake doesn't strand pending records.
  func startRetransmitWatchdog() {
    guard retransmitTask == nil else { return }
    let engine = engine
    let channel = datagramChannel
    retransmitTask = Task<Void, Never> {
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(200))
        if Task.isCancelled { return }
        if await engine.isHandshakeComplete { return }
        _ = try? await engine.handleDatagramTimeout { encrypted in
          try await channel.send(encrypted)
        }
      }
    }
  }

  /// Feed one inbound datagram through the engine. Returns plaintext when
  /// the datagram completed application data, `nil` for pure handshake.
  func ingestDatagram(_ data: Data) async throws -> Data? {
    let channel = datagramChannel
    lastSeen = .now
    let plaintext = try await engine.ingestDatagram(data) { encrypted in
      try await channel.send(encrypted)
    }
    // Snapshot the engine identity once so authz checks don't have to
    // re-enter the engine actor.
    if case .anonymous = peerIdentity, await engine.isHandshakeComplete {
      let captured = await engine.peerIdentity()
      _peerIdentity.withLock { $0 = captured }
    }
    return plaintext
  }

  /// `true` when the peer has been silent for at least `idleAfter`.
  func isIdle(now: ContinuousClock.Instant, idleAfter: Duration) -> Bool {
    now - lastSeen >= idleAfter
  }

  /// Surfaced so the endpoint's GC can evict stuck handshakes faster than
  /// just-idle fully-authenticated peers.
  func handshakeComplete() async -> Bool {
    await engine.isHandshakeComplete
  }

  package func sendOcp1EncodedData(_ data: Data) async throws {
    let channel = datagramChannel
    _ = try await engine.write(
      data,
      // Post-handshake SSL_write should never need to pull bytes —
      // DTLS doesn't renegotiate. Fail loudly if it ever does.
      read: { _ in throw Ocp1Error.notConnected },
      write: { encrypted in try await channel.send(encrypted) }
    )
  }

  package func close() async throws {
    retransmitTask?.cancel()
    retransmitTask = nil
    keepAliveTask?.cancel()
    keepAliveTask = nil
    await datagramChannel.close()
  }

  isolated deinit {
    retransmitTask?.cancel()
    keepAliveTask?.cancel()
  }

  package func didOpen() {
    isOpen = true
  }

  package nonisolated var description: String {
    "\(type(of: self))(\(identifier))"
  }
}

extension Ocp1OpenSSLDTLSController: Equatable {
  package nonisolated static func == (
    lhs: Ocp1OpenSSLDTLSController,
    rhs: Ocp1OpenSSLDTLSController
  ) -> Bool {
    lhs.peerAddress == rhs.peerAddress
  }
}

extension Ocp1OpenSSLDTLSController: Hashable {
  package nonisolated func hash(into hasher: inout Hasher) {
    peerAddress.hash(into: &hasher)
  }
}

#endif
