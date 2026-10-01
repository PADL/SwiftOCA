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
@_spi(SwiftOCAPrivate) import SwiftOCA
@testable import SwiftOCADevice
import XCTest

private actor CountingController: OcaController {
  nonisolated let flags: OcaControllerFlags = []
  private(set) var sendCount = 0

  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {
    sendCount += 1
  }
}

/// A controller that holds its device, as one that keeps its endpoint does: if the
/// device's subscription manager held it in turn, neither would ever be released.
private actor DeviceHoldingController: OcaController {
  nonisolated let flags: OcaControllerFlags = []
  let device: OcaDevice

  init(device: OcaDevice) { self.device = device }

  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {}
}

/// An endpoint that counts how often it is asked for its controllers.
private actor CountingEndpoint: OcaDeviceEndpoint {
  private let list: [OcaController]
  private(set) var askCount = 0

  init(_ list: [OcaController]) { self.list = list }

  var controllers: [OcaController] {
    askCount += 1
    return list
  }
}

/// The subscription manager holds every subscription, and an event's subscribers are
/// read from it: no endpoint and no controller is asked who subscribes.
final class SubscriberLookupTests: XCTestCase {
  private func event(_ emitterONo: OcaONo, index: OcaUint16 = 1) -> OcaEvent {
    OcaEvent(emitterONo: emitterONo, eventID: OcaEventID(defLevel: 1, eventIndex: index))
  }

  private func subscription(to event: OcaEvent) -> OcaSubscriptionManagerSubscription {
    .subscription2(OcaSubscription2(
      event: event, notificationDeliveryMode: .normal, destinationInformation: OcaNetworkAddress()
    ))
  }

  private func makeDevice() async throws -> (OcaDevice, SwiftOCADevice.OcaSubscriptionManager) {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let manager = await device.subscriptionManager
    return try (device, XCTUnwrap(manager))
  }

  func testAControllerIsNotifiedFromWhenItSubscribesUntilItUnsubscribes() async throws {
    let (device, manager) = try await makeDevice()
    let controller = CountingController()
    let event = event(7001)

    try await device.notifySubscribers(event, parameters: Data())
    var sent = await controller.sendCount
    XCTAssertEqual(sent, 0)

    try await manager.addSubscription(subscription(to: event), for: controller)
    var isSubscribed = await manager.isSubscribed(controller, toEventsFrom: 7001)
    XCTAssertTrue(isSubscribed)
    try await device.notifySubscribers(event, parameters: Data())
    sent = await controller.sendCount
    XCTAssertEqual(sent, 1)

    await manager.removeSubscription(subscription(to: event), for: controller)
    isSubscribed = await manager.isSubscribed(controller, toEventsFrom: 7001)
    XCTAssertFalse(isSubscribed)
    try await device.notifySubscribers(event, parameters: Data())
    sent = await controller.sendCount
    XCTAssertEqual(sent, 1)
    let left = await manager.subscribers(to: 7001)
    XCTAssertTrue(left.isEmpty, "nothing is kept for an emitter nobody subscribes to")
  }

  func testASubscriptionToOneEventOfAnObjectIsNotSentItsOthers() async throws {
    let (device, manager) = try await makeDevice()
    let controller = CountingController()
    try await manager.addSubscription(subscription(to: event(7002, index: 1)), for: controller)

    try await device.notifySubscribers(event(7002, index: 2), parameters: Data())
    var sent = await controller.sendCount
    XCTAssertEqual(sent, 0)
    try await device.notifySubscribers(event(7002, index: 1), parameters: Data())
    sent = await controller.sendCount
    XCTAssertEqual(sent, 1)
  }

  func testTheSameSubscriptionCannotBeMadeTwice() async throws {
    let (_, manager) = try await makeDevice()
    let controller = CountingController()
    try await manager.addSubscription(subscription(to: event(7003)), for: controller)
    do {
      try await manager.addSubscription(subscription(to: event(7003)), for: controller)
      XCTFail("a second subscription to the same event was accepted")
    } catch Ocp1Error.alreadySubscribedToEvent {}
    // another controller's subscription to the same event is its own
    try await manager.addSubscription(subscription(to: event(7003)), for: CountingController())
  }

  func testAControllerThatCannotBeSentLightweightNotificationsIsRefusedThem() async throws {
    let (_, manager) = try await makeDevice()
    let lightweight = OcaSubscriptionManagerSubscription.subscription2(OcaSubscription2(
      event: event(7004), notificationDeliveryMode: .lightweight, destinationInformation: OcaNetworkAddress()
    ))
    do {
      try await manager.addSubscription(lightweight, for: CountingController())
      XCTFail("a lightweight subscription was accepted")
    } catch Ocp1Error.status(.parameterError) {}
  }

