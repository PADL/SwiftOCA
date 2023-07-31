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

private extension Ocp1Message {
    func encode(type messageType: OcaMessageType) throws -> Data {
        let encoder = Ocp1BinaryEncoder()
        var messageData = try encoder.encode(self)

        if messageType != .ocaKeepAlive {
            /// replace `commandSize: OcaUint32` with actual command size
            precondition(messageData.count < OcaUint32.max)
            messageData.encodeInteger(OcaUint32(messageData.count), index: 0)
        }

        return messageData
    }
}

public extension AES70OCP1Connection {
    static func encodeOcp1MessagePdu(
        _ messages: [Ocp1Message],
        type messageType: OcaMessageType
    ) throws -> Data {
        var messagePduData = Data([Ocp1SyncValue])

        let header = Ocp1Header(pduType: messageType, messageCount: OcaUint16(messages.count))
        let encoder = Ocp1BinaryEncoder()
        messagePduData += try encoder.encode(header)

        try messages.forEach {
            messagePduData += try $0.encode(type: messageType)
        }
        /// MinimumPduSize == 7
        /// 0 `syncVal: OcaUint8`
        /// 1`protocolVersion: OcaUint16`
        /// 3 `pduSize: OcaUint32` (size of PDU not including syncVal)
        precondition(messagePduData.count < OcaUint32.max)
        messagePduData.encodeInteger(OcaUint32(messagePduData.count - 1), index: 3)
        return messagePduData
    }

    static func decodeOcp1MessagePdu(
        from data: Data,
        messages: inout [Data]
    ) throws -> OcaMessageType {
        precondition(data.count >= Self.MinimumPduSize)
        precondition(data[0] == Ocp1SyncValue)

        /// MinimumPduSize == 7
        /// 0 `syncVal: OcaUint8`
        /// 1`protocolVersion: OcaUint16`
        /// 3 `pduSize: OcaUint32` (size of PDU not including syncVal)

        guard data.count >= Self.MinimumPduSize + 3 else {
            throw Ocp1Error.invalidPduSize
        }

        var header = Ocp1Header()
        header.protocolVersion = data.decodeInteger(index: 1)
        guard header.protocolVersion == Ocp1ProtocolVersion else {
            throw Ocp1Error.invalidProtocolVersion
        }

        header.pduSize = data.decodeInteger(index: 3)
        precondition(header.pduSize <= data.count - 1)

        /// MinimumPduSize +3 == 10
        /// 7 `messageType: OcaUint8`
        /// 8 `messageCount: OcaUint16`
        guard let messageType = OcaMessageType(rawValue: data[7]) else {
            throw Ocp1Error.invalidMessageType
        }

        let messageCount: OcaUint16 = data.decodeInteger(index: 8)

        var cursor = Self.MinimumPduSize + 3 // start of first message

        for _ in 0..<messageCount {
            precondition(cursor < data.count)
            var messageData = data
                .subdata(in: cursor..<Int(header.pduSize) + 1) // because this includes sync byte

            if messageType != .ocaKeepAlive {
                let messageSize: OcaUint32 = messageData.decodeInteger(index: 0)

                guard messageSize <= messageData.count else {
                    throw Ocp1Error.invalidMessageSize
                }

                messageData = messageData.prefix(Int(messageSize))
                cursor += Int(messageSize)
            }

            messages.append(messageData)

            if messageType == .ocaKeepAlive {
                break
            }
        }

        return messageType
    }

    nonisolated static func decodeOcp1Message(
        from messageData: Data,
        type messageType: OcaMessageType
    ) throws -> Ocp1Message {
        let decoder = Ocp1BinaryDecoder()
        let message: Ocp1Message

        switch messageType {
        case .ocaCmd:
            message = try decoder.decode(Ocp1Command.self, from: messageData)
        case .ocaCmdRrq:
            message = try decoder.decode(Ocp1Command.self, from: messageData)
        case .ocaNtf1:
            message = try decoder.decode(Ocp1Notification1.self, from: messageData)
        case .ocaRsp:
            message = try decoder.decode(Ocp1Response.self, from: messageData)
        case .ocaKeepAlive:
            if messageData.count == 2 {
                message = try decoder.decode(Ocp1KeepAlive1.self, from: messageData)
            } else if messageData.count == 4 {
                message = try decoder.decode(Ocp1KeepAlive2.self, from: messageData)
            } else {
                throw Ocp1Error.invalidKeepAlivePdu
            }
        case .ocaNtf2:
            message = try decoder.decode(Ocp1Notification2.self, from: messageData)
        }

        return message
    }
}
