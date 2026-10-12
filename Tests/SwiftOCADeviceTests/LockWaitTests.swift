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

import Foundation
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

private actor WaitingController: OcaController {
  nonisolated let flags: OcaControllerFlags = [.supportsLocking]

  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {}
}

/// LockWait waiters must go when their wait ends, however it ends, or a later unlock
/// locks the target for a controller that was told otherwise (issue #179).
final class LockWaitTests: XCTestCase {
  private struct Fixture {
    let device: OcaDevice
    let lockManager: SwiftOCADevice.OcaLockManager
    let object: SwiftOCADevice.OcaWorker
    let holder = WaitingController()
    let waiter = WaitingController()
  }

  @OcaDevice
  private func makeFixture() async throws -> Fixture {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let lockManager = try await SwiftOCADevice.OcaLockManager(deviceDelegate: device)
    let object = try await SwiftOCADevice.OcaWorker(
      objectNumber: 10000, role: "Contended", deviceDelegate: device
    )
    let fixture = Fixture(device: device, lockManager: lockManager, object: object)
    try await object.setLockNoReadWrite(from: fixture.holder)
    return fixture
  }

  @OcaDevice
  private static func lockWait(
    _ fixture: Fixture,
    timeout: OcaTimeInterval
  ) async throws -> Ocp1Response {
    let command = try Ocp1Command(
      handle: 1,
      targetONo: OcaLockManagerONo,
      methodID: SwiftOCA.OcaLockManager.Methods.lockWait.methodID,
      parameters: OcaParameters(
        parameterCount: 3,
        parameterData: Ocp1Encoder().encode(SwiftOCA.OcaLockManager.LockWaitParameters(
          target: fixture.object.objectNumber, type: .lockNoReadWrite, timeout: timeout
        ))
      )
    )
    return try await fixture.lockManager.handleCommand(command, from: fixture.waiter)
  }

  @OcaDevice
  private static func abortWaits(_ fixture: Fixture) async throws -> Ocp1Response {
    let command = try Ocp1Command(
      handle: 2,
      targetONo: OcaLockManagerONo,
      methodID: SwiftOCA.OcaLockManager.Methods.abortWaits.methodID,
      parameters: OcaParameters(
        parameterCount: 1,
        parameterData: Ocp1Encoder().encode(fixture.object.objectNumber)
      )
    )
    return try await fixture.lockManager.handleCommand(command, from: fixture.waiter)
  }

  /// Starts a wait long enough to outlive the test and returns once it is registered.
  @OcaDevice
  private func startWaiting(_ fixture: Fixture) async throws -> Task<Ocp1Response, Error> {
    let waiting = Task { @OcaDevice in try await Self.lockWait(fixture, timeout: 30) }
    let registered = await eventually { fixture.lockManager.lockWaiterCount == 1 }
    XCTAssertTrue(registered, "the wait was not registered")
    return waiting
  }

