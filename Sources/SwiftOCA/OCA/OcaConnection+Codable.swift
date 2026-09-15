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

package extension OcaConnection {
  /// The header for a PDU of `pduSize` bytes, `syncVal` included, throwing if the
  /// size or message count cannot be represented on the wire.
  nonisolated static func ocp1Header(
    type messageType: OcaMessageType,
    messageCount: Int,
    pduSize: Int
  ) throws -> Ocp1Header {
    /// the header's `pduSize` counts every byte after `syncVal`
    guard let headerPduSize = OcaUint32(exactly: pduSize - 1),
          let messageCount = OcaUint16(exactly: messageCount)
    else {
      throw Ocp1Error.invalidPduSize
    }
    return Ocp1Header(pduType: messageType, messageCount: messageCount, pduSize: headerPduSize)
  }

  /// Encodes a whole PDU in a single pass. Every message knows its encoded size
  /// up front, so the PDU is allocated once at its exact size and each size field
  /// is written in place rather than patched afterwards.
  nonisolated static func encodeOcp1MessagePdu(
    _ messages: [Ocp1Message],
    type messageType: OcaMessageType
  ) throws -> Data {
    let pduSize = MinimumPduSize + messages.reduce(0) { $0 + $1.encodedSize }
    let header = try ocp1Header(type: messageType, messageCount: messages.count, pduSize: pduSize)

    return Data(ocp1ByteCount: pduSize) { output in
      output.append(Ocp1SyncValue)
      header.encode(into: &output)
      for message in messages {
        message.encode(into: &output)
      }
    }
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
