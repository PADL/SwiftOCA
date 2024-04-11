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

/// Connection monitor delivers responses keyed by request handle

extension Ocp1Connection.Monitor {
    private func receiveMessagePdu(
        _ connection: Ocp1Connection,
        messages: inout [Data]
    ) async throws -> OcaMessageType {
        var messagePduData = try await connection.read(Ocp1Connection.MinimumPduSize)

        guard messagePduData.count > 0 else {
            throw Ocp1Error.notConnected
        }

        /// just parse enough of the protocol in order to read rest of message
        /// `syncVal: OcaUint8` || `protocolVersion: OcaUint16` || `pduSize: OcaUint32`
        guard messagePduData.count >= Ocp1Connection.MinimumPduSize else {
            await connection.logger.warning("PDU of size \(messagePduData.count) is too short")
            throw Ocp1Error.pduTooShort
        }
        guard messagePduData[0] == Ocp1SyncValue else {
            await connection.logger.warning(
                "PDU has invalid sync value \(messagePduData.prefix(1).hexEncodedString())"
            )
            throw Ocp1Error.invalidSyncValue
        }

        let pduSize: OcaUint32 = messagePduData.decodeInteger(index: 3)
        guard pduSize >= (Ocp1Connection.MinimumPduSize - 1)
        else { // doesn't include sync byte
            await connection.logger.warning("PDU size \(pduSize) is less than minimum PDU size")
            throw Ocp1Error.invalidPduSize
        }

        let bytesLeft = Int(pduSize) + 1 - messagePduData.count
        if bytesLeft > 0 {
            messagePduData += try await connection.read(bytesLeft)
        }

        return try Ocp1Connection.decodeOcp1MessagePdu(
            from: messagePduData,
            messages: &messages
        )
    }

    private func processMessage(
        _ connection: Ocp1Connection,
        _ message: Ocp1Message
    ) async throws {
        switch message {
        case is Ocp1Command:
            await connection.logger.warning("device sent unexpected command \(message); ignoring")
        case let notification as Ocp1Notification1:
            if notification.parameters.parameterCount == 2 {
                await connection.notifySubscribers(
                    of: notification.parameters.eventData.event,
                    with: notification.parameters.eventData.eventParameters
                )
            }
        case let response as Ocp1Response:
            try resume(with: response)
        case is Ocp1KeepAlive1:
            fallthrough
        case is Ocp1KeepAlive2:
            break
        case let notification as Ocp1Notification2:
            try notification.throwIfException()
            await connection.notifySubscribers(of: notification.event, with: notification.data)
        default:
            throw Ocp1Error.unknownPduType
        }
    }

    private func receiveMessage(_ connection: Ocp1Connection) async throws {
        var messagePdus = [Data]()
        let messageType = try await receiveMessagePdu(connection, messages: &messagePdus)
        let messages = try messagePdus.map {
            try Ocp1Connection.decodeOcp1Message(from: $0, type: messageType)
        }

        updateLastMessageReceivedTime()

        for message in messages {
            try await processMessage(connection, message)
        }
    }

    private func keepAlive(_ connection: Ocp1Connection) async throws {
        let heartbeatTime = await connection.heartbeatTime
        let keepAliveThreshold = heartbeatTime * 3

        repeat {
            let now = ContinuousClock.now
            if now - lastMessageReceivedTime >= keepAliveThreshold {
                await connection.logger
                    .info(
                        "\(connection): no heartbeat packet received in past \(keepAliveThreshold)"
                    )
                throw Ocp1Error.responseTimeout
            }

            let timeSinceLastMessageSent = await now - connection.lastMessageSentTime
            var sleepTime = heartbeatTime
            if timeSinceLastMessageSent >= heartbeatTime {
                try await connection.sendKeepAlive()
            } else {
                sleepTime -= timeSinceLastMessageSent
            }
            try await Task.sleep(for: sleepTime)
        } while true
    }

    func receiveMessages(_ connection: Ocp1Connection) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            let heartbeatTime = await connection.heartbeatTime

            group.addTask { [self] in
                repeat {
                    try Task.checkCancellation()
                    try await receiveMessage(connection)
                } while true
            }
            if heartbeatTime > .zero {
                group.addTask(priority: .background) {
                    try await self.keepAlive(connection)
                }
            }
            try await group.next()
            group.cancelAll()
        }
    }
}