  @OcaDevice
  private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
      if condition() { return true }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return false
  }

  /// Unlocks the target as its holder and gives any leftover waiter a chance to misbehave.
  @OcaDevice
  private func unlockAndSettle(_ fixture: Fixture) async throws {
    try await fixture.object.unlock(from: fixture.holder)
    try await Task.sleep(for: .milliseconds(100))
  }

  @OcaDevice
  func testATimedOutWaiterIsGoneAndALaterUnlockDoesNotLockForIt() async throws {
    let fixture = try await makeFixture()

    do {
      _ = try await Self.lockWait(fixture, timeout: 0.05)
      XCTFail("the wait did not time out")
    } catch Ocp1Error.status(.timeout) {}
    XCTAssertEqual(fixture.lockManager.lockWaiterCount, 0)

    try await unlockAndSettle(fixture)
    XCTAssertEqual(fixture.object.lockState, .unlocked)
    XCTAssertEqual(fixture.lockManager.lockWaiterCount, 0)
  }

  @OcaDevice
  func testAnAbortedWaiterIsGoneAndALaterUnlockDoesNotLockForIt() async throws {
    let fixture = try await makeFixture()
    let waiting = try await startWaiting(fixture)

    let aborted = try await Self.abortWaits(fixture)
    XCTAssertEqual(aborted.statusCode, .ok)
    do {
      _ = try await waiting.value
      XCTFail("the aborted wait returned")
    } catch is CancellationError {}
    XCTAssertEqual(fixture.lockManager.lockWaiterCount, 0)

    try await unlockAndSettle(fixture)
    XCTAssertEqual(fixture.object.lockState, .unlocked)
  }

  @OcaDevice
  func testAGrantedWaiterIsGone() async throws {
    let fixture = try await makeFixture()
    let waiting = try await startWaiting(fixture)

    try await fixture.object.unlock(from: fixture.holder)
    let granted = try await waiting.value
    XCTAssertEqual(granted.statusCode, .ok)
    XCTAssertEqual(fixture.object.lockState, .lockedNoReadWrite(fixture.waiter.id))
    XCTAssertEqual(fixture.lockManager.lockWaiterCount, 0)
  }

  @OcaDevice
  func testAnExpiredControllersWaitersAreGone() async throws {
    let fixture = try await makeFixture()
    let waiting = try await startWaiting(fixture)

    await fixture.device.expire(controller: fixture.waiter)
    do {
      _ = try await waiting.value
      XCTFail("the expired controller's wait returned")
    } catch is CancellationError {}
    XCTAssertEqual(fixture.lockManager.lockWaiterCount, 0)

    try await unlockAndSettle(fixture)
    XCTAssertEqual(fixture.object.lockState, .unlocked)
  }

  @OcaDevice
  func testACancelledCallersWaiterIsGone() async throws {
    let fixture = try await makeFixture()
    let waiting = try await startWaiting(fixture)

    waiting.cancel()
    do {
      _ = try await waiting.value
      XCTFail("the cancelled wait returned")
    } catch is CancellationError {}
    XCTAssertEqual(fixture.lockManager.lockWaiterCount, 0)

    try await unlockAndSettle(fixture)
    XCTAssertEqual(fixture.object.lockState, .unlocked)
  }

  @OcaDevice
  func testASecondWaitOnTheSameTargetReplacesTheFirst() async throws {
    let fixture = try await makeFixture()
    let first = try await startWaiting(fixture)

    let second = Task { @OcaDevice in try await Self.lockWait(fixture, timeout: 30) }
    do {
      _ = try await first.value
      XCTFail("the replaced wait returned")
    } catch is CancellationError {}
    XCTAssertEqual(fixture.lockManager.lockWaiterCount, 1)

    try await fixture.object.unlock(from: fixture.holder)
    let granted = try await second.value
    XCTAssertEqual(granted.statusCode, .ok)
    XCTAssertEqual(fixture.object.lockState, .lockedNoReadWrite(fixture.waiter.id))
    XCTAssertEqual(fixture.lockManager.lockWaiterCount, 0)
  }

  /// Which way a grant at the deadline goes cannot be ordered from here, so this runs the
  /// race and checks that the reply and the lock state agree whichever side won.
  @OcaDevice
  func testTheReplyAgreesWithTheLockStateWhenGrantedAtTheDeadline() async throws {
    let fixture = try await makeFixture()

    for _ in 0..<20 {
      let waiting = Task { @OcaDevice in try await Self.lockWait(fixture, timeout: 0.02) }
      try await Task.sleep(for: .milliseconds(20))
      try? await fixture.object.unlock(from: fixture.holder)

      do {
        _ = try await waiting.value
        XCTAssertEqual(fixture.object.lockState, .lockedNoReadWrite(fixture.waiter.id))
        try await fixture.object.unlock(from: fixture.waiter)
      } catch Ocp1Error.status(.timeout) {
        let givenBack = await eventually { fixture.object.lockState == .unlocked }
        XCTAssertTrue(givenBack, "told timeout but holding the lock")
      }
      XCTAssertEqual(fixture.lockManager.lockWaiterCount, 0)
      try await fixture.object.setLockNoReadWrite(from: fixture.holder)
    }
  }
}
