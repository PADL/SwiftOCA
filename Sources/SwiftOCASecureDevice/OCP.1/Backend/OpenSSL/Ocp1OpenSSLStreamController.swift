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
import AsyncExtensions
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
@_spi(SwiftOCAPrivate)
import SwiftOCADevice
import SwiftOCASecure
import struct SystemPackage.Errno

/// Remote controller connected via TLS-wrapped TCP on Linux. The endpoint
/// hands off the post-handshake engine; from here all bytes route through
/// the engine's BIO pair.
package actor Ocp1OpenSSLStreamController: Ocp1ControllerInternal, CustomStringConvertible {
  package nonisolated let flags: OcaControllerFlags
  package nonisolated let connectionPrefix: String
  package nonisolated let identifier: String
  package nonisolated let peerAddress: AnySocketAddress
  /// Snapshotted at handshake completion, immutable thereafter.
  package nonisolated let peerIdentity: OcaPeerIdentity

  package var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  package var keepAliveTask: Task<(), Error>?
  package var lastMessageReceivedTime = ContinuousClock.recentPast
  package var lastMessageSentTime = ContinuousClock.recentPast
  package weak var endpoint: Ocp1OpenSSLStreamDeviceEndpoint?

  /// Nilled by `close()` so subsequent sends bail with `.notConnected`.
  /// The receive task captures its own reference at init.
  private var _stream: (any Ocp1ByteStream)?
  private let engine: Ocp1OpenSSLEngine
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
    endpoint: Ocp1OpenSSLStreamDeviceEndpoint,
    stream: any Ocp1ByteStream,
    peerAddress: AnySocketAddress,
    engine: Ocp1OpenSSLEngine
  ) async throws {
    self.endpoint = endpoint
    _stream = stream
    self.engine = engine
    flags = [.supportsLocking, .hasTransportLayerSecurity]
    connectionPrefix = OcaSecureTcpConnectionPrefix
    self.peerAddress = peerAddress
    identifier = (try? peerAddress.presentationAddress) ?? "unknown"
    peerIdentity = await engine.peerIdentity()

    (_messages, _messagesContinuation) = AsyncThrowingStream.makeStream(
      of: Ocp1MessageList.self,
      throwing: Error.self
    )

    // Capture refs so the receive task avoids re-entering the actor on
    // every read. `close()` cancels the task and closes the stream.
    let streamRef: any Ocp1ByteStream = stream
    let engineRef = engine
    let continuationRef = _messagesContinuation
    receiveMessageTask = Task { [weak self] in
      do {
        repeat {
          guard !Task.isCancelled else { break }
          let messages = try await OcaDevice.receiveMessages { count in
            try await engineRef.read(
              count,
              read: { c in try await streamRef.read(count: c, awaitingAllRead: false) },
              write: { d in try await streamRef.write(d) }
            )
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
    guard let stream = _stream else {
      throw Ocp1Error.notConnected
    }
    _ = try await engine.write(
      data,
      read: { c in try await stream.read(count: c, awaitingAllRead: false) },
      write: { d in try await stream.write(d) }
    )
  }

  package func close() async throws {
    keepAliveTask?.cancel()
    keepAliveTask = nil
    firstMessageTask?.cancel()
    firstMessageTask = nil

    let stream = _stream
    _stream = nil
    receiveMessageTask?.cancel()
    if let receiveMessageTask {
      _ = await receiveMessageTask.value
      self.receiveMessageTask = nil
    }
    if let stream {
      try? await engine.shutdown(
        read: { c in try await stream.read(count: c, awaitingAllRead: false) },
        write: { d in try await stream.write(d) }
      )
      await stream.close()
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

extension Ocp1OpenSSLStreamController: Equatable {
  package nonisolated static func == (
    lhs: Ocp1OpenSSLStreamController,
    rhs: Ocp1OpenSSLStreamController
  ) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }
}

extension Ocp1OpenSSLStreamController: Hashable {
  package nonisolated func hash(into hasher: inout Hasher) {
    ObjectIdentifier(self).hash(into: &hasher)
  }
}

#endif
