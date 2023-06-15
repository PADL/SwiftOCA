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
import BinaryCoder
import Socket

extension AES70OCP1Connection {
    func sendMessages() async throws {
        guard let requestMonitor = await requestMonitor else { throw Ocp1Error.notConnected }
        
        for await (messageType, messages) in requestMonitor.channel {
            let messagePduData = try encodeOcp1MessagePdu(messages, type: messageType)
            
            guard try await write(messagePduData) == messagePduData.count else {
                throw Ocp1Error.pduSendingFailed
            }
            requestMonitor.updateLastMessageTime()
        }
    }

    private func receiveMessagePdu(messages: inout [Data]) async throws -> OcaMessageType {
        var messagePduData = try await read(Self.MinimumPduSize)
        
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

        messagePduData += try await read(Int(pduSize) - (Self.MinimumPduSize - 1))
        return try decodeOcp1MessagePdu(from: messagePduData, messages: &messages)
    }

    private func processMessage(_ message: Ocp1Message, monitor: Monitor<Response>) async throws {
        switch message {
        case is Ocp1Command:
            debugPrint("processMessage: Device sent unexpected command \(message); ignoring")
        case let notification as Ocp1Notification:
            let event = notification.parameters.eventData.event
            debugPrint("processMessage: Received notification for event \(event)")
            Task { @MainActor in
                if let subscriber = subscribers[event], notification.parameters.parameterCount == 2 {
                    for callback in subscriber {
                        (callback as! AES70SubscriptionCallback)(notification.parameters.eventData)
                    }
                }
            }
        case let response as Ocp1Response:
            debugPrint("processMessage: response for request \(response.handle)")
            await monitor.channel.send(response)
        case is Ocp1KeepAlive1:
            break
        case is Ocp1KeepAlive2:
            break
        default:
            fatalError("processMessage: Unknown PDU type")
        }
    }
    
    private func receiveMessage() async throws {
        guard let responseMonitor = await responseMonitor else { throw Ocp1Error.notConnected }
        
        var messagePdus = [Data]()
        let messageType = try await receiveMessagePdu(messages: &messagePdus)
        let messages = try messagePdus.map {
            try decodeOcp1Message(from: $0, type: messageType)
        }
               
        responseMonitor.updateLastMessageTime()

        for message in messages {
            if keepAliveInterval != 0,
               responseMonitor.lastMessageTime + TimeInterval(3 * self.keepAliveInterval) < Date() {
                throw Ocp1Error.notConnected
            }

            try await processMessage(message, monitor: responseMonitor)
            responseMonitor.updateLastMessageTime()
        }
        
        await Task.yield()
    }
    
    func receiveMessages() async throws {
        repeat {
            try await receiveMessage()
            // rely on exceptions to get us out of the loop
        } while true
    }
}
