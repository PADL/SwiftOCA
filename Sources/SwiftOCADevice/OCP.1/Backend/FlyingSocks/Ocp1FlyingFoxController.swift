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

#if canImport(FlyingFox)

import AsyncExtensions
import FlyingFox
import FlyingSocks
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftOCA

/// A remote WebSocket endpoint
actor Ocp1FlyingFoxController: Ocp1ControllerInternal, CustomStringConvertible {
  nonisolated var flags: OcaControllerFlags { .supportsLocking }
  nonisolated var connectionPrefix: String { OcaWebSocketTcpConnectionPrefix }

  var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()

  private let _messages: AsyncThrowingStream<Ocp1MessageList, Error>
  private let outputStream: AsyncStream<WSMessage>.Continuation
  var endpoint: Ocp1FlyingFoxDeviceEndpoint?

  var keepAliveTask: Task<(), Error>?
  var lastMessageReceivedTime = ContinuousClock.recentPast
  var lastMessageSentTime = ContinuousClock.recentPast

  var messages: AsyncExtensions.AnyAsyncSequence<Ocp1MessageList> {
    _messages.eraseToAnyAsyncSequence()
  }

  init(
    endpoint: Ocp1FlyingFoxDeviceEndpoint?,
    inputStream: AsyncStream<WSMessage>,
    outputStream: AsyncStream<WSMessage>.Continuation
  ) {
    self.outputStream = outputStream
    self.endpoint = endpoint
    _messages = AsyncThrowingStream { continuation in
      let task = Task { [inputStream] in
        do {
          for await message in inputStream {
            guard case let .data(data) = message else {
              throw Ocp1Error.invalidMessageType
            }

            try continuation.yield(Ocp1MessageList(messagePduData: data))
          }

          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }

  var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  func sendOcp1EncodedData(_ data: Data) async throws {
    outputStream.yield(.data(data))
  }

  func close() async {
    outputStream.finish()

    keepAliveTask?.cancel()
    keepAliveTask = nil
  }

  deinit {
    keepAliveTask?.cancel()
    outputStream.finish()
  }

  nonisolated var identifier: String {
    String(describing: id)
  }

  nonisolated var description: String {
    "\(type(of: self))(id: \(id))"
  }
}

#endif
