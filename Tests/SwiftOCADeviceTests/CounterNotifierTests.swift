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

/// The CounterUpdate events the device sends from one notifier, in the order it sends
/// them: the device tells its event delegate of each before fanning it out, where a
/// client's dispatch of notifications keeps no order.
private final class ReceivedUpdates: OcaDeviceEventDelegate, @unchecked Sendable {
  private var _events = [OcaCounterUpdateEventData]()
  private let lock = NSLock()
  private let emitterONo: OcaONo

  init(from emitterONo: OcaONo) {
    self.emitterONo = emitterONo
  }

  var events: [OcaCounterUpdateEventData] { lock.withLock { _events } }

  func onEvent(_ event: OcaEvent, parameters: OcaEventParameters) async {
    guard event.emitterONo == emitterONo,
          event.eventID == SwiftOCA.OcaCounterNotifier.counterUpdateEventID,
          let data = try? parameters.encoded(as: .ocp1),
          let decoded = try? Ocp1Decoder().decode(OcaCounterUpdateEventData.self, from: data)
    else { return }
    lock.withLock { _events.append(decoded) }
  }

  func onControllerExpiry(_ controller: OcaController) async {}
}

private final class PropertyIDs: @unchecked Sendable {
  private var _ids = [OcaPropertyID]()
  private let lock = NSLock()

  var ids: [OcaPropertyID] { lock.lock(); defer { lock.unlock() }; return _ids }

  func append(_ id: OcaPropertyID) {
    lock.lock(); _ids.append(id); lock.unlock()
  }
}

/// An interface subclass with registration of its own.
private final class RegisteringInterface: SwiftOCADevice.OcaNetworkInterface {
  private(set) var didRegisterCount = 0

  override func didRegister() async {
    didRegisterCount += 1
    await super.didRegister()
  }
}

/// A notifier that counts the times owners wake it, which the library has no need to.
private final class CountingNotifier: SwiftOCADevice.OcaCounterNotifier {
  private(set) var wakeCount = 0

  override func counterSetsDidChange(
    for owner: any OcaCounterSetRepresentable,
    counterSets: [OcaCounterSet],
    resetting resets: Set<OcaCounterKey>
  ) {
    wakeCount += 1
    super.counterSetsDidChange(for: owner, counterSets: counterSets, resetting: resets)
  }
}

/// What the tests need to know of a notifier's progress, from its state.
extension SwiftOCADevice.OcaCounterNotifier {
  /// Whether the notifier has read `owner`'s counter sets as they are now: owners tell
  /// their notifiers, which read at once, when nothing is pending.
  func hasRead(_ owner: any OcaCounterSetRepresentable) -> Bool {
    !owner.counterSetChanges.isPending
  }

  /// Returns once the updates raised so far have been sent.
  func updatesDidSend() async {
    while let sending { await sending.value }
  }

  /// How many updates are waiting for the one being sent.
  var pendingUpdateCount: Int { pendingUpdates.count }

  /// How many counters the notifier is watching.
  var observedCounterCount: Int { observed.values.reduce(0) { $0 + $1.count } }
}

/// CounterUpdate (3.1) from a notifier attached to a network interface's counters.
final class CounterNotifierTests: XCTestCase {
  private struct Harness {
    let device: OcaDevice
    let connection: OcaLocalConnection
    let endpointTask: Task<(), Never>
    let deviceInterface: SwiftOCADevice.OcaNetworkInterface
    let deviceNotifier: CountingNotifier
    let interface: SwiftOCA.OcaNetworkInterface
    let notifier: SwiftOCA.OcaCounterNotifier
    let received: ReceivedUpdates

    func tearDown() async {
      try? await connection.disconnect()
      endpointTask.cancel()
    }

    func set(filterParameters: OcaCounterNotifierFilterParameters) async throws {
      try await notifier.$filterParameters._setValue(notifier, filterParameters)
    }

    func set(counter id: OcaID16, value: OcaUint64) async throws {
      try await { @OcaDevice in try deviceInterface.set(counter: id, value: value) }()
    }

    /// Sets a counter, then waits for the notifier to have sent what that calls for.
    func step(counter id: OcaID16, value: OcaUint64) async throws {
      try await set(counter: id, value: value)
      await settle()
    }

    func attach(_ counterID: OcaID16) async throws {
      try await interface.attachCounterNotifier(counterID: counterID, oNo: CounterNotifierTests.notifierONo)
      await settle()
    }

    func detach(_ counterID: OcaID16) async throws {
      try await interface.detachCounterNotifier(counterID: counterID, oNo: CounterNotifierTests.notifierONo)
      await settle()
    }

    /// Waits for the notifier to have read `owners`' counter sets as they are now, as their
    /// changes signal it to, and to have sent what that calls for.
    func settle(_ owners: [any OcaCounterSetRepresentable]? = nil, notifier: SwiftOCADevice.OcaCounterNotifier? = nil) async {
      let owners = owners ?? [deviceInterface]
      let notifier = notifier ?? deviceNotifier
      for owner in owners {
        let read = await waitUntil { await notifier.hasRead(owner) }
        XCTAssertTrue(read, "the notifier did not read \(owner)'s counter sets")
      }
      await notifier.updatesDidSend()
    }

    /// What the notifier last sent, once the changes made so far have reached it.
    func lastUpdate() async throws -> OcaList<OcaCounterUpdate> {
      await settle()
      return try await notifier.getLastUpdate()
    }

    /// Waits for `count` events in all, then for any stragglers.
    func events(_ count: Int) async -> [OcaCounterUpdateEventData] {
      await settle()
      _ = await waitUntil { received.events.count >= count }
      return received.events
    }
  }

  private static let interfaceONo: OcaONo = 0x0001_0700
  private static let notifierONo: OcaONo = 0x0001_0701
  private static let counterSetID = OcaBlob([0x01, 0x02])

