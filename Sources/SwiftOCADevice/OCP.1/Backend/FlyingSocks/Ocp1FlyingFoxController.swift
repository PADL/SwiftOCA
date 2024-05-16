//
// Copyright (c) 2024 PADL Software Pty Ltd
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

#if os(macOS) || os(iOS)

import AsyncExtensions
import FlyingFox
import FlyingSocks
import Foundation
import SwiftOCA

fileprivate extension AsyncStream where Element == WSMessage {
  var ocp1DecodedMessages: AnyAsyncSequence<Ocp1ControllerInternal.ControllerMessage> {
    flatMap {
      // TODO: handle OCP.1 PDUs split over multiple frames
      guard case let .data(data) = $0 else {
        throw Ocp1Error.invalidMessageType
      }

      var messagePdus = [Data]()
      let messageType = try Ocp1Connection.decodeOcp1MessagePdu(
        from: data,
        messages: &messagePdus
      )
      let messages = try messagePdus.map {
        try Ocp1Connection.decodeOcp1Message(from: $0, type: messageType)
      }

      return messages.map { ($0, messageType == .ocaCmdRrq) }.async
    }.eraseToAnyAsyncSequence()
  }
}

/// A remote WebSocket endpoint
actor Ocp1FlyingFoxController: Ocp1ControllerInternal, CustomStringConvertible {
  nonisolated var connectionPrefix: String { OcaWebSocketTcpConnectionPrefix }

  var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()

  private let inputStream: AsyncStream<WSMessage>
  private let outputStream: AsyncStream<WSMessage>.Continuation
  var endpoint: Ocp1FlyingFoxDeviceEndpoint?

  var keepAliveTask: Task<(), Error>?
  var lastMessageReceivedTime = ContinuousClock.now
  var lastMessageSentTime = ContinuousClock.now

  var messages: AsyncExtensions.AnyAsyncSequence<ControllerMessage> {
    inputStream.ocp1DecodedMessages.eraseToAnyAsyncSequence()
  }

  init(
    endpoint: Ocp1FlyingFoxDeviceEndpoint?,
    inputStream: AsyncStream<WSMessage>,
    outputStream: AsyncStream<WSMessage>.Continuation
  ) {
    self.inputStream = inputStream
    self.outputStream = outputStream
    self.endpoint = endpoint
  }

  var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  func onConnectionBecomingStale() async {
    await close()
  }

  func sendOcp1EncodedData(_ data: Data) async throws {
    outputStream.yield(.data(data))
  }

  func close() async {
    outputStream.finish()

    keepAliveTask?.cancel()
    keepAliveTask = nil
  }

  nonisolated var identifier: String {
    String(describing: id)
  }

  public nonisolated var description: String {
    "\(type(of: self))(id: \(id))"
  }
}

#endif
