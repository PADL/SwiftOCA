//
// Copyright (c) 2024-2026 PADL Software Pty Ltd
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

#if canImport(SwiftMsQuicHelper)

import AsyncAlgorithms
import AsyncExtensions
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftMsQuicHelper
@_spi(SwiftOCAPrivate)
import SwiftOCA
import Synchronization

actor Ocp1QuicController: Ocp1ControllerInternal, CustomStringConvertible {
  nonisolated var flags: OcaControllerFlags { .supportsLocking }
  nonisolated let connectionPrefix = OcaTcpConnectionPrefix

  var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  var keepAliveTask: Task<(), Error>?
  var lastMessageReceivedTime = ContinuousClock.recentPast
  var lastMessageSentTime = ContinuousClock.recentPast
  weak var endpoint: Ocp1QuicDeviceEndpoint?

  var messages: AnyAsyncSequence<Ocp1MessageList> {
    _messages.eraseToAnyAsyncSequence()
  }

  private let _messages: AsyncThrowingStream<Ocp1MessageList, Error>
  private let _messagesContinuation: AsyncThrowingStream<Ocp1MessageList, Error>.Continuation
  private let _connection: Mutex<QuicConnection?>
  private let _peerAddress: String
  private var receiveMessageTask: Task<(), Never>?

  nonisolated var description: String {
    "\(type(of: self))(address: \(_peerAddress))"
  }

  init(
    endpoint: Ocp1QuicDeviceEndpoint,
    connection: QuicConnection
  ) {
    self.endpoint = endpoint
    _connection = .init(connection)

    (_messages, _messagesContinuation) = AsyncThrowingStream.makeStream(
      of: Ocp1MessageList.self,
      throwing: Error.self
    )

    if let remoteAddress = try? connection.getRemoteAddress() {
      _peerAddress = remoteAddress.description
    } else {
      _peerAddress = "unknown"
    }

    connection.onPeerStreamStarted { [weak self] _, stream, _ in
      guard let self else { return }
      await self._receiveFromStream(stream)
    }
  }

  func start() {
    receiveMessageTask = Task { [weak self] in
      guard let self else { return }
      await withTaskCancellationHandler {
        await Task.yield()
      } onCancel: {
        Task { [weak self] in
          self?._messagesContinuation.finish()
        }
      }
    }
  }

  nonisolated func isConnection(_ connection: QuicConnection) -> Bool {
    _connection.withLock { $0 === connection }
  }

  func addPeerStream(_ stream: QuicStream) {
    Task { [weak self] in
      guard let self else { return }
      await self._receiveFromStream(stream)
    }
  }

  private func _receiveFromStream(_ stream: QuicStream) async {
    do {
      var buffer = Data()
      for try await chunk in stream.receive {
        buffer.append(chunk)

        while buffer.count >= Ocp1Connection.MinimumPduSize {
          guard buffer[buffer.startIndex] == Ocp1SyncValue else {
            throw Ocp1Error.invalidSyncValue
          }
          let pduSize: OcaUint32 = buffer.decodeInteger(index: buffer.startIndex + 3)
          guard pduSize >= (Ocp1Connection.MinimumPduSize - 1) else {
            throw Ocp1Error.invalidPduSize
          }
          let totalLength = Int(pduSize) + 1
          guard buffer.count >= totalLength else { break }

          let pduData = buffer.prefix(totalLength)
          let messageList = try Ocp1MessageList(messagePduData: Data(pduData))
          _messagesContinuation.yield(messageList)
          buffer.removeFirst(totalLength)
        }
      }
    } catch {
      _messagesContinuation.finish(throwing: error)
    }
  }

  private func _takeConnection() -> QuicConnection? {
    _connection.withLock {
      let conn = $0
      $0 = nil
      return conn
    }
  }

  var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  func sendOcp1EncodedData(_ data: Data) async throws {
    guard let connection = _connection.withLock({ $0 }) else {
      throw Ocp1Error.notConnected
    }
    let stream = try connection.openStream()
    try await stream.start()
    try await stream.send(data, flags: .fin)
  }

  func close() async {
    keepAliveTask?.cancel()
    keepAliveTask = nil

    if let connection = _takeConnection() {
      await connection.shutdown()
    }

    receiveMessageTask?.cancel()
    receiveMessageTask = nil

    _messagesContinuation.finish()
  }

  deinit {
    receiveMessageTask?.cancel()
    keepAliveTask?.cancel()
    _messagesContinuation.finish()
  }

  nonisolated var identifier: String {
    _peerAddress
  }
}

extension Ocp1QuicController: Equatable {
  nonisolated static func == (
    lhs: Ocp1QuicController,
    rhs: Ocp1QuicController
  ) -> Bool {
    lhs._peerAddress == rhs._peerAddress
  }
}

extension Ocp1QuicController: Hashable {
  nonisolated func hash(into hasher: inout Hasher) {
    _peerAddress.hash(into: &hasher)
  }
}

#endif
