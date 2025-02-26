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

private func _writeMessageSize(_ size: Int, to bytes: inout [UInt8], at index: Int) {
  precondition(size <= OcaUint32.max)
  precondition(bytes.count >= index + 4)
  withUnsafeBytes(of: OcaUint32(size).bigEndian) {
    bytes[index..<(index + 4)] = Array($0)[0..<4]
  }
}

private extension Ocp1Message {
  func encode(type messageType: OcaMessageType, into messageData: inout [UInt8]) throws {
    let offset = messageData.count

    (self as! _Ocp1MessageCodable).encode(into: &messageData)

    if messageType != .ocaKeepAlive {
      /// replace `commandSize: OcaUint32` with actual command size
      _writeMessageSize(messageData.count - offset, to: &messageData, at: offset)
    }
  }
}

package extension Ocp1Connection {
  private nonisolated static func encodeOcp1MessagePdu(
    _ messages: [Ocp1Message],
    type messageType: OcaMessageType
  ) throws -> [UInt8] {
    var messagePduData = [UInt8]()
    messagePduData.reserveCapacity(48) // enough for a metering PDU
    messagePduData += [Ocp1SyncValue]
    Ocp1Header(pduType: messageType, messageCount: OcaUint16(messages.count))
      .encode(into: &messagePduData)

    try messages.forEach {
      try ($0 as! _Ocp1MessageCodable).encode(type: messageType, into: &messagePduData)
    }
    /// MinimumPduSize == 7
    /// 0 `syncVal: OcaUint8`
    /// 1 `protocolVersion: OcaUint16`
    /// 3 `pduSize: OcaUint32` (size of PDU not including syncVal)
    _writeMessageSize(messagePduData.count - 1, to: &messagePduData, at: 3)

    return messagePduData
  }

  nonisolated static func encodeOcp1MessagePdu(
    _ messages: [Ocp1Message],
    type messageType: OcaMessageType
  ) throws -> Data {
    let bytes: [UInt8] = try encodeOcp1MessagePdu(messages, type: messageType)
    return Data(bytes)
  }

  nonisolated static func decodeOcp1MessagePdu(
    from data: Data,
    messages: inout [Data]
  ) throws -> OcaMessageType {
    guard data.count >= 1 + Ocp1Header.HeaderSize else {
      throw Ocp1Error.invalidPduSize
    }

    guard data[0] == Ocp1SyncValue else {
      throw Ocp1Error.invalidSyncValue
    }

    let header = try Ocp1Header(bytes: Array(data[1...]))
    let messageCount: OcaUint16 = data.decodeInteger(index: 8)

    var cursor = 1 + Ocp1Header.HeaderSize // start of first message

    for _ in 0..<messageCount {
      precondition(cursor < data.count)
      var messageData = data
        .subdata(in: cursor..<Int(header.pduSize) + 1) // because this includes sync byte

      if header.pduType != .ocaKeepAlive {
        if messageData.count < 4 {
          throw Ocp1Error.pduTooShort
        }
        let messageSize: OcaUint32 = messageData
          .decodeInteger(index: 0) /// _expects_ length >= 4

        guard messageSize <= messageData.count else {
          throw Ocp1Error.invalidMessageSize
        }

        messageData = messageData.prefix(Int(messageSize))
        cursor += Int(messageSize)
      }

      messages.append(messageData)

      if header.pduType == .ocaKeepAlive {
        break
      }
    }

    return header.pduType
  }

  nonisolated static func decodeOcp1Message(
    from messageData: Data,
    type messageType: OcaMessageType
  ) throws -> Ocp1Message {
    let message: Ocp1Message

    switch messageType {
    case .ocaCmd:
      message = try Ocp1Command(bytes: Array(messageData))
    case .ocaCmdRrq:
      message = try Ocp1Command(bytes: Array(messageData))
    case .ocaNtf1:
      message = try Ocp1Notification1(bytes: Array(messageData))
    case .ocaRsp:
      message = try Ocp1Response(bytes: Array(messageData))
    case .ocaKeepAlive:
      if messageData.count == 2 {
        message = try Ocp1KeepAlive1(bytes: Array(messageData))
      } else if messageData.count == 4 {
        message = try Ocp1KeepAlive2(bytes: Array(messageData))
      } else {
        throw Ocp1Error.invalidKeepAlivePdu
      }
    case .ocaNtf2:
      message = try Ocp1Notification2(bytes: Array(messageData))
    }

    return message
  }
}
