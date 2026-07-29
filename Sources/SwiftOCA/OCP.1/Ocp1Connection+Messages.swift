//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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
    _ message: some _Ocp1MessageCodable,
    type messageType: OcaMessageType
  ) async throws {
    try await batcher.enqueue(message, type: messageType)
  }

  /// `command.handle` is assigned here, replacing whatever the caller set:
  /// only the connection knows which handles it has issued.
  public func sendCommand(_ command: consuming Ocp1Command) async throws {
    guard let monitor else {
      throw Ocp1Error.notConnected
    }

    monitor.allocateCommandHandle(&command, responseRequired: false)
    try await sendMessage(command, type: .ocaCmd)
  }

  /// `command.handle` is assigned here, replacing whatever the caller set:
  /// only the connection knows which handles are in flight.
  public func sendCommandRrq(_ command: consuming Ocp1Command) async throws -> Ocp1Response {
    guard let monitor else {
      throw Ocp1Error.notConnected
    }

    let handle = monitor.allocateCommandHandle(&command, responseRequired: true)
    defer { monitor.releaseCommandHandle(handle) }

    let request = consume command

    return try await withThrowingTimeout(
      of: responseTimeout,
      clock: .continuous,
      operation: { [self] in
        try await sendMessage(request, type: .ocaCmdRrq)
        return try await monitor.response(for: handle)
      }, onTimeout: {
        monitor.resumeTimedOut(handle: handle)
      }
    )
  }

  func sendKeepAlive() async throws {
    try await sendMessage(
      Ocp1KeepAlive.message(interval: heartbeatTime),
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
