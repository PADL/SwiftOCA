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
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
import XCTest

/// A controller that takes lightweight notifications, and drops every message.
private actor LightweightController: OcaControllerLightweightNotifying {
  nonisolated let flags: OcaControllerFlags = []

  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {}

  func sendMessage(
    _ message: Ocp1Message,
    type messageType: OcaMessageType,
    to destinationAddress: OcaNetworkAddress
  ) async throws {}
}

/// What a controller may subscribe to, and how much: a missing emitter, a subscription
/// it already holds and one over the per-controller limit are all refused.
final class SubscriptionBoundsTests: XCTestCase {
  private struct Harness {
    let device: OcaDevice
    let endpoint: OcaLocalDeviceEndpoint
    let connection: OcaLocalConnection
    let endpointTask: Task<(), Never>

    var manager: SwiftOCA.OcaSubscriptionManager {
      get async { await connection.subscriptionManager }
    }

    var deviceManager: SwiftOCADevice.OcaSubscriptionManager {
      get async throws {
        let manager = await device.subscriptionManager
        return try XCTUnwrap(manager)
      }
    }

    var controller: any OcaController {
      get async throws {
        let controllers = await endpoint.controllers
        return try XCTUnwrap(controllers.first)
      }
    }
  }

  private func makeHarness() async throws -> Harness {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(endpoint)
    try await connection.connect()
    return Harness(
      device: device,
      endpoint: endpoint,
      connection: connection,
      endpointTask: endpointTask
    )
  }

  private static let missingONo: OcaONo = 0x00DE_AD00
  private static let label = OcaPropertyID("1.6")
  private static let subscriber = OcaMethod(oNo: 1055, methodID: OcaMethodID("1.1"))

  /// The rootblock's property-change subscriptions held by the harness's controller.
  private func propertySubscriptions(
    _ harness: Harness,
    to property: OcaPropertyID
  ) async throws -> [OcaSubscriptionManagerSubscription] {
    let controller = try await harness.controller
    let subscribers = try await harness.deviceManager.subscribers(to: OcaRootBlockONo)
    return subscribers.filter { $0.controller === controller }
      .flatMap(\.subscriptions)
      .filter { $0.property == property }
  }

  func testASubscriptionToAMissingObjectIsRefused() async throws {
    let harness = try await makeHarness()
    defer { harness.endpointTask.cancel() }

    do {
      try await harness.manager.addSubscription2(
        event: OcaEvent(emitterONo: Self.missingONo, eventID: OcaPropertyChangedEventID),
        notificationDeliveryMode: .normal,
        destinationInformation: OcaNetworkAddress()
      )
      XCTFail("subscription to a missing object accepted")
    } catch Ocp1Error.status(.badONo) {}

    let statuses = try await harness.manager.addPropertyChangeSubscription2List(
      emitters: [OcaRootBlockONo, Self.missingONo, OcaRootBlockONo],
      properties: [Self.label, Self.label, OcaPropertyID("1.5")],
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )
    XCTAssertEqual(statuses, [.ok, .badONo, .ok])
    let isSubscribed = try await harness.deviceManager
      .isSubscribed(harness.controller, toEventsFrom: Self.missingONo)
    XCTAssertFalse(isSubscribed)
  }

  func testADuplicatePropertyChangeSubscriptionIsRefused() async throws {
    let harness = try await makeHarness()
    defer { harness.endpointTask.cancel() }

    try await harness.manager.addPropertyChangeSubscription2(
      emitter: OcaRootBlockONo,
      property: Self.label,
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )
    // a normal notification goes down the connection, so the destination is no difference
    do {
      try await harness.manager.addPropertyChangeSubscription2(
        emitter: OcaRootBlockONo,
        property: Self.label,
        notificationDeliveryMode: .normal,
        destinationInformation: OcaNetworkAddress([1, 2, 3])
      )
      XCTFail("duplicate property-change subscription accepted")
    } catch Ocp1Error.status(.invalidRequest) {}

    let statuses = try await harness.manager.addPropertyChangeSubscription2List(
      emitters: [OcaRootBlockONo, OcaRootBlockONo],
      properties: [Self.label, OcaPropertyID("1.5")],
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )
    XCTAssertEqual(statuses, [.invalidRequest, .ok])
    let subscriptions = try await propertySubscriptions(harness, to: Self.label)
    XCTAssertEqual(subscriptions.count, 1)
  }

  func testADuplicateEv1PropertyChangeSubscriptionIsRefused() async throws {
    let harness = try await makeHarness()
    defer { harness.endpointTask.cancel() }

    for context in [OcaBlob(), OcaBlob([7])] {
      do {
        try await harness.manager.addPropertyChangeSubscription(
          emitter: OcaRootBlockONo,
          property: Self.label,
          subscriber: Self.subscriber,
          subscriberContext: context,
          notificationDeliveryMode: .normal,
          destinationInformation: OcaNetworkAddress()
        )
        XCTAssertTrue(context.isEmpty, "duplicate EV1 subscription accepted")
      } catch Ocp1Error.status(.invalidRequest) {
        XCTAssertFalse(context.isEmpty)
      }
    }
    let subscriptions = try await propertySubscriptions(harness, to: Self.label)
    XCTAssertEqual(subscriptions.count, 1)
  }

