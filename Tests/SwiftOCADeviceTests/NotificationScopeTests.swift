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
import Synchronization
import XCTest

private struct ScopeFailure: Error {}

/// Records each call to send it messages: the emitters of the notifications in it.
private actor RecordingController: OcaControllerLightweightNotifying {
  nonisolated let flags: OcaControllerFlags = []
  private(set) var sends = [[OcaONo]]()
  private(set) var lightweightSends = [OcaONo]()

  private func emitter(of message: Ocp1Message) -> OcaONo {
    (message as? Ocp1Notification2)?.event.emitterONo ?? OcaInvalidONo
  }

  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {
    sends.append(messages.map(emitter))
  }

  func sendMessage(
    _ message: Ocp1Message,
    type messageType: OcaMessageType,
    to destinationAddress: OcaNetworkAddress
  ) async throws {
    lightweightSends.append(emitter(of: message))
  }
}

/// A controller whose first send does not finish until it is let through.
private actor GatedController: OcaController {
  nonisolated let flags: OcaControllerFlags = []
  private(set) var sends = [[OcaONo]]()
  private(set) var isWaiting = false
  private var isGated = true
  private var gate: CheckedContinuation<(), Never>?

  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {
    if isGated {
      isGated = false
      isWaiting = true
      await withCheckedContinuation { gate = $0 }
    }
    sends.append(messages.map { ($0 as? Ocp1Notification2)?.event.emitterONo ?? OcaInvalidONo })
  }

  func open() {
    gate?.resume()
    gate = nil
  }
}

final class NotificationScopeTests: XCTestCase {
  private func event(_ emitterONo: OcaONo) -> OcaEvent {
    OcaEvent(emitterONo: emitterONo, eventID: OcaEventID(defLevel: 1, eventIndex: 1))
  }

  private func subscription(
    to emitterONo: OcaONo,
    mode: OcaNotificationDeliveryMode = .normal
  ) -> OcaSubscriptionManagerSubscription {
    .subscription2(OcaSubscription2(
      event: event(emitterONo),
      notificationDeliveryMode: mode,
      destinationInformation: OcaNetworkAddress()
    ))
  }

  private func makeDevice(
    subscribing controller: RecordingController,
    to emitters: [OcaONo]
  ) async throws -> OcaDevice {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let manager = await device.subscriptionManager
    for emitterONo in emitters {
      try await XCTUnwrap(manager).addSubscription(subscription(to: emitterONo), for: controller)
    }
    return device
  }

  func testNotificationsRaisedInAScopeAreSentTogetherWhenItEnds() async throws {
    let controller = RecordingController()
    let emitters: [OcaONo] = [8001, 8002, 8003, 8004]
    let device = try await makeDevice(subscribing: controller, to: emitters)

    try await device.withCoalescedNotifications {
      for emitterONo in emitters {
        try await device.notifySubscribers(event(emitterONo), parameters: Data())
      }
      // an event nobody subscribes to adds nothing
      try await device.notifySubscribers(event(8999), parameters: Data())
      let held = await controller.sends
      XCTAssertEqual(held, [], "a notification was sent before the scope ended")
    }

    let sends = await controller.sends
    XCTAssertEqual(sends, [emitters])
  }

  func testOutsideAScopeEachNotificationIsSentOnItsOwn() async throws {
    let controller = RecordingController()
    let device = try await makeDevice(subscribing: controller, to: [8011, 8012])

    try await device.notifySubscribers(event(8011), parameters: Data())
    try await device.notifySubscribers(event(8012), parameters: Data())

    let sends = await controller.sends
    XCTAssertEqual(sends, [[8011], [8012]])
  }

  func testEachControllerIsSentWhatItSubscribedToInTheOrderItWasRaised() async throws {
    let first = RecordingController()
    let second = RecordingController()
    let device = try await makeDevice(subscribing: first, to: [8021, 8022, 8023])
    let manager = await device.subscriptionManager
    try await XCTUnwrap(manager).addSubscription(subscription(to: 8022), for: second)

    try await device.withCoalescedNotifications {
      for emitterONo in [8023, 8021, 8022, 8021] as [OcaONo] {
        try await device.notifySubscribers(event(emitterONo), parameters: Data())
      }
    }

    let firstSends = await first.sends
    let secondSends = await second.sends
    XCTAssertEqual(firstSends, [[8023, 8021, 8022, 8021]])
    XCTAssertEqual(secondSends, [[8022]])
  }

