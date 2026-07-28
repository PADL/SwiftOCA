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

public let Ocp1SyncValue: OcaUint8 = 0x3B
public let Ocp1ProtocolVersion1: OcaUint16 = 1
public let Ocp1ProtocolVersion: OcaUint16 = Ocp1ProtocolVersion1

public struct Ocp1Header: Codable, Sendable, _Ocp1Codable {
  /// offset 0 (1 relative to start of PDU)
  public let protocolVersion: OcaUint16
  /// offset 2 (3 relative to start of PDU); size of PDU not including `syncVal`
  public let pduSize: OcaUint32
  /// offset 6 (7 relative to start of PDU)
  public let pduType: OcaMessageType
  /// offset 7 (8 relative to start of PDU), absent for `ocaKeepAlive` messages
  public let messageCount: OcaUint16

  init(pduType: OcaMessageType, messageCount: OcaUint16) {
    protocolVersion = Ocp1ProtocolVersion
    pduSize = 0
    self.pduType = pduType
    self.messageCount = messageCount
  }

  init() {
    self.init(pduType: .ocaKeepAlive, messageCount: 0)
  }

  package static let HeaderSize = 9

  init(parsing input: inout ParserSpan) throws {
    protocolVersion = try OcaUint16(parsingBigEndian: &input)

    // AES70-3-2024 says that the OCP.1 protocol version should always be 1,
    // but some clients send higher versions (presumably to match the AES70
    // revision). accept those; we will need to use different heuristics if the
    // actual wire protocol changes.
    guard protocolVersion >= Ocp1ProtocolVersion else {
      throw Ocp1Error.invalidProtocolVersion
    }

    pduSize = try OcaUint32(parsingBigEndian: &input)

    guard pduSize >= Self.HeaderSize else {
      throw Ocp1Error.invalidPduSize
    }

    pduType = try OcaMessageType(parsing: &input)
    messageCount = try OcaUint16(parsingBigEndian: &input)
  }

  func encode(into bytes: inout [UInt8]) {
    withUnsafeBytes(of: protocolVersion.bigEndian) { bytes.append(contentsOf: $0) }
    withUnsafeBytes(of: pduSize.bigEndian) { bytes.append(contentsOf: $0) }
    bytes.append(pduType.rawValue)
    withUnsafeBytes(of: messageCount.bigEndian) { bytes.append(contentsOf: $0) }
  }
}

public protocol Ocp1MessagePdu: Codable, Sendable {
  var syncVal: OcaUint8 { get }
  var header: Ocp1Header { get }
}

// TODO: currently tests depend on Codable, but this should be removed eventually

public protocol Ocp1Message: Codable, Sendable {
  var messageSize: OcaUint32 { get }
}

protocol _Ocp1MessageCodable: Ocp1Message & _Ocp1Codable {}
