//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
import XCTest

/// Several messages for a transport that carries a PDU in a packet.
final class EncodePdusTests: XCTestCase {
  private func notifications(_ count: Int, dataSize: Int = 9) throws -> [Ocp1Message] {
    try (0..<count).map { index in
      try Ocp1Notification2(
        event: OcaEvent(
          emitterONo: OcaONo(0x1000 + index),
          eventID: OcaEventID(defLevel: 1, eventIndex: 1)
        ),
        notificationType: .event,
        eventData: OcaEncodedEventData(
          Data(repeating: UInt8(truncatingIfNeeded: index), count: dataSize),
          format: .ocp1
        )
      )
    }
  }

  private func emitters(in pdus: [Data]) throws -> [[OcaONo]] {
    try pdus.map { pdu in
      let (type, messages) = try OcaControlProtocol.ocp1.decodePdu(pdu)
      XCTAssertEqual(type, .ocaNtf2)
      return messages.compactMap { ($0 as? Ocp1Notification2)?.event.emitterONo }
    }
  }

  func testMessagesThatFitAreOnePdu() throws {
    let messages = try notifications(8)
    let pdus = try OcaControlProtocol.ocp1.encodePdus(messages, type: .ocaNtf2, maximumSize: 1500)

    XCTAssertEqual(pdus.count, 1)
    XCTAssertEqual(pdus, [try OcaControlProtocol.ocp1.encodePdu(messages, type: .ocaNtf2)])
  }

  func testMessagesThatDoNotFitAreDividedInOrder() throws {
    let messages = try notifications(200)
    let pdus = try OcaControlProtocol.ocp1.encodePdus(messages, type: .ocaNtf2, maximumSize: 1500)

    XCTAssertGreaterThan(pdus.count, 1)
    for pdu in pdus {
      XCTAssertLessThanOrEqual(pdu.count, 1500)
    }
    let decoded = try emitters(in: pdus)
    XCTAssertEqual(decoded.flatMap { $0 }, (0..<200).map { OcaONo(0x1000 + $0) })
  }

  /// Each PDU is filled before the next is begun.
  func testEachPduHoldsAsManyMessagesAsFit() throws {
    let messages = try notifications(10)
    let header = OcaConnection.MinimumPduSize
    let messageSize = try OcaControlProtocol.ocp1
      .encodePdu([messages[0]], type: .ocaNtf2).count - header
    // room for three messages, and all but a byte of a fourth
    let pdus = try OcaControlProtocol.ocp1.encodePdus(
      messages,
      type: .ocaNtf2,
      maximumSize: header + 4 * messageSize - 1
    )

    XCTAssertEqual(try emitters(in: pdus).map(\.count), [3, 3, 3, 1])
  }

  /// A JSON PDU's size is not known until it is written, so OCP.2 is divided by halving.
  func testOcp2MessagesThatDoNotFitAreDividedInOrder() throws {
    let emitters = (0..<50).map { OcaONo(0x2000 + $0) }
    let messages: [Ocp1Message] = try emitters.map { emitterONo in
      let eventData = OcaPropertyChangedEventData<OcaFloat32>(
        propertyID: OcaPropertyID("4.1"),
        propertyValue: -12.5,
        changeType: .currentChanged
      )
      return try Ocp1Notification2(
        event: OcaEvent(emitterONo: emitterONo, eventID: OcaPropertyChangedEventID),
        notificationType: .event,
        eventData: .ocp2(Ocp2JSON.sendable(Ocp2Encoder().encodeValue(eventData)))
      )
    }
    let whole = try OcaControlProtocol.ocp2.encodePdu(messages, type: .ocaNtf2)
    let maximumSize = whole.count / 3

    let pdus = try OcaControlProtocol.ocp2
      .encodePdus(messages, type: .ocaNtf2, maximumSize: maximumSize)

    XCTAssertGreaterThan(pdus.count, 1)
    var decoded = [OcaONo]()
    for pdu in pdus {
      XCTAssertLessThanOrEqual(pdu.count, maximumSize)
      let (type, messages) = try OcaControlProtocol.ocp2.decodePdu(pdu)
      XCTAssertEqual(type, .ocaNtf2)
      decoded += messages.compactMap { ($0 as? Ocp1Notification2)?.event.emitterONo }
    }
    XCTAssertEqual(decoded, emitters)
  }

  /// One message cannot be divided; it is left for the transport to refuse.
  func testAMessageTooLargeOnItsOwnIsGivenAPduOfItsOwn() throws {
    let messages = try notifications(3, dataSize: 2000)
    let pdus = try OcaControlProtocol.ocp1.encodePdus(messages, type: .ocaNtf2, maximumSize: 1500)

    XCTAssertEqual(try emitters(in: pdus), [[0x1000], [0x1001], [0x1002]])
  }
}