  /// A lightweight notification goes somewhere other than down the controller's
  /// connection, in a datagram of its own; it is not held.
  func testALightweightNotificationIsSentAtOnce() async throws {
    let controller = RecordingController()
    let device = try await makeDevice(subscribing: controller, to: [8031])
    let manager = await device.subscriptionManager
    try await XCTUnwrap(manager)
      .addSubscription(subscription(to: 8032, mode: .lightweight), for: controller)

    try await device.withCoalescedNotifications {
      try await device.notifySubscribers(event(8032), parameters: Data())
      try await device.notifySubscribers(event(8031), parameters: Data())
      let lightweight = await controller.lightweightSends
      XCTAssertEqual(lightweight, [8032])
    }

    let sends = await controller.sends
    XCTAssertEqual(sends, [[8031]])
  }

  func testAScopeThatThrowsStillSendsWhatWasRaised() async throws {
    let controller = RecordingController()
    let device = try await makeDevice(subscribing: controller, to: [8041])

    do {
      try await device.withCoalescedNotifications {
        try await device.notifySubscribers(event(8041), parameters: Data())
        throw ScopeFailure()
      }
      XCTFail("the scope's error was swallowed")
    } catch is ScopeFailure {}

    let sends = await controller.sends
    XCTAssertEqual(sends, [[8041]])
  }

  func testAScopeThatRaisesNothingSendsNothing() async throws {
    let controller = RecordingController()
    let device = try await makeDevice(subscribing: controller, to: [8051])

    let result = await device.withCoalescedNotifications { 42 }

    XCTAssertEqual(result, 42)
    let sends = await controller.sends
    XCTAssertEqual(sends, [])
  }

  /// Only what is raised while the scope is open is held.
  func testWhatATaskTheScopeStartedRaisesAfterItHasEndedIsSentOnItsOwn() async throws {
    let controller = RecordingController()
    let device = try await makeDevice(subscribing: controller, to: [8061, 8062])
    let isOpen = Mutex(false)
    let late = event(8062)

    let straggler = await device.withCoalescedNotifications {
      try? await device.notifySubscribers(event(8061), parameters: Data())
      return Task { @Sendable in
        while !isOpen.withLock({ $0 }) { await Task.yield() }
        try await device.notifySubscribers(late, parameters: Data())
      }
    }
    var sends = await controller.sends
    XCTAssertEqual(sends, [[8061]])

    isOpen.withLock { $0 = true }
    try await straggler.value
    sends = await controller.sends
    XCTAssertEqual(sends, [[8061], [8062]])
  }

  /// The whole way: a client subscribed over a connection is called back for every
  /// notification of a scope, in order, though they reach it in one PDU.
  func testAClientReceivesEveryNotificationOfAScope() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    defer { endpointTask.cancel() }
    let connection = await OcaLocalConnection(endpoint)
    try await connection.connect()

    let emitters = (0..<40).map { OcaONo(8100 + $0) }
    let received = Mutex([OcaONo]())
    for emitterONo in emitters {
      _ = try await connection.addSubscription(event: event(emitterONo)) { event, _ in
        received.withLock { $0.append(event.emitterONo) }
      }
    }

