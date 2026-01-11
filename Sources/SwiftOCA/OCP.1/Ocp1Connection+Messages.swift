//
// Copyright (c) 2023 PADL Software Pty Ltd
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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Ocp1Connection {
  private func sendMessage(
    _ message: Ocp1Message,
    type messageType: OcaMessageType
  ) async throws {
    try await batcher.enqueue(message, type: messageType)
  }

  public func sendCommand(_ command: Ocp1Command) async throws {
    try await sendMessage(command, type: .ocaCmd)
  }

  private func response(for handle: OcaUint32) async throws -> Ocp1Response {
    guard let monitor else {
      throw Ocp1Error.notConnected
    }

    return try await withUnsafeThrowingContinuation { continuation in
      monitor.register(handle: handle, continuation: continuation)
    }
  }

  private func _sendCommandRrqExtendedStatus(_ command: Ocp1Command) async throws -> Ocp1Response {
    let extendedStatusCommand = Ocp1Command(
      commandSize: command.commandSize,
      handle: command.handle,
      targetONo: command.targetONo,
      methodID: command.methodID,
      extensions: [.init(extensionID: OcaExtendedStatusExtensionID, extensionData: .init())]
    )
    try await sendMessage(extendedStatusCommand, type: .ocaCmdRrqExtended)
    return try await response(for: command.handle)
  }

  private func _sendCommandRrq(_ command: Ocp1Command) async throws -> Ocp1Response {
    try await sendMessage(command, type: .ocaCmdRrq)
    return try await response(for: command.handle)
  }

  public func sendCommandRrq(_ command: Ocp1Command) async throws -> Ocp1Response {
    try await withThrowingTimeout(
      of: responseTimeout,
      clock: .continuous,
      operation: { [self] in
        if await options.flags.contains(.extendedStatusSupported) {
          do {
            return try await _sendCommandRrqExtendedStatus(command)
          } catch Ocp1Error.status {
            try await _disableExtendedStatus()
            return try await _sendCommandRrq(command)
          }
        } else {
          return try await _sendCommandRrq(command)
        }
      }, onTimeout: { [self] in
        try await monitor?.resumeTimedOut(handle: command.handle)
      }
    )
  }

  func sendKeepAlive() async throws {
    try await sendMessage(
      Ocp1KeepAlive.keepAlive(interval: heartbeatTime),
      type: .ocaKeepAlive
    )
  }

  @Sendable
  func sendMessagePduData(
    _ messagePduData: Data
  ) async throws {
    guard try await write(messagePduData) == messagePduData.count else {
      throw Ocp1Error.pduSendingFailed
    }

    lastMessageSentTime = .now
  }
}