  func testAnEv1PropertyChangeSubscriptionCanBeRemoved() async throws {
    let harness = try await makeHarness()
    defer { harness.endpointTask.cancel() }

    try await harness.manager.addPropertyChangeSubscription(
      emitter: OcaRootBlockONo,
      property: Self.label,
      subscriber: Self.subscriber,
      subscriberContext: OcaBlob([7]),
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )
    var subscriptions = try await propertySubscriptions(harness, to: Self.label)
    XCTAssertEqual(subscriptions.count, 1)

    try await harness.manager.removePropertyChangeSubscription(
      emitter: OcaRootBlockONo,
      property: Self.label,
      subscriber: Self.subscriber
    )
    subscriptions = try await propertySubscriptions(harness, to: Self.label)
    XCTAssertEqual(subscriptions.count, 0)
  }

  private func subscription2(
    to emitterONo: OcaONo,
    mode: OcaNotificationDeliveryMode = .normal,
    destination: OcaNetworkAddress = OcaNetworkAddress()
  ) -> OcaSubscriptionManagerSubscription {
    .subscription2(OcaSubscription2(
      event: OcaEvent(emitterONo: emitterONo, eventID: OcaPropertyChangedEventID),
      notificationDeliveryMode: mode,
      destinationInformation: destination
    ))
  }

  func testANormalSubscriptionIsNotToldApartByDestination() async throws {
    let harness = try await makeHarness()
    defer { harness.endpointTask.cancel() }

    let manager = try await harness.deviceManager
    let controller = LightweightController()
    try await manager.addSubscription(subscription2(to: 7001), for: controller)
    do {
      try await manager.addSubscription(
        subscription2(to: 7001, destination: OcaNetworkAddress([1, 2, 3])),
        for: controller
      )
      XCTFail("normal subscription repeated with another destination accepted")
    } catch Ocp1Error.alreadySubscribedToEvent(_) {}
    let count = await manager.subscriptionCount(for: controller)
    XCTAssertEqual(count, 1)
  }

  func testLightweightSubscriptionsAreToldApartByDestination() async throws {
    let harness = try await makeHarness()
    defer { harness.endpointTask.cancel() }

    let manager = try await harness.deviceManager
    let controller = LightweightController()
    let first = subscription2(to: 7001, mode: .lightweight, destination: OcaNetworkAddress([1]))
    let second = subscription2(to: 7001, mode: .lightweight, destination: OcaNetworkAddress([2]))
    try await manager.addSubscription(first, for: controller)
    try await manager.addSubscription(second, for: controller)
    var count = await manager.subscriptionCount(for: controller)
    XCTAssertEqual(count, 2)

    await manager.removeSubscription(
      subscription2(to: 7001, mode: .lightweight, destination: OcaNetworkAddress([3])),
      for: controller
    )
    count = await manager.subscriptionCount(for: controller)
    XCTAssertEqual(count, 2)

    await manager.removeSubscription(first, for: controller)
    var held = await manager.subscribers(to: 7001).flatMap(\.subscriptions)
    XCTAssertEqual(held, [second])

    await manager.removeSubscription(second, for: controller)
    held = await manager.subscribers(to: 7001).flatMap(\.subscriptions)
    XCTAssertEqual(held, [])
  }

  func testAnInProcessCallerIsNotHeldToTheLimit() async throws {
    let harness = try await makeHarness()
    defer { harness.endpointTask.cancel() }

    let manager = try await harness.deviceManager
    let controller = LightweightController()
    let limit = SwiftOCADevice.OcaSubscriptionManager.maximumSubscriptionsPerController
    for emitterONo in 0..<OcaONo(limit + 1) {
      try await manager.addSubscription(
        subscription2(to: 0x0010_0000 + emitterONo),
        for: controller
      )
    }
    let count = await manager.subscriptionCount(for: controller)
    XCTAssertEqual(count, limit + 1)
  }

  func testAControllerOverTheLimitIsRefused() async throws {
    let harness = try await makeHarness()
    defer { harness.endpointTask.cancel() }

    let deviceManager = try await harness.deviceManager
    let controller = try await harness.controller
    let held = await deviceManager.subscriptionCount(for: controller)
    let limit = SwiftOCADevice.OcaSubscriptionManager.maximumSubscriptionsPerController
    let properties = (0..<(limit - held + 1)).map {
      OcaPropertyID(defLevel: 100, propertyIndex: OcaUint16($0))
    }

    var statuses = try await harness.manager.addPropertyChangeSubscription2List(
      emitters: Array(repeating: OcaRootBlockONo, count: properties.count),
      properties: properties,
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )
    XCTAssertEqual(statuses.dropLast(), Array(repeating: .ok, count: properties.count - 1)[...])
    XCTAssertEqual(statuses.last, .outOfMemory)
    var count = await deviceManager.subscriptionCount(for: controller)
    XCTAssertEqual(count, limit)

    // removing one makes room for one
    try await harness.manager.removePropertyChangeSubscription2(
      emitter: OcaRootBlockONo,
      property: properties[0],
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )
    statuses = try await harness.manager.addPropertyChangeSubscription2List(
      emitters: [OcaRootBlockONo, OcaRootBlockONo],
      properties: [properties[properties.count - 1], properties[0]],
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )
    XCTAssertEqual(statuses, [.ok, .outOfMemory])

    // at the limit the limit is checked first, even for one already held
    statuses = try await harness.manager.addPropertyChangeSubscription2List(
      emitters: [OcaRootBlockONo],
      properties: [properties[1]],
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )
    XCTAssertEqual(statuses, [.outOfMemory])

    await deviceManager.removeSubscriptions(of: controller)
    count = await deviceManager.subscriptionCount(for: controller)
    XCTAssertEqual(count, 0)
  }
}
