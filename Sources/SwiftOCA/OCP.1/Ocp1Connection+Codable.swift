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

import BinaryParsing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

private func _writeMessageSize(_ size: Int, to bytes: inout [UInt8], at index: Int) {
  precondition(bytes.count >= index + 4)
  let size = OcaUint32(size)
  bytes[index + 0] = UInt8((size >> 24) & 0xFF)
  bytes[index + 1] = UInt8((size >> 16) & 0xFF)
  bytes[index + 2] = UInt8((size >> 8) & 0xFF)
  bytes[index + 3] = UInt8(size & 0xFF)
}

extension _Ocp1MessageCodable {
  func encode(type messageType: OcaMessageType, into messageData: inout [UInt8]) throws {
    let offset = messageData.count

    encode(into: &messageData)

    if messageType != .ocaKeepAlive {
      /// replace `commandSize: OcaUint32` with actual command size
      _writeMessageSize(messageData.count - offset, to: &messageData, at: offset)
    }
  }
}

package extension Ocp1Connection {
  nonisolated static func encodeOcp1MessagePduData(
    type messageType: OcaMessageType,
    encodedPdus: [[UInt8]]
  ) throws -> [UInt8] {
    var messagePduData = [UInt8]()
    let estimatedSize = Self.MinimumPduSize + encodedPdus.reduce(0) { $0 + $1.count }
    messagePduData.reserveCapacity(estimatedSize)
    messagePduData.append(Ocp1SyncValue)
    Ocp1Header(pduType: messageType, messageCount: OcaUint16(encodedPdus.count))
      .encode(into: &messagePduData)

    encodedPdus.forEach { messagePduData.append(contentsOf: $0) }
    /// MinimumPduSize == 7
    /// 0 `syncVal: OcaUint8`
    /// 1 `protocolVersion: OcaUint16`
    /// 3 `pduSize: OcaUint32` (size of PDU not including syncVal)
    _writeMessageSize(messagePduData.count - 1, to: &messagePduData, at: 3)

    return messagePduData
  }

  private nonisolated static func encodeOcp1MessagePdu(
    _ messages: [Ocp1Message],
    type messageType: OcaMessageType
  ) throws -> [UInt8] {
    var messagePduData = [UInt8]()
    let estimatedSize = 16 + (messages.count * 32) // header + estimated per-message
    messagePduData.reserveCapacity(estimatedSize)
    messagePduData.append(Ocp1SyncValue)
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

  /// Decodes a complete OCP.1 PDU into its constituent messages.
  ///
  /// The whole PDU is parsed in a single pass over one `ParserSpan`. Each
  /// message is decoded from a sub-span bounded by its own declared size, so a
  /// message can neither read past the PDU nor into its neighbour, and a PDU
  /// that declares more bytes (or more messages) than it delivers throws rather
  /// than trapping — both matter because `data` here is unvalidated input
  /// straight off the wire.
  nonisolated static func decodeOcp1MessagePdu(
    from data: Data
  ) throws -> (OcaMessageType, [Ocp1Message]) {
    try Ocp1Error.mapping {
      try data.withParserSpan { try _decodeOcp1MessagePdu(&$0) }
    }
  }

  private nonisolated static func _decodeOcp1MessagePdu(
    _ input: inout ParserSpan
  ) throws -> (OcaMessageType, [Ocp1Message]) {
    guard try OcaUint8(parsing: &input) == Ocp1SyncValue else {
      throw Ocp1Error.invalidSyncValue
    }

    let header = try Ocp1Header(parsing: &input)

    /// `pduSize` counts every byte after `syncVal`, so the messages occupy the
    /// `pduSize - HeaderSize` bytes following the header. Slicing here is what
    /// bounds the rest of the parse: if the sender declared more than it sent,
    /// this throws `pduTooShort` instead of running off the end of the buffer.
    var body = try input.sliceSpan(
      byteCount: Int(throwingOnOverflow: header.pduSize) - Ocp1Header.HeaderSize
    )

    if header.pduType == .ocaKeepAlive {
      /// Keep-alive messages carry no per-message size field; the message is
      /// the remainder of the PDU, and `messageCount` is not meaningful.
      return (header.pduType, [try decodeOcp1KeepAlive(parsing: &body)])
    }

    var messages = [Ocp1Message]()
    messages.reserveCapacity(Int(header.messageCount))

    for _ in 0..<header.messageCount {
      /// The size field is part of the message it describes, so read it from a
      /// lookahead span and leave `body` positioned at the start of the message.
      var lookahead = try body.seeking(toRelativeOffset: 0)
      let messageSize = try Int(throwingOnOverflow: OcaUint32(parsingBigEndian: &lookahead))
      guard messageSize >= MemoryLayout<OcaUint32>.size else {
        throw Ocp1Error.invalidMessageSize
      }
      var message = try body.sliceSpan(byteCount: messageSize)
      try messages.append(decodeOcp1Message(parsing: &message, type: header.pduType))
    }

    return (header.pduType, messages)
  }

  private nonisolated static func decodeOcp1Message(
    parsing input: inout ParserSpan,
    type messageType: OcaMessageType
  ) throws -> Ocp1Message {
    switch messageType {
    case .ocaCmd, .ocaCmdRrq:
      try Ocp1Command(parsing: &input)
    case .ocaNtf1:
      try Ocp1Notification1(parsing: &input)
    case .ocaRsp:
      try Ocp1Response(parsing: &input)
    case .ocaNtf2:
      try Ocp1Notification2(parsing: &input)
    case .ocaKeepAlive:
      try decodeOcp1KeepAlive(parsing: &input)
    }
  }

  private nonisolated static func decodeOcp1KeepAlive(
    parsing input: inout ParserSpan
  ) throws -> Ocp1Message {
    /// The two keep-alive variants are distinguished only by their length:
    /// `Ocp1KeepAlive1` carries seconds, `Ocp1KeepAlive2` milliseconds.
    switch input.count {
    case MemoryLayout<OcaUint16>.size:
      try Ocp1KeepAlive1(parsing: &input)
    case MemoryLayout<OcaUint32>.size:
      try Ocp1KeepAlive2(parsing: &input)
    default:
      throw Ocp1Error.invalidKeepAlivePdu
    }
  }
}
