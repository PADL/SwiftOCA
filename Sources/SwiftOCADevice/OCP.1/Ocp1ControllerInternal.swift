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

import AsyncExtensions
import Foundation
import Logging
import SwiftOCA

/// OcaControllerPrivate should eventually be merged into OcaController once we are ready to
/// support out-of-tree endpoints

protocol Ocp1ControllerInternal: OcaControllerDefaultSubscribing, AnyActor {
  associatedtype Endpoint: OcaDeviceEndpointPrivate

  nonisolated var connectionPrefix: String { get }

  typealias ControllerMessage = (Ocp1Message, Bool)

  /// get an identifier used for logging
  nonisolated var identifier: String { get }

  var endpoint: Endpoint? { get }

  /// a sequence of (message, isRrq) where isRrq indicates if a response is required
  var messages: AnyAsyncSequence<ControllerMessage> { get }

  /// last message sent time
  var lastMessageSentTime: ContinuousClock.Instant { get set }

  /// last message received time
  var lastMessageReceivedTime: ContinuousClock.Instant { get set }

  /// keep alive interval
  var heartbeatTime: Duration { get set }

  /// keep alive task
  var keepAliveTask: Task<(), Error>? { get set }

  func sendOcp1EncodedData(_ data: Data) async throws

  /// cleanup
  func onConnectionBecomingStale() async throws

  /// close the underlying connection (if any)
  func close() async throws
}

/// When using UDP, the Controller sends a Keep-alive message to the Device before sending other
/// messages. A Device using UDP ignores all messages received from a Controller prior to receipt of
/// a Keep-alive message from that Controller.
protocol Ocp1ControllerDatagramSemantics: Actor {
  var isOpen: Bool { get }
  func didOpen()
}

extension Ocp1ControllerInternal {
  /// handle a single message
  func handle<Endpoint: OcaDeviceEndpointPrivate>(
    for endpoint: Endpoint,
    message: Ocp1Message,
    rrq: Bool
  ) async throws {
    let controller = self as! Endpoint.ControllerType
    var response: Ocp1Response?

    lastMessageReceivedTime = .now

    if let datagramController = self as? Ocp1ControllerDatagramSemantics {
      if message is Ocp1KeepAlive1 || message is Ocp1KeepAlive2 {
        await datagramController.didOpen()
      } else if await datagramController.isOpen == false {
        endpoint.logger.info("received non-keepalive message \(message) before open")
        throw Ocp1Error.invalidMessageType
      }
    }

    switch message {
    case let command as Ocp1Command:
      endpoint.logger.command(command, on: controller)
      let commandResponse = await endpoint.device.handleCommand(
        command,
        timeout: endpoint.timeout,
        from: controller
      )
      response = Ocp1Response(
        handle: command.handle,
        statusCode: commandResponse.statusCode,
        parameters: commandResponse.parameters
      )
    case let keepAlive as Ocp1KeepAlive1:
      heartbeatTime = .seconds(keepAlive.heartBeatTime)
    case let keepAlive as Ocp1KeepAlive2:
      heartbeatTime = .milliseconds(keepAlive.heartBeatTime)
    default:
      endpoint.logger.info("received unknown message \(message)")
      throw Ocp1Error.invalidMessageType
    }

    if rrq, let response {
      try await sendMessage(response, type: .ocaRsp)
    }
    if let response {
      endpoint.logger.response(response, on: controller)
    }
  }

  /// handle messages until an error
  func handle<Endpoint: OcaDeviceEndpointPrivate>(for endpoint: Endpoint) async {
    let controller = self as! Endpoint.ControllerType

    endpoint.logger.info("controller added", controller: controller)
    await endpoint.add(controller: controller)
    do {
      for try await (message, rrq) in messages {
        try await handle(
          for: endpoint,
          message: message,
          rrq: rrq
        )
      }
    } catch Ocp1Error.notConnected {
    } catch {
      endpoint.logger.error(error, controller: controller)
    }
    await endpoint.unlockAndRemove(controller: controller)
    try? await close()
    endpoint.logger.info("controller removed", controller: controller)
  }

  /// returns `true` if insufficient keepalives were received to keep connection fresh
  private func connectionIsStale(_ now: ContinuousClock.Instant) -> Bool {
    lastMessageReceivedTime + (heartbeatTime * 3) < now
  }

  private func sendKeepAlive() async throws {
    try await sendMessage(
      Ocp1KeepAlive.keepAlive(interval: heartbeatTime),
      type: .ocaKeepAlive
    )
  }