    try await device.withCoalescedNotifications {
      for emitterONo in emitters {
        try await device.notifySubscribers(event(emitterONo), parameters: Data([0x01]))
      }
    }

    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while received.withLock({ $0.count }) < emitters.count, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertEqual(received.withLock { $0 }, emitters)
    try await connection.disconnect()
  }

  /// A scope that ends sends everything pending, so what an outer scope raised first goes
  /// first; what is raised after waits for the outer scope.
  func testAScopeInsideAnotherSendsWhatIsPendingWhenItEnds() async throws {
    let controller = RecordingController()
    let device = try await makeDevice(subscribing: controller, to: [8071, 8072, 8073])

    try await device.withCoalescedNotifications {
      try await device.notifySubscribers(event(8071), parameters: Data())
      try await device.withCoalescedNotifications {
        try await device.notifySubscribers(event(8072), parameters: Data())
      }
      let sent = await controller.sends
      XCTAssertEqual(sent, [[8071, 8072]])
      try await device.notifySubscribers(event(8073), parameters: Data())
      let held = await controller.sends
      XCTAssertEqual(held, [[8071, 8072]])
    }

    let sends = await controller.sends
    XCTAssertEqual(sends, [[8071, 8072], [8073]])
  }

  /// The device holds what any task raises while a scope is open: sent at once, it could
  /// reach a controller before what was raised first.
  func testWhatAnotherTaskRaisesWhileAScopeIsOpenWaitsInOrder() async throws {
    let controller = RecordingController()
    let other = RecordingController()
    let device = try await makeDevice(subscribing: controller, to: [8091, 8092, 8093])
    let manager = await device.subscriptionManager
    try await XCTUnwrap(manager).addSubscription(subscription(to: 8092), for: other)
    let events = [event(8091), event(8092), event(8093)]

    try await device.withCoalescedNotifications {
      try await device.notifySubscribers(events[0], parameters: Data())
      try await Task.detached {
        try await device.notifySubscribers(events[1], parameters: Data())
      }.value
      let held = await controller.sends
      XCTAssertEqual(held, [], "a notification overtook one raised before it")
      let heldForOther = await other.sends
      XCTAssertEqual(heldForOther, [])
      try await device.notifySubscribers(events[2], parameters: Data())
    }

    let sends = await controller.sends
    XCTAssertEqual(sends, [[8091, 8092, 8093]])
    let otherSends = await other.sends
    XCTAssertEqual(otherSends, [[8092]])
  }

  /// Two tasks with a scope open at once: the first to end sends what both have raised.
  func testScopesOpenAtOnceKeepAControllersNotificationsInTheOrderRaised() async throws {
    let controller = RecordingController()
    let device = try await makeDevice(subscribing: controller, to: [8111, 8112, 8113])
    let events = [event(8111), event(8112), event(8113)]

    try await device.withCoalescedNotifications {
      try await device.notifySubscribers(events[0], parameters: Data())
      try await Task.detached {
        try await device.withCoalescedNotifications {
          try await device.notifySubscribers(events[1], parameters: Data())
        }
      }.value
      try await device.notifySubscribers(events[2], parameters: Data())
    }

    let sends = await controller.sends
    XCTAssertEqual(sends, [[8111, 8112], [8113]])
  }

  /// What is pending for a controller does not keep it: one that goes meanwhile is sent nothing.
  func testWhatIsPendingDoesNotKeepAControllerThatHasGone() async throws {
    var controller: RecordingController? = RecordingController()
    weak var gone = controller
    let device = try await makeDevice(subscribing: controller!, to: [8121])
    let raised = event(8121)

    try await device.withCoalescedNotifications {
      try await device.notifySubscribers(raised, parameters: Data())
      controller = nil
      XCTAssertNil(gone, "a pending notification kept its controller")
    }
  }

  /// What is raised while a scope's notifications are still being sent waits for them:
  /// sent at once, it could reach the controller first.
  func testWhatIsRaisedWhileAScopeIsBeingSentFollowsIt() async throws {
    let controller = GatedController()
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let manager = await device.subscriptionManager
    for emitterONo in [8131, 8132] as [OcaONo] {
      try await XCTUnwrap(manager).addSubscription(subscription(to: emitterONo), for: controller)
    }
    let events = [event(8131), event(8132)]

    let scope = Task {
      try await device.withCoalescedNotifications {
        try await device.notifySubscribers(events[0], parameters: Data())
      }
    }
    while await !controller.isWaiting { await Task.yield() }
    try await device.notifySubscribers(events[1], parameters: Data())
    try await Task.sleep(for: .milliseconds(20))
    let overtaking = await controller.sends
    XCTAssertEqual(overtaking, [], "a notification overtook a scope still being sent")

    await controller.open()
    try await scope.value
    let sends = await controller.sends
    XCTAssertEqual(sends, [[8131], [8132]])
  }
}
