//
// Copyright (c) 2026 PADL Software Pty Ltd
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

/// The AES70 control protocol spoken on a connection.
///
/// Both protocols carry the same in-memory message model (`Ocp1Command`,
/// `Ocp1Response`, `Ocp1Notification2`, keep-alives); they differ only in how a
/// PDU is framed and how method parameters are marshaled. The `Ocp1*` message
/// types are therefore the protocol-neutral model, despite their names.
public enum OcaControlProtocol: String, Codable, Sendable, CaseIterable {
  /// AES70-3: binary PDUs, positional parameters
  case ocp1
  #if NonEmbeddedBuild
  /// AES70-4: newline-delimited JSON PDUs, named parameters
  case ocp2
  #endif
}

/// The marshaling of `OcaParameters.parameterData`.
public enum OcaParameterFormat: Sendable, Hashable {
  /// positional OCP.1 bytes, counted by `parameterCount`
  case ocp1
  /// a serialised OCP.2 JSON `Parameters` object
  case ocp2
}

/// Reads one PDU at a time from a transport. Owned by exactly one receive loop
/// and not `Sendable`: it buffers bytes between PDUs on stream transports.
///
/// `read(n, awaitingAllRead)` returns exactly `n` bytes when `awaitingAllRead`, else
/// between 1 and `n` as soon as any are available; a message-oriented transport
/// returns one whole message either way, ignoring `n`. It throws on EOF.
package protocol OcaPduReader: AnyObject {
  func nextPdu(
    read: (_ count: Int, _ awaitingAllRead: Bool) async throws -> Data
  ) async throws -> Data
}

public extension OcaControlProtocol {
  /// Default maximum PDU size accepted from the peer.
  static let defaultMaximumPduSize = 16 * 1024 * 1024
}

/// A message ready to be appended to a PDU, its encoded size already known.
enum OcaPreparedMessage<Message: _Ocp1MessageCodable> {
  /// written in place when appended
  case ocp1(Message, encodedSize: Int)
  #if NonEmbeddedBuild
  /// serialised up front, as a JSON message's size is only known once it is written
  case ocp2([UInt8])
  #endif

  var encodedSize: Int {
    switch self {
    case let .ocp1(_, encodedSize):
      encodedSize
    #if NonEmbeddedBuild
    case let .ocp2(bytes):
      bytes.count
    #endif
    }
  }
}