  /// Oca-3 notes that both controller and device send `KeepAlive` messages if they haven't
  /// yet received (or sent) another message during `HeartbeatTime`.
  func heartbeatTimeDidChange(from oldValue: Duration) {
    if (heartbeatTime != .zero && heartbeatTime != oldValue) || keepAliveTask == nil {
      // if we have a keepalive interval and it has changed, or we haven't yet started
      // the keepalive task, (re)start it
      keepAliveTask = Task<(), Error> {
        repeat {
          let now = ContinuousClock.now
          if connectionIsStale(now) {
            try? await onConnectionBecomingStale()
            await endpoint?.remove(controller: self as! Endpoint.ControllerType)
            endpoint?.logger.info("expired controller", controller: self)
            break
          }
          let timeSinceLastMessageSent = now - lastMessageSentTime
          var sleepTime = heartbeatTime
          if timeSinceLastMessageSent >= heartbeatTime {
            try await sendKeepAlive()
          } else {
            sleepTime -= timeSinceLastMessageSent
          }
          try await Task.sleep(for: sleepTime)
        } while !Task.isCancelled
      }
    } else if heartbeatTime == .zero, let keepAliveTask {
      // otherwise if the new interval is zero, cancel the task (if any)
      keepAliveTask.cancel()
      self.keepAliveTask = nil
    }
  }

  func decodeMessages(from messagePduData: [UInt8]) throws -> [ControllerMessage] {
    guard messagePduData.count >= Ocp1Connection.MinimumPduSize,
          messagePduData[0] == Ocp1SyncValue
    else {
      throw Ocp1Error.invalidSyncValue
    }
    let pduSize: OcaUint32 = Data(messagePduData).decodeInteger(index: 3)
    guard pduSize >= (Ocp1Connection.MinimumPduSize - 1) else {
      throw Ocp1Error.invalidPduSize
    }

    var messagePdus = [Data]()
    let messageType = try Ocp1Connection.decodeOcp1MessagePdu(
      from: Data(messagePduData),
      messages: &messagePdus
    )
    let messages = try messagePdus.map {
      try Ocp1Connection.decodeOcp1Message(from: $0, type: messageType)
    }

    return messages.map { ($0, messageType == .ocaCmdRrq) }
  }

  func sendMessage(
    _ message: Ocp1Message,
    type messageType: OcaMessageType
  ) async throws {
    try await sendMessages([message], type: messageType)
  }

  func sendMessages(
    _ messages: [Ocp1Message],
    type messageType: OcaMessageType
  ) async throws {
    lastMessageSentTime = .now

    try await sendOcp1EncodedData(Ocp1Connection.encodeOcp1MessagePdu(
      messages,
      type: messageType
    ))
  }
}

extension OcaDevice {
  typealias GetChunk = @Sendable (Int) async throws -> [UInt8]

  #if canImport(FlyingSocks)
  static func unsafeReceiveMessages(_ getChunk: (Int) async throws -> [UInt8]) async throws
    -> [Ocp1ControllerInternal.ControllerMessage]
  {
    try await receiveMessages(getChunk)
  }
  #endif

  static func receiveMessages(_ getChunk: GetChunk) async throws
    -> [Ocp1ControllerInternal.ControllerMessage]
  {
    var messagePduData = try await getChunk(Ocp1Connection.MinimumPduSize)

    guard messagePduData.count != 0 else {
      // 0 length on EOF
      throw Ocp1Error.notConnected
    }

    guard messagePduData.count >= Ocp1Connection.MinimumPduSize,
          messagePduData[0] == Ocp1SyncValue
    else {
      throw Ocp1Error.invalidSyncValue
    }

    let pduSize: OcaUint32 = Data(messagePduData).decodeInteger(index: 3)
    guard pduSize >= (Ocp1Connection.MinimumPduSize - 1) else {
      throw Ocp1Error.invalidPduSize
    }

    let bytesLeft = Int(pduSize) - (Ocp1Connection.MinimumPduSize - 1)
    messagePduData += try await getChunk(bytesLeft)

    var messagePdus = [Data]()
    let messageType = try Ocp1Connection.decodeOcp1MessagePdu(
      from: Data(messagePduData),
      messages: &messagePdus
    )
    let messages = try messagePdus.map {
      try Ocp1Connection.decodeOcp1Message(from: $0, type: messageType)
    }

    return messages.map { ($0, messageType == .ocaCmdRrq) }
  }
}

extension Duration {
  var timeInterval: TimeInterval {
    TimeInterval(components.seconds) + TimeInterval(components.attoseconds) * 1e-18
  }
}

protocol Ocp1ControllerInternalLightweightNotifyingInternal: OcaControllerLightweightNotifying {
  func sendOcp1EncodedData(
    _ data: Data,
    to destinationAddress: OcaNetworkAddress
  ) async throws
}

extension Ocp1ControllerInternalLightweightNotifyingInternal {
  func sendMessage(
    _ message: Ocp1Message,
    type messageType: OcaMessageType,
    to destinationAddress: OcaNetworkAddress
  ) async throws {
    try await sendOcp1EncodedData(Ocp1Connection.encodeOcp1MessagePdu(
      [message],
      type: messageType
    ), to: destinationAddress)
  }
}

// https://www.swiftbysundell.com/articles/async-and-concurrent-forEach-and-map/
extension Sequence {
  func asyncForEach(
    _ operation: @Sendable (Element) async throws -> ()
  ) async rethrows {
    for element in self {
      try await operation(element)
    }
  }
}
