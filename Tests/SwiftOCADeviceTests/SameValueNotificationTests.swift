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

#if NonEmbeddedBuild
import Foundation
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

private final class Counter: @unchecked Sendable {
  private var _value = 0
  private let lock = NSLock()
  var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
  func increment() { lock.lock(); _value += 1; lock.unlock() }
}

/// A device property set to the value it already has notifies no one; only a
/// cadenced property (the level sensor's reading) keeps notifying on request.
final class SameValueNotificationTests: XCTestCase {
  private struct Harness {
    let device: OcaDevice
    let connection: OcaLocalConnection
    let endpointTask: Task<(), Never>

    func tearDown() async {
      try? await connection.disconnect()
      endpointTask.cancel()
    }
  }

  private static let labelID = OcaPropertyID("2.3")
  private static let gainID = OcaPropertyID("4.1")

  func testSameValueSetSendsNoNotificationOverOcp1() async throws {
    try await assertSameValueSetSendsNoNotification(controlProtocol: .ocp1, oNo: 0x0001_0500)
  }

  func testSameValueSetSendsNoNotificationOverOcp2() async throws {
    try await assertSameValueSetSendsNoNotification(controlProtocol: .ocp2, oNo: 0x0001_0501)
  }

  private func assertSameValueSetSendsNoNotification(
    controlProtocol: OcaControlProtocol,
    oNo: OcaONo
  ) async throws {
    let harness = try await makeHarness(controlProtocol: controlProtocol)
    defer { Task { await harness.tearDown() } }

    let deviceGain = try await SwiftOCADevice.OcaGain(
      objectNumber: oNo,
      role: "Gain",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    let clientGain: SwiftOCA.OcaGain = try await harness.connection.resolve(
      object: OcaObjectIdentification(
        oNo: oNo,
        classIdentification: SwiftOCA.OcaGain.classIdentification
      )
    )
    let notifications = try await countNotifications(harness, oNo: oNo)

    // Sets from a controller: each still succeeds, but changes nothing
    let gain = await { @OcaDevice in deviceGain.gain }()
    try await clientGain.$gain._setValue(clientGain, gain)
    try await clientGain.$label._setValue(clientGain, "")
    // and from the device itself
    await { @OcaDevice in deviceGain.label = "" }()
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(notifications.value, 0, "a same-value set notified the controller")

    try await clientGain.$gain._setValue(
      clientGain,
      OcaBoundedPropertyValue<OcaDB>(value: -6.0, in: gain.range)
    )
    let notified = await wait { notifications.value >= 1 }
    XCTAssertTrue(notified, "a changed value did not notify the controller")
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(notifications.value, 1, "a changed value notified more than once")
  }

  func testPropertyChangesSignalsCurrentValueThenOnlyChanges() async throws {
    let harness = try await makeHarness(controlProtocol: .ocp1)
    defer { Task { await harness.tearDown() } }

    let deviceGain = try await SwiftOCADevice.OcaGain(
      objectNumber: 0x0001_0502,
      role: "Gain",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    let (labelChanges, task) = await countChanges(of: deviceGain, propertyID: Self.labelID)
    defer { task.cancel() }

    let initial = await wait { labelChanges.value == 1 }
    XCTAssertTrue(initial, "the current value was not signalled on following")

    await { @OcaDevice in deviceGain.label = "" }()
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(labelChanges.value, 1, "a same-value set was signalled")

    await { @OcaDevice in deviceGain.label = "changed" }()
    let changed = await wait { labelChanges.value == 2 }
    XCTAssertTrue(changed, "a changed value was not signalled")
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(labelChanges.value, 2)
  }

  /// Event forwarding and dataset restore follow the same rule as a Set.
  func testSameValueFromEventOrJsonIsNotSignalled() async throws {
    let harness = try await makeHarness(controlProtocol: .ocp1)
    defer { Task { await harness.tearDown() } }

    let deviceGain = try await SwiftOCADevice.OcaGain(
      objectNumber: 0x0001_0503,
      role: "Gain",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    await { @OcaDevice in deviceGain.label = "label" }()
    let (labelChanges, labelTask) = await countChanges(of: deviceGain, propertyID: Self.labelID)
    let (gainChanges, gainTask) = await countChanges(of: deviceGain, propertyID: Self.gainID)
    defer { labelTask.cancel(); gainTask.cancel() }
    let initial = await wait { labelChanges.value == 1 && gainChanges.value == 1 }
    XCTAssertTrue(initial)

    let eventData = try OcaAnyPropertyChangedEventData(
      propertyID: Self.labelID,
      propertyValue: Ocp1Encoder().encode("label"),
      changeType: .currentChanged
    )
    try await deviceGain.forward(
      event: OcaEvent(emitterONo: deviceGain.objectNumber, eventID: OcaPropertyChangedEventID),
      eventData: eventData
    )

    let jsonObject = await deviceGain.jsonObject
    try await deviceGain.deserialize(jsonObject: jsonObject)

    try await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(labelChanges.value, 1, "a same-value event or restore was signalled")
    XCTAssertEqual(gainChanges.value, 1, "a same-value restore was signalled")
  }

  /// A level sensor's reading sits outside the property wrapper and keeps its
  /// own rule: an equal reading notifies only when asked to.
  func testLevelSensorStillNotifiesAnEqualReadingOnRequest() async throws {
    let harness = try await makeHarness(controlProtocol: .ocp1)
    defer { Task { await harness.tearDown() } }

    let oNo: OcaONo = 0x0001_0504
    let sensor = try await SwiftOCADevice.OcaLevelSensor(
      objectNumber: oNo,
      role: "Meter",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    let notifications = try await countNotifications(harness, oNo: oNo)

    try await sensor.update(reading: -12.0)
    let first = await wait { notifications.value == 1 }
    XCTAssertTrue(first)

    try await sensor.update(reading: -12.0, alwaysNotifySubscribers: true)
    try await sensor.update(reading: -12.0, alwaysNotifySubscribers: true)
    let cadenced = await wait { notifications.value == 3 }
    XCTAssertTrue(cadenced, "an equal meter reading did not notify")
  }

  func testAChangeOfBoundsAloneIsSignalled() async throws {
    let harness = try await makeHarness(controlProtocol: .ocp1)
    defer { Task { await harness.tearDown() } }

    let sensor = try await SwiftOCADevice.OcaFloat32Sensor(
      OcaBoundedPropertyValue(value: 0.0, in: -1.0...1.0),
      objectNumber: 0x0001_0505,
      deviceDelegate: harness.device
    )
    let (changes, task) = await countChanges(of: sensor, propertyID: OcaPropertyID("5.1"))
    defer { task.cancel() }
    let initial = await wait { changes.value == 1 }
    XCTAssertTrue(initial)

    let half = OcaBoundedPropertyValue<OcaFloat32>(value: 0.5, in: -1.0...1.0)
    await { @OcaDevice in sensor.reading = half }()
    let changed = await wait { changes.value == 2 }
    XCTAssertTrue(changed)
    await { @OcaDevice in sensor.reading = half }()
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(changes.value, 2, "an equal bounded value was signalled")

    // the bounds are part of a bounded value
    await { @OcaDevice in sensor.reading = OcaBoundedPropertyValue(value: 0.5, in: -2.0...1.0) }()
    let rebounded = await wait { changes.value == 3 }
    XCTAssertTrue(rebounded, "a change of bounds alone was not signalled")
  }

  // MARK: - helpers

  private func countNotifications(_ harness: Harness, oNo: OcaONo) async throws -> Counter {
    let counter = Counter()
    let event = OcaEvent(emitterONo: oNo, eventID: OcaPropertyChangedEventID)
    _ = try await harness.connection.addSubscription(label: "count", event: event) { _, _ in
      counter.increment()
    }
    let subscribed = await wait { await harness.connection.isSubscribed(event: event) }
    XCTAssertTrue(subscribed)
    // let the device-side AddSubscription land
    try await Task.sleep(for: .milliseconds(300))
    return counter
  }

  private func countChanges(
    of object: SwiftOCADevice.OcaRoot,
    propertyID: OcaPropertyID
  ) async -> (Counter, Task<(), Never>) {
    let counter = Counter()
    let changes = await object.propertyChanges
    let task = Task {
      do {
        for try await id in changes where id == propertyID {
          counter.increment()
        }
      } catch {}
    }
    return (counter, task)
  }

  private func makeHarness(controlProtocol: OcaControlProtocol) async throws -> Harness {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(
      device: device,
      controlProtocol: controlProtocol
    )
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(
      endpoint,
      options: OcaConnectionOptions(controlProtocol: controlProtocol)
    )
    try await connection.connect()
    return Harness(device: device, connection: connection, endpointTask: endpointTask)
  }

  private func wait(
    timeout: Duration = .seconds(5),
    until condition: @Sendable () async -> Bool
  ) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if await condition() { return true }
      try? await Task.sleep(for: .milliseconds(25))
    }
    return await condition()
  }
}
#endif