/// Framing, as a switch on the protocol rather than a witness table: the two
/// framings are a closed set and hold no state (per-connection reader state lives
/// in the `OcaPduReader` they vend), so an existential would buy nothing and cost a
/// dynamic dispatch — and, for a message passed as `any Ocp1Message`, a heap box on
/// every send, since the message types are larger than an existential's inline
/// buffer.
package extension OcaControlProtocol {
  /// Encode a whole PDU.
  func encodePdu(_ messages: [Ocp1Message], type messageType: OcaMessageType) throws -> Data {
    switch self {
    case .ocp1:
      try OcaConnection.encodeOcp1MessagePdu(messages, type: messageType)
    #if NonEmbeddedBuild
    case .ocp2:
      try Ocp2Message.encodePdu(messages, type: messageType)
    #endif
    }
  }

  /// Decode a whole PDU into its message type and messages.
  func decodePdu(_ data: Data) throws -> (OcaMessageType, [Ocp1Message]) {
    switch self {
    case .ocp1:
      try OcaConnection.decodeOcp1MessagePdu(from: data)
    #if NonEmbeddedBuild
    case .ocp2:
      try Ocp2Message.decodePdu(data)
    #endif
    }
  }

  /// Validates the boundary of one PDU delivered by a packet transport before
  /// its contents are decoded. Packet data must never be joined to another packet.
  func validatePacketPdu(_ data: Data, maximumPduSize: Int) throws {
    switch self {
    case .ocp1:
      try Ocp1PduReader.validatePacket(data, maximumPduSize: maximumPduSize)
    #if NonEmbeddedBuild
    case .ocp2:
      guard data.count <= maximumPduSize + 2 else {
        throw Ocp1Error.invalidPduSize
      }
    #endif
    }
  }

  /// Batching support: a PDU is built in place, one message at a time. A message
  /// is prepared first, so its size is known before the batcher decides which PDU
  /// it joins; `beginPdu`, `appendMessage` and `finishPdu` then write it with no
  /// intermediate buffer per message. Generic, so a message reaches the encoder
  /// without being boxed; `internal` because `_Ocp1MessageCodable` is, and only
  /// the batcher (in this module) sends one message at a time.
  internal func prepareMessage<Message: _Ocp1MessageCodable>(
    _ message: Message,
    type messageType: OcaMessageType
  ) throws -> OcaPreparedMessage<Message> {
    switch self {
    case .ocp1:
      let encodedSize = message.encodedSize
      /// a message too large for any PDU would otherwise trap writing its size
      guard OcaUint32(exactly: OcaConnection.MinimumPduSize - 1 + encodedSize) != nil else {
        throw Ocp1Error.invalidPduSize
      }
      return .ocp1(message, encodedSize: encodedSize)
    #if NonEmbeddedBuild
    case .ocp2:
      return try .ocp2(Ocp2Message.encodeMessage(message, type: messageType))
    #endif
    }
  }

  /// A PDU holding no messages yet, with room reserved for `capacity` bytes of them.
  func beginPdu(type messageType: OcaMessageType, reservingCapacity capacity: Int = 0) throws -> Data {
    switch self {
    case .ocp1:
      var pdu = Data(capacity: OcaConnection.MinimumPduSize + capacity)
      /// `syncVal` and the header, written by `finishPdu` once the size and count are known
      pdu.count = OcaConnection.MinimumPduSize
      return pdu
    #if NonEmbeddedBuild
    case .ocp2:
      let prefix = try Ocp2Message.pduPrefix(type: messageType)
      var pdu = Data(capacity: prefix.count + capacity + 3)
      pdu.append(contentsOf: prefix)
      return pdu
    #endif
    }
  }

  /// Appends a prepared message to a PDU already holding `messageCount` messages.
  internal func appendMessage(
    _ message: OcaPreparedMessage<some _Ocp1MessageCodable>,
    to pdu: inout Data,
    messageCount: Int
  ) {
    switch message {
    case let .ocp1(message, encodedSize):
      pdu.appendOcp1(byteCount: encodedSize) { message.encode(into: &$0) }
    #if NonEmbeddedBuild
    case let .ocp2(bytes):
      if messageCount > 0 {
        pdu.append(UInt8(ascii: ","))
      }
      pdu.append(contentsOf: bytes)
    #endif
    }
  }

  /// Completes a PDU holding `messageCount` messages, ready to send.
  func finishPdu(_ pdu: inout Data, type messageType: OcaMessageType, messageCount: Int) throws {
    switch self {
    case .ocp1:
      let header = try OcaConnection.ocp1Header(
        type: messageType,
        messageCount: messageCount,
        pduSize: pdu.count
      )
      pdu.withOcp1Output(at: 0, byteCount: OcaConnection.MinimumPduSize) { output in
        output.append(Ocp1SyncValue)
        header.encode(into: &output)
      }
    #if NonEmbeddedBuild
    case .ocp2:
      pdu.append(contentsOf: Ocp2Message.pduSuffix(type: messageType))
    #endif
    }
  }

  /// The size `pdu`, holding `messageCount` messages, will have once finished, with
  /// a further message of `additionalMessageSize` bytes if one is given. For batch
  /// size accounting.
  func finishedPduSize(
    _ pdu: Data,
    messageCount: Int,
    type messageType: OcaMessageType,
    adding additionalMessageSize: Int? = nil
  ) -> Int {
    let size = pdu.count + (additionalMessageSize ?? 0)
    switch self {
    case .ocp1:
      return size
    #if NonEmbeddedBuild
    case .ocp2:
      let separatorSize = additionalMessageSize != nil && messageCount > 0 ? 1 : 0
      return size + separatorSize + Ocp2Message.pduSuffix(type: messageType).count
    #endif
    }
  }

  /// A reader for one receive loop. `preservesPduBoundaries` means every read
  /// is exactly one transport packet containing one PDU; WebSocket messages are
  /// deliberately a byte stream and therefore pass `false`.
  func makeReader(preservesPduBoundaries: Bool, maximumPduSize: Int) -> any OcaPduReader {
    switch self {
    case .ocp1:
      Ocp1PduReader(
        preservesPduBoundaries: preservesPduBoundaries,
        maximumPduSize: maximumPduSize
      )
    #if NonEmbeddedBuild
    case .ocp2:
      Ocp2PduReader(
        preservesPduBoundaries: preservesPduBoundaries,
        maximumPduSize: maximumPduSize
      )
    #endif
    }
  }

  /// The connection prefix for the protocol in use: `ocp1` on OCP.1, `ocp2` on OCP.2.
  func connectionPrefix(ocp1: String, ocp2: String) -> String {
    switch self {
    case .ocp1: ocp1
    #if NonEmbeddedBuild
    case .ocp2: ocp2
    #endif
    }
  }

  /// WebSocket subprotocol to offer/accept (AES70-3 8.4.3.4.2, AES70-4 10.4.3.4.2).
  var webSocketSubprotocol: String? {
    switch self {
    case .ocp1:
      "AES70-OCP.1"
    #if NonEmbeddedBuild
    case .ocp2:
      "AES70-OCP.2"
    #endif
    }
  }

  /// Whether WebSocket frames carry text (OCP.2) or binary (OCP.1).
  var webSocketUsesTextFrames: Bool {
    switch self {
    case .ocp1:
      false
    #if NonEmbeddedBuild
    case .ocp2:
      true
    #endif
    }
  }
}