  func testAnExpiredControllerIsNoLongerNotified() async throws {
    let (device, manager) = try await makeDevice()
    let staying = CountingController()
    let leaving = CountingController()
    for emitterONo in [7005, 7006] as [OcaONo] {
      try await manager.addSubscription(subscription(to: event(emitterONo)), for: staying)
      try await manager.addSubscription(subscription(to: event(emitterONo)), for: leaving)
    }
    try await device.notifySubscribers(event(7005), parameters: Data())

    await device.expire(controller: leaving)
    try await device.notifySubscribers(event(7005), parameters: Data())
    try await device.notifySubscribers(event(7006), parameters: Data())

    let stayed = await staying.sendCount
    let left = await leaving.sendCount
    XCTAssertEqual(stayed, 3)
    XCTAssertEqual(left, 1)
  }

  /// The manager does not own a controller: it neither keeps one alive nor, through
  /// it, whatever the controller refers to.
  func testAControllerThatGoesWithoutExpiringIsNeitherKeptNorNotified() async throws {
    let (device, manager) = try await makeDevice()
    weak var gone: CountingController?
    do {
      let controller = CountingController()
      gone = controller
      try await manager.addSubscription(subscription(to: event(7010)), for: controller)
      try await manager.addSubscription(subscription(to: event(7011)), for: controller)
      try await device.notifySubscribers(event(7010), parameters: Data())
      let sent = await controller.sendCount
      XCTAssertEqual(sent, 1)
    }
    XCTAssertNil(gone, "the subscription manager kept the controller alive")

    try await device.notifySubscribers(event(7010), parameters: Data())
    for emitterONo in [7010, 7011] as [OcaONo] {
      let left = await manager.subscribers(to: emitterONo)
      XCTAssertTrue(left.isEmpty)
    }
  }

  func testASubscribedControllerThatHoldsItsDeviceMakesNoCycle() async throws {
    weak var controller: DeviceHoldingController?
    weak var device: OcaDevice?
    weak var manager: SwiftOCADevice.OcaSubscriptionManager?
    do {
      let (madeDevice, madeManager) = try await makeDevice()
      let made = DeviceHoldingController(device: madeDevice)
      (controller, device, manager) = (made, madeDevice, madeManager)
      try await madeManager.addSubscription(subscription(to: event(7013)), for: made)
      try await madeDevice.notifySubscribers(event(7013), parameters: Data())
    }
    XCTAssertNil(controller, "the controller is still held")
    XCTAssertNil(device, "the device is still held")
    XCTAssertNil(manager, "the subscription manager is still held")
  }

  func testAnExpiredControllerIsReleased() async throws {
    let (device, manager) = try await makeDevice()
    var controller: CountingController? = CountingController()
    weak var expired = controller
    try await manager.addSubscription(subscription(to: event(7012)), for: XCTUnwrap(controller))
    try await device.expire(controller: XCTUnwrap(controller))
    controller = nil
    XCTAssertNil(expired)
  }

  func testTheControllersOfARemovedEndpointAreNoLongerNotified() async throws {
    let (device, manager) = try await makeDevice()
    let controller = CountingController()
    let endpoint = CountingEndpoint([controller])
    try await device.add(endpoint: endpoint)
    try await manager.addSubscription(subscription(to: event(7007)), for: controller)
    try await device.notifySubscribers(event(7007), parameters: Data())

    try await device.remove(endpoint: endpoint)
    try await device.notifySubscribers(event(7007), parameters: Data())
    let sent = await controller.sendCount
    XCTAssertEqual(sent, 1)
  }

  /// What moving the subscriptions is for: an event, subscribed to or not, asks no
  /// endpoint for its controllers.
  func testAnEventAsksNoEndpointForItsControllers() async throws {
    let (device, manager) = try await makeDevice()
    let controller = CountingController()
    let endpoint = CountingEndpoint([controller])
    try await device.add(endpoint: endpoint)
    try await manager.addSubscription(subscription(to: event(7008)), for: controller)

    for _ in 0..<100 {
      try await device.notifySubscribers(event(7008), parameters: Data())
      try await device.notifySubscribers(event(7009), parameters: Data())
    }
    let sent = await controller.sendCount
    XCTAssertEqual(sent, 100)
    let asked = await endpoint.askCount
    XCTAssertEqual(asked, 0)
  }
}
