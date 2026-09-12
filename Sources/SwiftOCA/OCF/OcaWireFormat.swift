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
      try Ocp1Connection.encodeOcp1MessagePdu(messages, type: messageType)
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
      try Ocp1Connection.decodeOcp1MessagePdu(from: data)
    #if NonEmbeddedBuild
    case .ocp2:
      try Ocp2Message.decodePdu(data)
    #endif
    }
  }

  /// Batching support: encode one message; `assemblePdu` later combines any
  /// number of same-type encoded messages into one PDU. Generic, so a message
  /// reaches the encoder without being boxed; `internal` because
  /// `_Ocp1MessageCodable` is, and only the batcher (in this module) sends one
  /// message at a time.
  internal func encodeMessage(
    _ message: some _Ocp1MessageCodable,
    type messageType: OcaMessageType
  ) throws -> [UInt8] {
    switch self {
    case .ocp1:
      var bytes = [UInt8]()
      try message.encode(type: messageType, into: &bytes)
      return bytes
    #if NonEmbeddedBuild
    case .ocp2:
      return try Ocp2Message.encodeMessage(message, type: messageType)
    #endif
    }
  }

  func assemblePdu(
    type messageType: OcaMessageType,
    encodedMessages: [[UInt8]]
  ) throws -> [UInt8] {
    switch self {
    case .ocp1:
      try Ocp1Connection.encodeOcp1MessagePduData(type: messageType, encodedPdus: encodedMessages)
    #if NonEmbeddedBuild
    case .ocp2:
      try Ocp2Message.assemblePdu(type: messageType, encodedMessages: encodedMessages)
    #endif
    }
  }

  /// Bytes a PDU carrying `messageCount` messages adds beyond the messages
  /// themselves, for batch size accounting.
  func pduOverhead(messageCount: Int) -> Int {
    switch self {
    case .ocp1:
      Ocp1Connection.MinimumPduSize
    #if NonEmbeddedBuild
    case .ocp2:
      Ocp2Message.pduOverhead(messageCount: messageCount)
    #endif
    }
  }

  /// A reader for one receive loop. `isMessageOriented` transports deliver a whole
  /// PDU per read.
  func makeReader(isMessageOriented: Bool, maximumPduSize: Int) -> any OcaPduReader {
    switch self {
    case .ocp1:
      Ocp1PduReader(maximumPduSize: maximumPduSize)
    #if NonEmbeddedBuild
    case .ocp2:
      Ocp2PduReader(isMessageOriented: isMessageOriented, maximumPduSize: maximumPduSize)
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

  /// WebSocket subprotocol to offer/accept, or `nil` for none.
  var webSocketSubprotocol: String? {
    switch self {
    case .ocp1:
      nil
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
