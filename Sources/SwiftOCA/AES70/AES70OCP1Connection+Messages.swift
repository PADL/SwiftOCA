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

import Foundation

extension AES70OCP1Connection {
    func updateLastMessageSentTime() async {
        lastMessageSentTime = Date()
    }

    private func sendMessages(
        _ messages: [Ocp1Message],
        type messageType: OcaMessageType
    ) async throws {
        let messagePduData = try Self.encodeOcp1MessagePdu(messages, type: messageType)

        do {
            guard try await write(messagePduData) == messagePduData.count else {
                throw Ocp1Error.pduSendingFailed
            }
            await updateLastMessageSentTime()
        } catch Ocp1Error.notConnected {
            if options.automaticReconnect {
                try await reconnectDevice()
            } else {
                throw Ocp1Error.notConnected
            }
        }
    }

    private func sendMessage(
        _ message: Ocp1Message,
        type messageType: OcaMessageType
    ) async throws {
        try await sendMessages([message], type: messageType)
    }

    func sendCommand(_ command: Ocp1Command) async throws {
        try await sendMessage(command, type: .ocaCmd)
    }

    private func response(for handle: OcaUint32) async throws -> Ocp1Response {
        guard let monitor = monitor else {
            throw Ocp1Error.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await monitor.register(handle: handle, continuation: continuation)
            }
        }
    }

    func sendCommandRrq(_ command: Ocp1Command) async throws -> Ocp1Response {
        try await sendMessage(command, type: .ocaCmdRrq)
        return try await response(for: command.handle)
    }

    func sendKeepAlive() async throws {
        let message = Ocp1KeepAlive1(heartBeatTime: keepAliveInterval)
        try await sendMessage(message, type: .ocaKeepAlive)
    }
}
