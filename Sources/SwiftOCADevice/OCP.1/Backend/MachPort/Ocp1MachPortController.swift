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

#if canImport(Darwin)

import AsyncExtensions
import Darwin.Mach
import Foundation
@_spi(SwiftOCAPrivate)
import SwiftOCA

actor Ocp1MachPortController: Ocp1ControllerInternal {
  nonisolated var flags: OcaControllerFlags { .supportsLocking }
  nonisolated var connectionPrefix: String { OcaMachPortConnectionPrefix }

  var lastMessageReceivedTime = ContinuousClock.recentPast
  var lastMessageSentTime = ContinuousClock.recentPast
  var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  var keepAliveTask: Task<(), Error>?

  weak var endpoint: Ocp1MachPortDeviceEndpoint?
  var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()

  /// our dedicated receive port for this controller session
  private let receiveHandle: Ocp1MachPortHandle
  /// send right to the client's receive port
  private let clientSendPort: mach_port_t
  private let _messages: AsyncThrowingStream<Ocp1MessageList, Error>

  nonisolated let identifier: String

  init(
    endpoint: Ocp1MachPortDeviceEndpoint,
    receiveHandle: Ocp1MachPortHandle,
    clientSendPort: mach_port_t,
    identifier: String
  ) {
    self.endpoint = endpoint
    self.receiveHandle = receiveHandle
    self.clientSendPort = clientSendPort
    self.identifier = identifier

    let (stream, continuation) = AsyncThrowingStream<Ocp1MessageList, Error>.makeStream()
    _messages = stream

    let handle = receiveHandle
    DispatchQueue(
      label: "com.padl.SwiftOCADevice.machReceive"
    ).async {
      do {
        while true {
          let envelope = try handle.receive()
          switch envelope.kind {
          case .data:
            let messageList = try Ocp1MessageList(messagePduData: envelope.payload)
            continuation.yield(messageList)
          case .disconnect:
            continuation.finish(throwing: Ocp1Error.notConnected)
            return
          case .connect, .connectReply:
            envelope.dispose()
          }
        }
      } catch {
        continuation.finish(throwing: error)
      }
    }
  }

  var messages: AnyAsyncSequence<Ocp1MessageList> {
    _messages.eraseToAnyAsyncSequence()
  }

  func sendOcp1EncodedData(_ data: Data) async throws {
    try receiveHandle.sendData(data, to: clientSendPort)
  }

  func close() throws {
    try? receiveHandle.sendDisconnect(to: clientSendPort)
    Ocp1MachPortHandle.deallocateSendRight(clientSendPort)
    receiveHandle.destroy()
  }
}

extension Ocp1MachPortController: Equatable {
  nonisolated static func == (
    lhs: Ocp1MachPortController,
    rhs: Ocp1MachPortController
  ) -> Bool {
    lhs.receiveHandle.port == rhs.receiveHandle.port
  }
}

extension Ocp1MachPortController: Hashable {
  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(receiveHandle.port)
  }
}

#endif
