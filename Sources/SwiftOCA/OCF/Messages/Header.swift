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

  init(bytes: borrowing[UInt8]) throws {
    guard bytes.count >= Self.HeaderSize else {
      throw Ocp1Error.pduTooShort
    }

    protocolVersion = bytes.withUnsafeBytes {
      OcaUint16(bigEndian: $0.loadUnaligned(fromByteOffset: 0, as: OcaUint16.self))
    }

    guard protocolVersion == Ocp1ProtocolVersion else {
      throw Ocp1Error.invalidProtocolVersion
    }

    pduSize = bytes.withUnsafeBytes {
      OcaUint32(bigEndian: $0.loadUnaligned(fromByteOffset: 2, as: OcaUint32.self))
    }

    guard pduSize >= Self.HeaderSize else {
      throw Ocp1Error.invalidPduSize
    }

    guard let pduType = OcaMessageType(rawValue: bytes[6]) else {
      throw Ocp1Error.invalidMessageType
    }

    self.pduType = pduType

    messageCount = bytes.withUnsafeBytes {
      OcaUint16(bigEndian: $0.loadUnaligned(fromByteOffset: 7, as: OcaUint16.self))
    }
  }

  func encode(into bytes: inout [UInt8]) {
    let startIndex = bytes.count
    bytes += [0, 0, 0, 0, 0, 0, 0, 0, 0] // reserve 9 bytes for header

    withUnsafeBytes(of: protocolVersion.bigEndian) {
      bytes[startIndex] = $0[0]
      bytes[startIndex + 1] = $0[1]
    }

    withUnsafeBytes(of: pduSize.bigEndian) {
      bytes[startIndex + 2] = $0[0]
      bytes[startIndex + 3] = $0[1]
      bytes[startIndex + 4] = $0[2]
      bytes[startIndex + 5] = $0[3]
    }

    bytes[startIndex + 6] = pduType.rawValue

    withUnsafeBytes(of: messageCount.bigEndian) {
      bytes[startIndex + 7] = $0[0]
      bytes[startIndex + 8] = $0[1]
    }
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

protocol _Ocp1ExtendedMessageCodable: _Ocp1MessageCodable {
  init(bytes: borrowing[UInt8], extensionsSupported: Bool) throws
}
