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
import AsyncExtensions
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore
import NIOSSL
@_spi(SwiftOCAPrivate)
import SwiftOCA
@_spi(SwiftOCAPrivate)
import SwiftOCADevice
import SwiftOCASecure

/// Remote controller connected via NIO + NIOSSL. Built post-handshake from
/// an accepted child `Channel`; mirrors `Ocp1OpenSSLStreamController`.
package actor Ocp1NIOSecureTCPController: Ocp1ControllerInternal, CustomStringConvertible {
  package nonisolated let flags: OcaControllerFlags
  package nonisolated let connectionPrefix: String
  package nonisolated let identifier: String
  /// Snapshotted at handshake completion, immutable thereafter.
  package nonisolated let peerIdentity: OcaPeerIdentity

  package var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  package var keepAliveTask: Task<(), Error>?
  package var lastMessageReceivedTime = ContinuousClock.recentPast
  package var lastMessageSentTime = ContinuousClock.recentPast
  package weak var endpoint: Ocp1NIOSecureTCPDeviceEndpoint?

  /// Nilled by `close()` so subsequent sends bail with `.notConnected`.
  private var _channel: (any Channel)?
  private let _bridge: Ocp1NIOByteBufferBridge
  private let _messages: AsyncThrowingStream<Ocp1MessageList, Error>
  private let _messagesContinuation: AsyncThrowingStream<Ocp1MessageList, Error>.Continuation
  private var receiveMessageTask: Task<(), Never>?
  /// Closes the connection if no message arrives within the endpoint's
  /// `firstMessageDeadline`; cancelled on the first inbound message.
  private var firstMessageTask: Task<Void, Never>?
  private let createdAt: ContinuousClock.Instant = .now

  package var messages: AnyAsyncSequence<Ocp1MessageList> {
    _messages.eraseToAnyAsyncSequence()
  }

  package var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  init(
    endpoint: Ocp1NIOSecureTCPDeviceEndpoint,
    channel: any Channel,
    bridge: Ocp1NIOByteBufferBridge,
    peerIdentity: OcaPeerIdentity,
    identifier: String
  ) async throws {
    self.endpoint = endpoint
    _channel = channel
    _bridge = bridge
    flags = [.supportsLocking, .hasTransportLayerSecurity]
    connectionPrefix = OcaSecureTcpConnectionPrefix
    self.peerIdentity = peerIdentity
    self.identifier = identifier

    (_messages, _messagesContinuation) = AsyncThrowingStream.makeStream(
      of: Ocp1MessageList.self,
      throwing: Error.self
    )

    let bridgeRef = _bridge
    let continuationRef = _messagesContinuation
    receiveMessageTask = Task { [weak self] in
      do {
        repeat {
          guard !Task.isCancelled else { break }
          let messages = try await OcaDevice.receiveMessages { count in
            try await bridgeRef.read(count)
          }
          await self?.noteMessageReceived()
          continuationRef.yield(messages)
        } while true
      } catch {
        continuationRef.finish(throwing: error)
      }
    }

    let deadline = endpoint.firstMessageDeadline
    firstMessageTask = Task<Void, Never> { [weak self] in
      try? await Task.sleep(for: deadline)
      if Task.isCancelled { return }
      guard let self else { return }
      await self.enforceFirstMessageDeadline()
    }
  }

  private func noteMessageReceived() {
    if let task = firstMessageTask {
      task.cancel()
      firstMessageTask = nil
    }
  }

  private func enforceFirstMessageDeadline() async {
    if firstMessageTask == nil { return }
    firstMessageTask = nil
    if lastMessageReceivedTime > createdAt { return }
    if let endpoint = await self.endpoint {
      endpoint.logger.warning(
        "TLS peer \(identifier) did not send a message within first-message deadline; closing"
      )
    }
    try? await close()
  }

  package func sendOcp1EncodedData(_ data: Data) async throws {
    guard let channel = _channel else {
      throw Ocp1Error.notConnected
    }
    var buffer = channel.allocator.buffer(capacity: data.count)
    buffer.writeBytes(data)
    do {
      try await channel.writeAndFlush(buffer).get()
    } catch {
      throw Ocp1Error.notConnected
    }
  }

  package func close() async throws {
    keepAliveTask?.cancel()
    keepAliveTask = nil
    firstMessageTask?.cancel()
    firstMessageTask = nil

    let channel = _channel
    _channel = nil
    receiveMessageTask?.cancel()
    if let receiveMessageTask {
      _ = await receiveMessageTask.value
      self.receiveMessageTask = nil
    }
    _bridge.close()
    if let channel {
      try? await channel.close(mode: .all).get()
    }
    _messagesContinuation.finish()
  }

  deinit {
    receiveMessageTask?.cancel()
    keepAliveTask?.cancel()
    firstMessageTask?.cancel()
    _messagesContinuation.finish()
  }

  package nonisolated var description: String {
    "\(type(of: self))(\(identifier))"
  }
}

extension Ocp1NIOSecureTCPController: Equatable {
  package nonisolated static func == (
    lhs: Ocp1NIOSecureTCPController,
    rhs: Ocp1NIOSecureTCPController
  ) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }
}

extension Ocp1NIOSecureTCPController: Hashable {
  package nonisolated func hash(into hasher: inout Hasher) {
    ObjectIdentifier(self).hash(into: &hasher)
  }
}

#endif
