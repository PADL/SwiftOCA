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
@testable import SwiftOCADevice
@_spi(SwiftOCAPrivate) import SwiftOCA
import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif
import SocketAddress

/// Stands in for a controller whose socket is slow. `sendMessages` is an `OcaController`
/// requirement, so the fan-out reaches this rather than a real transport.
private actor SlowController: OcaController {
  nonisolated let flags: OcaControllerFlags = []

  private let delay: Duration
  private(set) var sendCount = 0
  private(set) var enteredAt: ContinuousClock.Instant?

  init(delay: Duration) {
    self.delay = delay
  }

  func sendMessages(
    _ messages: [Ocp1Message],
    type messageType: OcaMessageType
  ) async throws {
    if enteredAt == nil { enteredAt = .now }
    sendCount += 1
    try? await Task.sleep(for: delay)
  }
}

/// A controller with a transport of its own to queue on, whose peer has stopped reading:
/// `sendMessages` never returns, while `queueMessages` takes the message and returns.
private actor StalledQueuedController: OcaControllerQueuedSending {
  nonisolated let flags: OcaControllerFlags = []
  private(set) var queued = 0
  private(set) var sent = 0

  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {
    sent += 1
    try? await Task.sleep(for: .seconds(3600))
  }

  func queueMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {
    queued += 1
  }
}

private final class MockEndpoint: OcaDeviceEndpoint, @unchecked Sendable {
  let controllers: [OcaController]

  nonisolated var address: any SocketAddress { sockaddr_storage() }

  init(controllers: [OcaController]) {
    self.controllers = controllers
  }
}

final class NotificationFanOutTests: XCTestCase {
  private static let emitter: OcaONo = 4242

  private func makeEvent() -> OcaEvent {
    OcaEvent(emitterONo: Self.emitter, eventID: OcaEventID(defLevel: 1, eventIndex: 2))
  }

  private func subscription(for event: OcaEvent) -> OcaSubscriptionManagerSubscription {
    .subscription2(OcaSubscription2(
      event: event,
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    ))
  }

  /// Every subscribed controller must be entered without waiting for the previous one's
  /// socket. Serially this took the sum of the delays; concurrently it takes the longest.
  func testControllersAreNotifiedConcurrently() async throws {
    let controllerCount = 6
    let delay = Duration.milliseconds(300)

    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let event = makeEvent()
    let controllers = (0..<controllerCount).map { _ in SlowController(delay: delay) }
    let manager = await device.subscriptionManager
    let subscriptionManager = try XCTUnwrap(manager)
    for controller in controllers {
      try await subscriptionManager.addSubscription(subscription(for: event), for: controller)
    }
    let endpoint = MockEndpoint(controllers: controllers)
    try await device.add(endpoint: endpoint)

    let subCount = await subscriptionManager.subscribers(to: Self.emitter).count
    XCTAssertEqual(subCount, controllerCount, "subscriptions were not registered")
    let epCount = await device.endpoints.count
    XCTAssertEqual(epCount, 1, "endpoint was not registered on the device")
    let smState = await subscriptionManager.state
    XCTAssertEqual(smState, .normal, "subscription manager not in normal state")

    let started = ContinuousClock.now
    try await device.notifySubscribers(event, parameters: Data())
    let elapsed = ContinuousClock.now - started

    for controller in controllers {
      let count = await controller.sendCount
      XCTAssertEqual(count, 1, "a controller was not notified")
    }

    // Serial delivery would be controllerCount * delay; allow generous slack for a
    // loaded machine while still failing well below the serial figure.
    let serial = delay * controllerCount
    XCTAssertLessThan(
      elapsed,
      serial / 2,
      "fan-out took \(elapsed); serial delivery would be \(serial)"
    )

    // Each controller should have been entered before the first one's send completed.
    let entries = await withTaskGroup(of: ContinuousClock.Instant?.self) { group in
      for controller in controllers {
        group.addTask { await controller.enteredAt }
      }
      var result = [ContinuousClock.Instant]()
      for await entry in group { if let entry { result.append(entry) } }
      return result
    }
    XCTAssertEqual(entries.count, controllerCount)
    if let first = entries.min(), let last = entries.max() {
      XCTAssertLessThan(last - first, delay, "controllers were entered \(last - first) apart")
    }
  }

  /// A controller that can queue is never waited on: its stalled peer holds up neither the
  /// setter raising the event nor the other controllers, sent at once or from a scope.
  func testAStalledPeerIsQueuedToNotWaitedOn() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let event = makeEvent()
    let stalled = StalledQueuedController()
    let other = SlowController(delay: .zero)
    let manager = await device.subscriptionManager
    let subscriptionManager = try XCTUnwrap(manager)
    for controller in [stalled, other] as [OcaController] {
      try await subscriptionManager.addSubscription(subscription(for: event), for: controller)
    }
    try await device.add(endpoint: MockEndpoint(controllers: [stalled, other]))

    let started = ContinuousClock.now
    try await device.notifySubscribers(event, parameters: Data())
    await device.withCoalescedNotifications {
      try? await device.notifySubscribers(event, parameters: Data())
      try? await device.notifySubscribers(event, parameters: Data())
    }
    XCTAssertLessThan(ContinuousClock.now - started, .seconds(1), "a stalled peer was waited on")
    let queued = await stalled.queued
    let sent = await stalled.sent
    XCTAssertEqual(queued, 2, "the direct send and the scope's batch")
    XCTAssertEqual(sent, 0)
    let others = await other.sendCount
    XCTAssertEqual(others, 2)
  }
}
