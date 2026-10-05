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
@_spi(SwiftOCAPrivate) import SwiftOCA
@testable import SwiftOCADevice
import Synchronization
import XCTest

private let encodings = Atomic<Int>(0)

/// A value that counts how often it is encoded.
private struct CountedValue: Codable, Sendable {
  var value: OcaUint16 = 1

  init() {}

  init(from decoder: any Decoder) throws {
    value = try OcaUint16(from: decoder)
  }

  func encode(to encoder: any Encoder) throws {
    encodings.add(1, ordering: .relaxed)
    try value.encode(to: encoder)
  }
}

/// A controller that acts on the events it is subscribed to itself, as an in-process
/// one would, and is sent none.
private actor ObservingController: OcaController {
  nonisolated let flags: OcaControllerFlags = []
  nonisolated var controlProtocol: OcaControlProtocol { .ocp2 }
  private let observed = Mutex<[(OcaEvent, OcaPropertyID?)]>([])
  private(set) var sent = 0

  nonisolated var observedEvents: [(OcaEvent, OcaPropertyID?)] { observed.withLock { $0 } }

  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {
    sent += messages.count
  }

  nonisolated func isNotifiable(event: OcaEvent, parameters: OcaEventParameters) -> Bool {
    observed.withLock { $0.append((event, parameters.propertyID)) }
    return false
  }
}

private final class MockEndpoint: OcaDeviceEndpoint, @unchecked Sendable {
  let controllers: [OcaController]

  init(controllers: [OcaController]) {
    self.controllers = controllers
  }
}

final class UnnotifiedEventTests: XCTestCase {
  private static let emitter: OcaONo = 4343
  private static let event = OcaEvent(emitterONo: emitter, eventID: OcaPropertyChangedEventID)

  private func subscribe(
    _ controller: ObservingController,
    to property: OcaPropertyID
  ) async throws -> OcaDevice {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let manager = await device.subscriptionManager
    try await XCTUnwrap(manager).addSubscription(
      .propertyChangeSubscription2(OcaPropertyChangeSubscription2(
        emitter: Self.emitter, property: property,
        notificationDeliveryMode: .normal, destinationInformation: OcaNetworkAddress()
      )),
      for: controller
    )
    try await device.add(endpoint: MockEndpoint(controllers: [controller]))
    return device
  }

  private func changed(_ property: OcaPropertyID) -> OcaPropertyChangedEventData<CountedValue> {
    OcaPropertyChangedEventData(propertyID: property, propertyValue: CountedValue(), changeType: .currentChanged)
  }

  func testAnEventThatIsNotNotifiableIsNeitherEncodedNorSent() async throws {
    let controller = ObservingController()
    let device = try await subscribe(controller, to: OcaPropertyID("2.3"))
    encodings.store(0, ordering: .relaxed)

    try await device.notifySubscribers(Self.event, parameters: changed(OcaPropertyID("2.3")))
    try await device.withCoalescedNotifications {
      try await device.notifySubscribers(Self.event, parameters: changed(OcaPropertyID("2.3")))
    }

    XCTAssertEqual(controller.observedEvents.map(\.1), [OcaPropertyID("2.3"), OcaPropertyID("2.3")])
    XCTAssertEqual(controller.observedEvents.first?.0.emitterONo, Self.emitter)
    let sent = await controller.sent
    XCTAssertEqual(sent, 0)
    XCTAssertEqual(encodings.load(ordering: .relaxed), 0)
  }

  func testAnEventNoSubscriptionMatchesIsNotOffered() async throws {
    let controller = ObservingController()
    let device = try await subscribe(controller, to: OcaPropertyID("2.3"))
    try await device.notifySubscribers(Self.event, parameters: changed(OcaPropertyID("2.4")))
    XCTAssertTrue(controller.observedEvents.isEmpty)
  }
}
