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
@testable import SwiftOCADevice
import XCTest

final class PacketTransportSendTests: XCTestCase {
  /// A controller whose transport sends a PDU in a packet is sent as many as it takes.
  @OcaDevice
  func testAControllerOnAPacketTransportIsSentNoPduLargerThanItCarries() async throws {
    typealias Endpoint = DatagramProxyDeviceEndpoint<Int>
    let (input, _) = AsyncStream<Endpoint.PeerMessagePDU>.makeStream()
    let (output, outputContinuation) = AsyncStream<Endpoint.PeerMessagePDU>.makeStream()
    let endpoint = try await Endpoint(
      maximumSendPduSize: 200,
      inputStream: input,
      outputStream: outputContinuation,
      device: OcaDevice()
    )
    let controller = DatagramProxyController(with: 1, endpoint: endpoint)
    let emitters = (0..<40).map { OcaONo(8200 + $0) }
    let messages: [Ocp1Message] = try emitters.map {
      try Ocp1Notification2(
        event: OcaEvent(emitterONo: $0, eventID: OcaEventID(defLevel: 1, eventIndex: 1)),
        notificationType: .event,
        eventData: OcaEncodedEventData(Data(count: 9), format: .ocp1)
      )
    }

    try await controller.sendMessages(messages, type: .ocaNtf2)
    outputContinuation.finish()

    var sent = [OcaONo]()
    var pdus = 0
    for await (_, pdu) in output {
      XCTAssertLessThanOrEqual(pdu.count, 200)
      let (_, decoded) = try OcaControlProtocol.ocp1.decodePdu(Data(pdu))
      sent += decoded.compactMap { ($0 as? Ocp1Notification2)?.event.emitterONo }
      pdus += 1
    }
    XCTAssertGreaterThan(pdus, 1)
    XCTAssertEqual(sent, emitters)
  }
}