  func testCountDeltaNotifiesEveryNCounts() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 3))
    try await h.attach(1)

    for value in OcaUint64(1)...7 {
      try await h.step(counter: 1, value: value)
    }
    let events = await h.events(2)
    XCTAssertEqual(events, [event(1, 3), event(1, 6)])
    let lastUpdate = try await h.lastUpdate()
    XCTAssertEqual(lastUpdate, event(1, 6).updates)
  }

  func testUpdatesAreSentInTheOrderTheCountersChanged() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 1))
    try await h.attach(1)

    for value in OcaUint64(1)...50 {
      try await h.step(counter: 1, value: value)
    }
    let events = await h.events(50)
    XCTAssertEqual(events, (OcaUint64(1)...50).map { event(1, $0) })
  }

  func testRapidChangesAreSentInOrderEndingWithTheLatest() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 1))
    try await h.attach(1)

    // changes made faster than they are sent may be sent together, never out of order
    for value in OcaUint64(1)...200 {
      try await h.set(counter: 1, value: value)
    }
    await h.settle()
    let latest = event(1, 200)
    _ = await waitUntil { h.received.events.last == latest }
    let values = h.received.events.flatMap(\.updates).map(\.value)
    XCTAssertEqual(values.last, 200)
    XCTAssertEqual(values, values.sorted())
    XCTAssertEqual(Set(values).count, values.count, "a value was sent twice")
  }

  func testThresholdGatesUpdates() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(
      threshold: 10,
      operator: .greaterThanOrEqual,
      countDelta: 1
    ))
    try await h.attach(1)

    try await h.step(counter: 1, value: 5)
    let below = try await h.lastUpdate()
    XCTAssertEqual(below, [], "a value below the threshold notified")

    try await h.step(counter: 1, value: 12)
    let events = await h.events(1)
    XCTAssertEqual(events, [event(1, 12)])
  }

  func testACountDeltaOfZeroSendsNoChange() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 0))
    try await h.attach(1)

    for value in OcaUint64(1)...5 {
      try await h.step(counter: 1, value: value)
    }
    let lastUpdate = try await h.lastUpdate()
    XCTAssertEqual(lastUpdate, [])
  }

  func testResetNotifiesWhateverTheFilters() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(threshold: 100, operator: .greaterThan, countDelta: 1))
    try await h.attach(1)
    try await h.attach(2)

    // below the threshold: a change on its own notifies nothing
    try await h.step(counter: 1, value: 4)
    let before = try await h.lastUpdate()
    XCTAssertEqual(before, [])

    try await h.interface.resetCounters()
    let events = await h.events(1)
    XCTAssertEqual(events, [OcaCounterUpdateEventData(updates: [
      update(1, 0),
      update(2, 0),
    ])])
  }

  func testAResetIsNotifiedOnceThoughItChangesTheValue() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 1))
    try await h.attach(1)
    try await h.step(counter: 1, value: 5)

    try await h.interface.resetCounters()
    // read before the next change, which would otherwise be read with it
    await h.settle()
    try await h.step(counter: 1, value: 1)
    let events = await h.events(3)
    XCTAssertEqual(events, [event(1, 5), event(1, 0), event(1, 1)])
  }

  func testDetachedCounterDoesNotNotify() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 1))
    try await h.attach(1)
    try await h.attach(2)
    try await h.detach(1)

    try await h.step(counter: 1, value: 1)
    try await h.step(counter: 2, value: 1)
    let events = await h.events(1)
    XCTAssertEqual(events, [event(2, 1)])
  }

  func testAChangeWakesOnlyTheNotifiersConcerned() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 1))
    try await h.attach(1)
    // a second notifier no counter set names, and one the interface named once
    let (idle, once) = try await { @OcaDevice in
      let idle = try await CountingNotifier(
        objectNumber: 0x0001_0702, deviceDelegate: h.device, addToRootBlock: false
      )
      let once = try await CountingNotifier(
        objectNumber: 0x0001_0703, deviceDelegate: h.device, addToRootBlock: false
      )
      try h.deviceInterface.counterSet.attach(notifier: once.objectNumber, to: 2)
      return (idle, once)
    }()
    await h.settle(notifier: once)
    let (idleWakes, onceWakes) = await { @OcaDevice in (idle.wakeCount, once.wakeCount) }()

    // detached: told once more, so that it forgets the counter, and not again after
    try await { @OcaDevice in try h.deviceInterface.counterSet.detach(notifier: once.objectNumber, from: 2) }()
    await h.settle(notifier: once)
    for value in OcaUint64(1)...3 {
      try await h.step(counter: 1, value: value)
    }
    await h.settle(notifier: once)
    let events = await h.events(3)
    XCTAssertEqual(events.count, 3)
    let (idleAfter, onceAfter, onceObserved) = await { @OcaDevice in
      (idle.wakeCount, once.wakeCount, once.observedCounterCount)
    }()
    XCTAssertEqual(idleAfter, idleWakes, "a notifier no set names was woken")
    XCTAssertEqual(onceAfter, onceWakes + 1, "a detached notifier was woken again")
    XCTAssertEqual(onceObserved, 0)
  }

  func testCounterSetsOfTwoOwnersAreTrackedApart() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 1))
    // two interfaces left with their default counter sets
    let (first, second) = try await { @OcaDevice in
      var interfaces = [SwiftOCADevice.OcaNetworkInterface]()
      for oNo: OcaONo in [0x0001_0710, 0x0001_0711] {
        let interface = try await SwiftOCADevice.OcaNetworkInterface(
          objectNumber: oNo,
          deviceDelegate: h.device,
          addToRootBlock: false
        )
        interface.counterSet.counter = [
          OcaCounter(id: 1, value: 0, initialValue: 0, role: "one", notifiers: [Self.notifierONo]),
        ]
        interfaces.append(interface)
      }
      return (interfaces[0], interfaces[1])
    }()
    let (firstID, secondID) = await { @OcaDevice in (first.counterSet.id, second.counterSet.id) }()
    XCTAssertNotEqual(firstID, secondID)
    XCTAssertEqual(
      firstID,
      try OcaPropertyCounterSetID(ownerONo: 0x0001_0710, propertyID: OcaPropertyID("2.13")).blob
    )
    XCTAssertEqual(try OcaPropertyCounterSetID(blob: firstID).ownerONo, 0x0001_0710)
    await h.settle([first, second])

    for owner in [first, second] {
      try await { @OcaDevice in try owner.set(counter: 1, value: 1) }()
      await h.settle([owner])
    }
    // detaching one owner's counter leaves the other's attached
    try await { @OcaDevice in try first.counterSet.detach(notifier: Self.notifierONo, from: 1) }()
    await h.settle([first])
    for owner in [first, second] {
      try await { @OcaDevice in try owner.set(counter: 1, value: 2) }()
      await h.settle([owner])
    }
    let updates = OcaList([firstID, secondID, secondID]).enumerated().map { index, id in
      OcaCounterUpdate(counterSetID: id, counterID: 1, value: index == 2 ? 2 : 1)
    }
    let events = await h.events(3)
    XCTAssertEqual(events, updates.map { OcaCounterUpdateEventData(updates: [$0]) })
  }

  func testACounterSetAssignedDirectlyReachesItsNotifiers() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 1))
    let notifier = h.deviceNotifier
    func assign(value: OcaUint64, notifiers: [OcaONo]) async {
      let interface = h.deviceInterface
      // as a dataset restore or the device itself would, not through the counter helpers
      await { @OcaDevice in
        interface.counterSet = OcaCounterSet(id: Self.counterSetID, counter: [
          OcaCounter(id: 1, value: value, initialValue: 0, role: "one", notifiers: notifiers),
        ])
      }()
    }

    await assign(value: 5, notifiers: [Self.notifierONo])
    await h.settle()
    await assign(value: 6, notifiers: [Self.notifierONo])
    let events = await h.events(1)
    XCTAssertEqual(events, [event(1, 6)])

    // detached: a periodic update no longer sends it
    await assign(value: 7, notifiers: [])
    await h.settle()
    await { @OcaDevice in notifier.sendPeriodicUpdate() }()
    await h.settle()
    let lastUpdate = try await h.notifier.getLastUpdate()
    XCTAssertEqual(lastUpdate, event(1, 6).updates)
  }

  func testAStalledControllerHoldsUpOnlyItsOwnNotifier() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 1))
    try await h.attach(1)

    // a second notifier whose only subscriber never finishes a send
    let stalled = StalledController()
    let otherONo: OcaONo = 0x0001_0702
    let other = try await { @OcaDevice in
      let other = try await SwiftOCADevice.OcaCounterNotifier(
        objectNumber: otherONo,
        deviceDelegate: h.device,
        addToRootBlock: false
      )
      other.filterParameters = OcaCounterNotifierFilterParameters(
        threshold: 0, operator: .none, period: 0, countDelta: 1
      )
      try h.deviceInterface.counterSet.attach(notifier: otherONo, to: 2)
      return other
    }()
    defer { Task { await stalled.release() } }
    let manager = await h.device.subscriptionManager
    let subscriptionManager = try XCTUnwrap(manager)
    try await subscriptionManager.addSubscription(.subscription2(OcaSubscription2(
      event: OcaEvent(emitterONo: otherONo, eventID: SwiftOCA.OcaCounterNotifier.counterUpdateEventID),
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )), for: stalled)
    await h.settle(notifier: other)

    for value in OcaUint64(1)...100 {
      try await h.set(counter: 2, value: value)
      try await h.step(counter: 1, value: value)
    }
    let events = await h.events(100)
    XCTAssertEqual(events, (OcaUint64(1)...100).map { event(1, $0) })
    let entered = await waitUntil { await stalled.sendCount == 1 }
    XCTAssertTrue(entered, "the stalled controller was not sent its first update")
    let sendCount = await stalled.sendCount
    XCTAssertEqual(sendCount, 1, "the stalled controller was sent more than its first update")
    // what waits for the stalled send is the newest value of each counter, no more
    let interface = h.deviceInterface
    let bounded = await waitUntil {
      let read = await other.hasRead(interface)
      let pending = await other.pendingUpdateCount
      return read && pending == 1
    }
    XCTAssertTrue(bounded, "more than the newest value waits for the stalled send")
  }

  func testAnOwnerNoLongerRegisteredIsForgotten() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.attach(1)
    try await h.step(counter: 1, value: 1)
    let notifier = h.deviceNotifier
    let owner = try await { @OcaDevice in
      let owner = try await SwiftOCADevice.OcaNetworkInterface(
        objectNumber: 0x0001_0720,
        deviceDelegate: h.device,
        addToRootBlock: false
      )
      owner.counterSet.counter = [
        OcaCounter(id: 1, value: 3, initialValue: 0, role: "one", notifiers: [Self.notifierONo]),
      ]
      return owner
    }()
    await h.settle([owner])
    let ownerID = await { @OcaDevice in owner.counterSet.id }()
    await { @OcaDevice in notifier.sendPeriodicUpdate() }()
    await h.settle()
    let sent = try await h.notifier.getLastUpdate()
    XCTAssertEqual(sent, [update(1, 1), OcaCounterUpdate(counterSetID: ownerID, counterID: 1, value: 3)])

    // deregistered, though still referenced here: its counters are forgotten, and changing
    // its sets does not bring them back
    try await h.device.deregister(object: owner)
    await h.settle([owner])
    try await { @OcaDevice in try owner.set(counter: 1, value: 4) }()
    await { @OcaDevice in try? owner.reset(&owner.counterSet, counter: 1) }()
    await h.settle([owner])
    await { @OcaDevice in notifier.sendPeriodicUpdate() }()
    await h.settle()
    let afterwards = try await h.notifier.getLastUpdate()
    XCTAssertEqual(afterwards, [update(1, 1)], "the notifier still sends a deregistered owner's counters")
    withExtendedLifetime(owner) {}
  }

  func testACounterAttachedResetAndDetachedInOneTurnIsNotKept() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.attach(2)
    let interface = h.deviceInterface
    let notifier = h.deviceNotifier
    try await { @OcaDevice in
      try interface.counterSet.attach(notifier: Self.notifierONo, to: 1)
      try interface.reset(&interface.counterSet, counter: 1)
      try interface.counterSet.detach(notifier: Self.notifierONo, from: 1)
    }()
    await h.settle()
    await { @OcaDevice in notifier.sendPeriodicUpdate() }()
    await h.settle()
    let oneTurn = try await h.notifier.getLastUpdate()
    XCTAssertEqual(oneTurn, [update(2, 0)], "a periodic update sent a detached counter")

    // and detached once the notifier has read it attached, leaving the sets naming it
    // nowhere: it must hear of that all the same
    let marker = try await { @OcaDevice in
      let marker = try await SwiftOCADevice.OcaNetworkInterface(
        objectNumber: 0x0001_0730,
        deviceDelegate: h.device,
        addToRootBlock: false
      )
      marker.counterSet.counter = [
        OcaCounter(id: 1, value: 5, initialValue: 0, role: "one", notifiers: [Self.notifierONo]),
      ]
      return marker
    }()
    await h.settle([marker])
    let markerID = await { @OcaDevice in marker.counterSet.id }()
    try await h.detach(2)
    try await h.attach(1)
    try await h.detach(1)
    await { @OcaDevice in notifier.sendPeriodicUpdate() }()
    await h.settle()
    let later = try await h.notifier.getLastUpdate()
    XCTAssertEqual(
      later,
      [OcaCounterUpdate(counterSetID: markerID, counterID: 1, value: 5)],
      "a periodic update sent a detached counter"
    )
  }

  func testANotifierCreatedAfterItsCountersNameItFindsThem() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    let laterONo: OcaONo = 0x0001_0703
    let interface = h.deviceInterface
    try await { @OcaDevice in try interface.counterSet.attach(notifier: laterONo, to: 1) }()
    try await h.set(counter: 1, value: 9)

    let later = try await { @OcaDevice in
      try await SwiftOCADevice.OcaCounterNotifier(
        objectNumber: laterONo,
        deviceDelegate: h.device,
        addToRootBlock: false
      )
    }()
    await h.settle(notifier: later)
    await { @OcaDevice in later.sendPeriodicUpdate() }()
    await h.settle(notifier: later)
    let lastUpdate = try await later.getLastUpdate(from: TestController())
    XCTAssertEqual(lastUpdate, [update(1, 9)])
  }

  func testChangesMadeTogetherAreReadTogether() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 1))
    try await h.attach(1)
    let notifier = h.deviceNotifier
    let interface = h.deviceInterface
    let before = await { @OcaDevice in notifier.wakeCount }()

    // in one turn, as a poller updating its counters would
    try await { @OcaDevice in
      for value in OcaUint64(1)...200 {
        try interface.set(counter: 1, value: value)
        try interface.set(counter: 2, value: value)
      }
    }()
    await h.settle()
    let wakes = await { @OcaDevice in notifier.wakeCount }() - before
    XCTAssertEqual(wakes, 1, "400 changes made together woke the notifier \(wakes) times")
    let latest = event(1, 200)
    let sent = await waitUntil { h.received.events.last == latest }
    XCTAssertTrue(sent, "the latest value was not sent")
  }

  func testPeriodSendsTheAttachedCounters() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.attach(1)
    try await h.attach(2)
    try await h.step(counter: 1, value: 7)
    let before = try await h.lastUpdate()
    XCTAssertEqual(before, [])

    // counter 2 stays at 0, below the threshold
    try await h.set(filterParameters: filter(threshold: 5, operator: .greaterThan, period: 0.1))
    let events = await h.events(2)
    XCTAssertGreaterThanOrEqual(events.count, 2)
    XCTAssertTrue(events.allSatisfy { $0 == event(1, 7) })

    // once the timer has stopped and what it raised is sent, nothing more comes
    try await h.set(filterParameters: filter())
    let notifier = h.deviceNotifier
    let stopped = await waitUntil { await notifier.periodTimer == nil }
    XCTAssertTrue(stopped, "the timer was not stopped")
    await h.settle()
    let count = await stableCount { h.received.events.count }
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(h.received.events.count, count, "periodic updates continued with no period")
  }

  func testPeriodFollowsALocalSet() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.attach(1)
    try await h.step(counter: 1, value: 3)

    // as a dataset restore or the device itself would set it, not SetFilterParameters
    let parameters = filter(period: 0.1)
    await { @OcaDevice in h.deviceNotifier.filterParameters = parameters }()
    let events = await h.events(1)
    XCTAssertEqual(events.first, event(1, 3))
  }

  func testAPeriodicUpdateIsWhatCountDeltaMeasuresFrom() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.attach(1)
    try await h.step(counter: 1, value: 3)
    try await h.set(filterParameters: filter(countDelta: 5))

    // a Period's tick, without waiting for one
    let notifier = h.deviceNotifier
    await { @OcaDevice in notifier.sendPeriodicUpdate() }()
    let periodic = try await h.lastUpdate()
    XCTAssertEqual(periodic, event(1, 3).updates)

    // 3 was notified, so 7 is 4 counts on and 8 is 5
    try await h.step(counter: 1, value: 7)
    let notYet = try await h.lastUpdate()
    XCTAssertEqual(notYet, event(1, 3).updates)
    try await h.step(counter: 1, value: 8)
    let lastUpdate = try await h.lastUpdate()
    XCTAssertEqual(lastUpdate, event(1, 8).updates)
  }

  func testAPeriodOutOfRangeIsRefused() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    for period: OcaTimeInterval in [1e11, 0.05, 0.001, -1, .nan, .infinity] {
      do {
        try await h.set(filterParameters: filter(period: period))
        XCTFail("accepted a Period of \(period)")
      } catch let Ocp1Error.status(status) {
        XCTAssertEqual(status, .parameterOutOfRange)
      }
    }
    try await h.set(filterParameters: filter(period: 0))
    try await h.set(filterParameters: filter(period: 3600))
  }

  func testAPeriodIsCheckedOverOCP2AfterTheLock() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    let controller = TestController()
    func set(period: OcaTimeInterval) async throws -> OcaStatus {
      nonisolated(unsafe) let parameters: [String: Any] = try [
        "FilterParameters": XCTUnwrap(Ocp2Encoder().encodeValue(filter(period: period))),
      ]
      return await h.device.send(
        OcaMethodID("3.3"), to: Self.notifierONo, ocp2Parameters: parameters, from: controller
      ).status
    }
    let outOfRange = try await set(period: 1e11)
    XCTAssertEqual(outOfRange, .parameterOutOfRange)
    let accepted = try await set(period: 60)
    XCTAssertEqual(accepted, .ok)
    let period = await h.deviceNotifier.filterParameters?.period
    XCTAssertEqual(period, 60)

    // write-locked by another controller: Locked, whatever the Period
    let locked = await h.deviceNotifier.setLockState(to: .lockNoWrite, controller: TestController())
    XCTAssertTrue(locked)
    let refused = try await set(period: 1e11)
    XCTAssertEqual(refused, .locked)
  }

  func testEveryOperatorGatesPeriodicUpdates() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.attach(1)
    try await h.attach(2)
    try await h.set(counter: 1, value: 5)
    try await h.set(counter: 2, value: 6)
    await h.settle()
    let notifier = h.deviceNotifier
    // threshold 5: counter 1 holds 5, counter 2 holds 6
    let expected: [(OcaRelationalOperator, [OcaCounterUpdate])] = [
      (.none, [update(1, 5), update(2, 6)]),
      (.equality, [update(1, 5)]),
      (.inequality, [update(2, 6)]),
      (.greaterThan, [update(2, 6)]),
      (.greaterThanOrEqual, [update(1, 5), update(2, 6)]),
      (.lessThan, []),
      (.lessThanOrEqual, [update(1, 5)]),
    ]
    for (op, updates) in expected {
      try await h.set(filterParameters: filter(threshold: 5, operator: op))
      let before = h.received.events.count
      await { @OcaDevice in notifier.sendPeriodicUpdate() }()
      await notifier.updatesDidSend()
      let sent = h.received.events.dropFirst(before).flatMap(\.updates)
      XCTAssertEqual(sent, updates, "\(op)")
    }
  }

  func testACounterSetAgentsCountersNotify() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 1))
    let agent = try await { @OcaDevice in
      let agent = try await SwiftOCADevice.OcaCounterSetAgent(deviceDelegate: h.device, addToRootBlock: false)
      agent.counterSet.counter = [
        OcaCounter(id: 1, value: 0, initialValue: 0, role: "one", notifiers: []),
        OcaCounter(id: 2, value: 5, initialValue: 0, role: "two", notifiers: []),
      ]
      return agent
    }()
    let agentID = await agent.counterSet.id
    let controller = TestController()
    try await agent.attachCounterNotifier(id: 1, oNo: Self.notifierONo, from: controller)
    try await agent.attachCounterNotifier(id: 2, oNo: Self.notifierONo, from: controller)
    await h.settle([agent])
    try await { @OcaDevice in try agent.increment(counter: 1) }()
    await h.settle([agent])
    // only the counter reset notifies, though both are attached
    try await agent.resetCounter(id: 2, from: controller)
    do {
      try await agent.resetCounter(id: 3, from: controller)
      XCTFail("reset a counter the set does not have")
    } catch Ocp1Error.status(.parameterOutOfRange) {}

    await h.settle([agent])
    let events = await h.events(2)
    XCTAssertEqual(events, [
      OcaCounterUpdateEventData(updates: [OcaCounterUpdate(counterSetID: agentID, counterID: 1, value: 1)]),
      OcaCounterUpdateEventData(updates: [OcaCounterUpdate(counterSetID: agentID, counterID: 2, value: 0)]),
    ])
  }

  func testACounterChangeRaisesNoPropertyChanged() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    let changed = PropertyIDs()
    let event = OcaEvent(emitterONo: Self.interfaceONo, eventID: OcaPropertyChangedEventID)
    _ = try await h.connection.addSubscription(label: "changes", event: event) { _, data in
      try changed.append(Ocp1Decoder().decode(OcaPropertyID.self, from: data))
    }

    try await h.attach(1)
    try await h.step(counter: 1, value: 5)
    let interface = h.deviceInterface
    await { @OcaDevice in interface.counterSet.reset() }()
    // a property that is not private, whose change follows the counters'
    await { @OcaDevice in interface.label = "fence" }()
    let fenced = await waitUntil { changed.ids.contains(OcaPropertyID("2.1")) }
    XCTAssertTrue(fenced)
    XCTAssertEqual(changed.ids, [OcaPropertyID("2.1")])
  }

  func testACounterSetIsNotAPropertyOfItsOwner() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    let agent = try await { @OcaDevice in
      try await SwiftOCADevice.OcaCounterSetAgent(deviceDelegate: h.device, addToRootBlock: false)
    }()
    let interface = h.deviceInterface
    let (interfaceIDs, agentIDs, serialized) = try await { @OcaDevice in
      (
        interface.devicePropertyDescriptors.map(\.propertyID),
        agent.devicePropertyDescriptors.map(\.propertyID),
        try agent.serialize()
      )
    }()
    XCTAssertFalse(interfaceIDs.contains(OcaPropertyID("2.13")))
    XCTAssertFalse(agentIDs.contains(OcaPropertyID("3.1")))
    // a dataset neither keeps nor restores it
    XCTAssertNil(serialized[OcaPropertyID("3.1").description])
    // a controller reads it with the class's method
    let counterSet = try await h.interface.getCounterSet()
    XCTAssertEqual(counterSet.id, Self.counterSetID)
    XCTAssertEqual(counterSet.counter.map(\.id), [1, 2])
  }

  func testSetCounterSetIsChecked() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    let agent = try await { @OcaDevice in
      try await SwiftOCADevice.OcaCounterSetAgent(deviceDelegate: h.device, addToRootBlock: false)
    }()
    let clientAgent: SwiftOCA.OcaCounterSetAgent = try await h.connection.resolve(
      object: OcaObjectIdentification(
        oNo: agent.objectNumber,
        classIdentification: SwiftOCA.OcaCounterSetAgent.classIdentification
      )
    )
    func counter(_ id: OcaID16, notifiers: [OcaONo] = []) -> OcaCounter {
      OcaCounter(id: id, value: 0, initialValue: 0, role: "c\(id)", notifiers: notifiers)
    }
    let refused: [(String, [OcaCounter])] = [
      ("too many", (0...256).map { counter(OcaID16($0)) }),
      ("a duplicate ID", [counter(1), counter(1)]),
      ("a notifier that is not one", [counter(1, notifiers: [Self.interfaceONo])]),
      ("a notifier that does not exist", [counter(1, notifiers: [0x0001_0FFF])]),
    ]
    for (reason, counters) in refused {
      do {
        try await clientAgent.setCounterSet(counterSet: OcaCounterSet(counter: counters))
        XCTFail("accepted a set with \(reason)")
      } catch let Ocp1Error.status(status) {
        XCTAssertEqual(status, .parameterOutOfRange, reason)
      }
    }
    // the most counters, and the set keeps the agent's ID whatever is sent
    let agentID = await agent.counterSet.id
    try await clientAgent.setCounterSet(counterSet: OcaCounterSet(
      id: OcaBlob([9, 9]), counter: (1...256).map { counter(OcaID16($0), notifiers: [Self.notifierONo]) }
    ))
    let set = try await clientAgent.getCounterSet()
    XCTAssertEqual(set.counter.count, 256)
    XCTAssertEqual(set.id, agentID)
  }

  func testSetCounterSetReachesItsNotifiers() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 1))
    let agent = try await { @OcaDevice in
      try await SwiftOCADevice.OcaCounterSetAgent(deviceDelegate: h.device, addToRootBlock: false)
    }()
    let clientAgent: SwiftOCA.OcaCounterSetAgent = try await h.connection.resolve(
      object: OcaObjectIdentification(
        oNo: agent.objectNumber,
        classIdentification: SwiftOCA.OcaCounterSetAgent.classIdentification
      )
    )
    let agentID = await agent.counterSet.id
    func counterSet(value: OcaUint64) -> OcaCounterSet {
      OcaCounterSet(id: agentID, counter: [
        OcaCounter(id: 1, value: value, initialValue: 0, role: "one", notifiers: [Self.notifierONo]),
      ])
    }

    try await clientAgent.setCounterSet(counterSet: counterSet(value: 3))
    await h.settle([agent])
    try await clientAgent.setCounterSet(counterSet: counterSet(value: 4))
    await h.settle([agent])
    let events = await h.events(1)
    XCTAssertEqual(events, [
      OcaCounterUpdateEventData(updates: [OcaCounterUpdate(counterSetID: agentID, counterID: 1, value: 4)]),
    ])
    let read = try await clientAgent.getCounterSet()
    XCTAssertEqual(read, counterSet(value: 4))
  }

  func testACounterSetSetWithoutAnIDIsNamedByItsProperty() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    let interfaceID = try OcaPropertyCounterSetID(ownerONo: Self.interfaceONo, propertyID: OcaPropertyID("2.13")).blob
    // set after registration, as a subclass filling in its counters would
    let named = await { @OcaDevice in
      h.deviceInterface.counterSet = OcaCounterSet(counter: [
        OcaCounter(id: 1, value: 0, initialValue: 0, role: "one", notifiers: []),
      ])
      return h.deviceInterface.counterSet.id
    }()
    XCTAssertEqual(named, interfaceID)
    let read = try await h.interface.getCounterSet()
    XCTAssertEqual(read.id, interfaceID)

    // and by a controller's SetCounterSet
    let agent = try await { @OcaDevice in
      try await SwiftOCADevice.OcaCounterSetAgent(deviceDelegate: h.device, addToRootBlock: false)
    }()
    let clientAgent: SwiftOCA.OcaCounterSetAgent = try await h.connection.resolve(
      object: OcaObjectIdentification(
        oNo: agent.objectNumber,
        classIdentification: SwiftOCA.OcaCounterSetAgent.classIdentification
      )
    )
    try await clientAgent.setCounterSet(counterSet: OcaCounterSet(counter: [
      OcaCounter(id: 1, value: 2, initialValue: 0, role: "one", notifiers: []),
    ]))
    let agentSet = try await clientAgent.getCounterSet()
    XCTAssertEqual(
      agentSet.id,
      try OcaPropertyCounterSetID(ownerONo: agent.objectNumber, propertyID: OcaPropertyID("3.1")).blob
    )
  }

  func testEndpointIDZeroResetsEveryEndpoint() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    let application = try await { @OcaDevice in
      let application = try await SwiftOCADevice.OcaMediaTransportApplication(
        objectNumber: 0x0001_0731, deviceDelegate: h.device, addToRootBlock: false
      )
      // endpoint 2 has counter 2, endpoint 1 does not, as inputs' and outputs' differ
      for (id, counterIDs) in [(OcaMediaStreamEndpointID(2), [OcaID16(1), 2]), (1, [1])] {
        application.insert(
          endpoint: OcaMediaStreamEndpoint(idInternal: id, direction: .input, userLabel: "Input \(id)"),
          counterSet: OcaCounterSet(counter: counterIDs.map {
            OcaCounter(id: $0, value: 5, initialValue: 0, role: "c\($0)", notifiers: [Self.notifierONo])
          })
        )
      }
      return application
    }()
    let client: SwiftOCA.OcaMediaTransportApplication = try await h.connection.resolve(
      object: OcaObjectIdentification(
        oNo: application.objectNumber,
        classIdentification: SwiftOCA.OcaMediaTransportApplication.classIdentification
      )
    )
    await h.settle([application])
    let ids = await { @OcaDevice in application.endpointCounterSets.mapValues(\.id) }()
    func reset(_ id: OcaMediaStreamEndpointID, _ counterID: OcaID16) -> OcaCounterUpdate {
      OcaCounterUpdate(counterSetID: ids[id]!, counterID: counterID, value: 0)
    }

    // one counter: only where it is, and none of it is refused
    try await client.resetEndpointCounterSet(endpointID: 0, counterID: 2)
    var events = await h.events(1)
    XCTAssertEqual(events.last?.updates, [reset(2, 2)])
    do {
      try await client.resetEndpointCounterSet(endpointID: 0, counterID: 3)
      XCTFail("reset a counter no endpoint has")
    } catch let Ocp1Error.status(status) {
      XCTAssertEqual(status, .parameterOutOfRange)
    }
    // every counter of every endpoint, in endpoint order
    try await client.resetEndpointCounterSet(endpointID: 0, counterID: 0)
    events = await h.events(2)
    XCTAssertEqual(events.last?.updates, [reset(1, 1), reset(2, 1), reset(2, 2)])
  }

  func testAnOwnerSubclassRunsItsRegistrationAndTheLibrarys() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    let interface = try await { @OcaDevice in
      try await RegisteringInterface(objectNumber: 0x0001_0732, deviceDelegate: h.device, addToRootBlock: false)
    }()
    let (registered, id) = await { @OcaDevice in (interface.didRegisterCount, interface.counterSet.id) }()
    XCTAssertEqual(registered, 1)
    XCTAssertEqual(id, try OcaPropertyCounterSetID(ownerONo: 0x0001_0732, propertyID: OcaPropertyID("2.13")).blob)
  }

  func testAReregisteredNotifierStartsAfresh() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(period: 0.1, countDelta: 1))
    try await h.attach(1)
    let notifier = h.deviceNotifier
    try await h.device.deregister(object: notifier)
    let stopped = await { @OcaDevice in notifier.periodTimer == nil && notifier.observed.isEmpty }()
    XCTAssertTrue(stopped)

    try await h.device.register(object: notifier)
    let restarted = await waitUntil { await notifier.periodTimer != nil }
    XCTAssertTrue(restarted, "Period did not restart")
    let observed = await { @OcaDevice in notifier.observed.values.flatMap(\.keys).map(\.counterID) }()
    XCTAssertEqual(observed, [1], "the counters were not read again from the device's objects")
    try await h.step(counter: 1, value: 4)
    let latest = event(1, 4)
    let sent = await waitUntil { h.received.events.contains(latest) }
    XCTAssertTrue(sent)
  }

  func testAResetWaitingBehindASendIsNotReplaced() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(countDelta: 1))
    try await h.attach(1)
    let stalled = StalledController()
    let manager = await h.device.subscriptionManager
    try await XCTUnwrap(manager).addSubscription(.subscription2(OcaSubscription2(
      event: OcaEvent(emitterONo: Self.notifierONo, eventID: SwiftOCA.OcaCounterNotifier.counterUpdateEventID),
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )), for: stalled)
    try await h.set(counter: 1, value: 1)
    let entered = await waitUntil { await stalled.sendCount == 1 }
    XCTAssertTrue(entered)
    // while 1 is being sent: a reset, then a change after it
    let interface = h.deviceInterface
    let notifier = h.deviceNotifier
    try await { @OcaDevice in try interface.reset(&interface.counterSet, counter: 1) }()
    let readReset = await waitUntil { await notifier.hasRead(interface) }
    try await { @OcaDevice in try interface.set(counter: 1, value: 7) }()
    let readChange = await waitUntil { await notifier.hasRead(interface) }
    XCTAssertTrue(readReset && readChange)
    await stalled.release()
    await h.deviceNotifier.updatesDidSend()
    XCTAssertEqual(h.received.events, [event(1, 1), event(1, 0), event(1, 7)])
  }

  func testEndpointCounterSetsAreNamedAndTheirResetsNotified() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    let application = try await { @OcaDevice in
      let application = try await SwiftOCADevice.OcaMediaTransportApplication(
        objectNumber: 0x0001_0730, deviceDelegate: h.device, addToRootBlock: false
      )
      // two endpoints' sets, left to the application to name
      for id: OcaMediaStreamEndpointID in [1, 2] {
        application.insert(
          endpoint: OcaMediaStreamEndpoint(idInternal: id, direction: .input, userLabel: "Input \(id)"),
          counterSet: OcaCounterSet(counter: [
            OcaCounter(id: 1, value: 5, initialValue: 0, role: "one", notifiers: [Self.notifierONo]),
          ])
        )
      }
      return application
    }()
    let ids = await { @OcaDevice in application.endpointCounterSets.mapValues(\.id) }()
    for id: OcaMediaStreamEndpointID in [1, 2] {
      XCTAssertEqual(ids[id], try OcaMediaStreamEndpointCounterSetID(ownerONo: 0x0001_0730, endpointID: id).blob)
    }
    await h.settle([application])

    // a reset is notified though the filters would pass nothing; a reset of a reset too
    try await { @OcaDevice in try application.resetEndpointCounterSet(endpointID: 2, counterID: 1) }()
    await h.settle([application])
    try await { @OcaDevice in try application.resetEndpointCounterSet(endpointID: 2, counterID: 1) }()
    await h.settle([application])
    let events = await h.events(2)
    let reset = OcaCounterUpdateEventData(updates: [OcaCounterUpdate(counterSetID: ids[2]!, counterID: 1, value: 0)])
    XCTAssertEqual(events, [reset, reset])
    // the client's method does the same
    let client: SwiftOCA.OcaMediaTransportApplication = try await h.connection.resolve(
      object: OcaObjectIdentification(
        oNo: application.objectNumber,
        classIdentification: SwiftOCA.OcaMediaTransportApplication.classIdentification
      )
    )
    try await client.resetEndpointCounterSet(endpointID: 1)
    let all = await h.events(3)
    XCTAssertEqual(all.last, OcaCounterUpdateEventData(updates: [
      OcaCounterUpdate(counterSetID: ids[1]!, counterID: 1, value: 0),
    ]))
  }

  func testADeregisteredNotifierSendsNothingMore() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }
    try await h.set(filterParameters: filter(period: 0.1, countDelta: 1))
    try await h.attach(1)
    // a subscriber that holds the first send, so that later updates wait behind it
    let stalled = StalledController()
    let manager = await h.device.subscriptionManager
    try await XCTUnwrap(manager).addSubscription(.subscription2(OcaSubscription2(
      event: OcaEvent(emitterONo: Self.notifierONo, eventID: SwiftOCA.OcaCounterNotifier.counterUpdateEventID),
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )), for: stalled)
    for value in OcaUint64(1)...3 {
      try await h.set(counter: 1, value: value)
    }
    let notifier = h.deviceNotifier
    let waiting = await waitUntil { await notifier.pendingUpdateCount > 0 }
    XCTAssertTrue(waiting, "no update waited behind the stalled send")

    try await h.device.deregister(object: notifier)
    let count = h.received.events.count
    let stopped = await { @OcaDevice in notifier.periodTimer == nil }()
    XCTAssertTrue(stopped, "the period timer outlived the registration")
    await stalled.release()
    await notifier.updatesDidSend()
    // still named by the interface's counter, which changes
    try await h.set(counter: 1, value: 4)
    await h.settle()
    let kept = await { @OcaDevice in notifier.observedCounterCount }()
    XCTAssertEqual(kept, 0, "a deregistered notifier kept counters")
    XCTAssertEqual(h.received.events.count, count, "a deregistered notifier sent updates")
  }

  func testEventDataIsCodedAsTheModelHasIt() throws {
    let updates = [update(1, 3), update(2, 4)]
    let data = OcaCounterUpdateEventData(updates: updates)
    // OCP.1: the list alone, as the struct's only field
    XCTAssertEqual(try Ocp1Encoder().encode(data) as [UInt8], try Ocp1Encoder().encode(updates) as [UInt8])
    // OCP.2: named as AES70-2 names them
    let encoded = try XCTUnwrap(try Ocp2Encoder().encodeValue(data) as? [String: Any])
    XCTAssertEqual(Set(encoded.keys), ["Updates"])
    let first = try XCTUnwrap((encoded["Updates"] as? [Any])?.first as? [String: Any])
    XCTAssertEqual(Set(first.keys), ["CounterSetID", "CounterID", "Value"])
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaCounterUpdateEventData.self, from: encoded), data)
  }

  // MARK: - Helpers

  private func filter(
    threshold: OcaUint64 = 0,
    operator: OcaRelationalOperator = .none,
    period: OcaTimeInterval = 0,
    countDelta: OcaUint64 = 0
  ) -> OcaCounterNotifierFilterParameters {
    OcaCounterNotifierFilterParameters(
      threshold: threshold,
      operator: `operator`,
      period: period,
      countDelta: countDelta
    )
  }

  private func update(_ counterID: OcaID16, _ value: OcaUint64) -> OcaCounterUpdate {
    OcaCounterUpdate(counterSetID: Self.counterSetID, counterID: counterID, value: value)
  }

  private func event(_ counterID: OcaID16, _ value: OcaUint64) -> OcaCounterUpdateEventData {
    OcaCounterUpdateEventData(updates: [update(counterID, value)])
  }

  private func makeHarness() async throws -> Harness {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device, controlProtocol: .ocp1)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(endpoint)
    try await connection.connect()

    let deviceInterface = try await SwiftOCADevice.OcaNetworkInterface(
      objectNumber: Self.interfaceONo,
      role: "Interface",
      deviceDelegate: device,
      addToRootBlock: true
    )
    await { @OcaDevice in
      deviceInterface.counterSet = OcaCounterSet(id: Self.counterSetID, counter: [
        OcaCounter(id: 1, value: 0, initialValue: 0, role: "one", notifiers: []),
        OcaCounter(id: 2, value: 0, initialValue: 0, role: "two", notifiers: []),
      ])
    }()
    let deviceNotifier = try await CountingNotifier(
      objectNumber: Self.notifierONo,
      role: "Notifier",
      deviceDelegate: device,
      addToRootBlock: true
    )

    let interface: SwiftOCA.OcaNetworkInterface = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: Self.interfaceONo,
        classIdentification: SwiftOCA.OcaNetworkInterface.classIdentification
      )
    )
    let notifier: SwiftOCA.OcaCounterNotifier = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: Self.notifierONo,
        classIdentification: SwiftOCA.OcaCounterNotifier.classIdentification
      )
    )

    let received = ReceivedUpdates(from: Self.notifierONo)
    await device.setEventDelegate(received)
    // a subscriber, so that the device sends the events it tells the delegate of
    let event = OcaEvent(
      emitterONo: Self.notifierONo,
      eventID: SwiftOCA.OcaCounterNotifier.counterUpdateEventID
    )
    _ = try await connection.addSubscription(label: "counter", event: event) { _, _ in }

    return Harness(
      device: device,
      connection: connection,
      endpointTask: endpointTask,
      deviceInterface: deviceInterface,
      deviceNotifier: deviceNotifier,
      interface: interface,
      notifier: notifier,
      received: received
    )
  }
}

private actor TestController: OcaController {
  nonisolated let flags: OcaControllerFlags = [.supportsLocking]
  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {}
}

/// A controller whose sends never finish until released, as one would whose peer stopped
/// reading.
private actor StalledController: OcaController {
  nonisolated let flags: OcaControllerFlags = []
  private(set) var sendCount = 0
  private var waiting = [CheckedContinuation<(), Never>]()
  private var isReleased = false

  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {
    sendCount += 1
    guard !isReleased else { return }
    await withCheckedContinuation { waiting.append($0) }
  }

  func release() {
    isReleased = true
    waiting.forEach { $0.resume() }
    waiting = []
  }
}

/// A count once it has stopped changing for a while, as messages already sent arrive.
private func stableCount(_ count: @Sendable () -> Int) async -> Int {
  var last = count()
  while true {
    try? await Task.sleep(for: .milliseconds(150))
    let current = count()
    if current == last { return current }
    last = current
  }
}

private func waitUntil(
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
#endif
