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

extension AES70OCP1Connection.Monitor {
    private func receiveMessagePdu(_ connection: AES70OCP1Connection,
                                   messages: inout [Data]) async throws -> OcaMessageType {
        var messagePduData = try await connection.read(Self.MinimumPduSize)
        
        /// just parse enough of the protocol in order to read rest of message
        /// `syncVal: OcaUint8` || `protocolVersion: OcaUint16` || `pduSize: OcaUint32`
        guard messagePduData.count >= Self.MinimumPduSize else {
            debugPrint("receiveMessagePdu: PDU of size \(messagePduData.count) is too short")
            throw Ocp1Error.pduTooShort
        }
        guard messagePduData[0] == Ocp1SyncValue else {
            debugPrint("receiveMessagePdu: PDU has invalid sync value \(messagePduData.prefix(1).hexEncodedString())")
            throw Ocp1Error.invalidSyncValue
        }
        let pduSize: OcaUint32 = messagePduData.decodeInteger(index: 3)
        guard pduSize >= (Self.MinimumPduSize - 1) else { // doesn't include sync byte
            debugPrint("receiveMessagePdu: PDU size \(pduSize) is less than minimum PDU size")
            throw Ocp1Error.invalidPduSize
        }

        messagePduData += try await connection.read(Int(pduSize) - (Self.MinimumPduSize - 1))
        return try decodeOcp1MessagePdu(from: messagePduData, messages: &messages)
    }

    private func processMessage(_ connection: AES70OCP1Connection, _ message: Ocp1Message) async throws {
        switch message {
        case is Ocp1Command:
            debugPrint("processMessage: Device sent unexpected command \(message); ignoring")
        case let notification as Ocp1Notification:
            let event = notification.parameters.eventData.event
            // debugPrint("processMessage: Received notification for event \(event)")
            Task {
                if let callback = await connection.subscriptions[event], notification.parameters.parameterCount == 2 {
                    await callback(notification.parameters.eventData)
                }
            }
        case let response as Ocp1Response:
            //debugPrint("processMessage: \(Date()): response for request \(response.handle)")
            guard let continuation = self.pop(response.handle) else {
                throw Ocp1Error.invalidHandle
            }

            Task {
                continuation.resume(with: Result<Ocp1Response, Ocp1Error>.success(response))
            }
        case is Ocp1KeepAlive1:
            break
        case is Ocp1KeepAlive2:
            break
        default:
            fatalError("processMessage: Unknown PDU type")
        }
    }
    
    private func receiveMessage(_ connection: AES70OCP1Connection) async throws {
        var messagePdus = [Data]()
        let messageType = try await receiveMessagePdu(connection, messages: &messagePdus)
        let messages = try messagePdus.map {
            try decodeOcp1Message(from: $0, type: messageType)
        }
               
        updateLastMessageReceivedTime()

        for message in messages {
            let keepAliveInterval = await connection.keepAliveInterval
            if keepAliveInterval != 0, await connectionIsStale {
                throw Ocp1Error.notConnected
            }

            try await processMessage(connection, message)
        }        
    }
    
    func receiveMessages(_ connection: AES70OCP1Connection) async throws {
        repeat {
            try await receiveMessage(connection)
        } while !isCancelled
    }
}
