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

@testable @_spi(SwiftOCAPrivate) import SwiftOCA
import XCTest

/// The timer `sendCommandRrq` waits on for its response deadline. A wait must return
/// at its deadline, throw at once when cancelled whether or not it has suspended yet,
/// fire on time even when it falls due before a wait already pending, and leave
/// nothing behind.
final class DeadlineTimerTests: XCTestCase {
  /// generous, so that a slow scheduler cannot turn these into flakes
  private static let slack = Duration.seconds(2)

  private func waitUntilOutstanding(_ timer: DeadlineTimer, _ count: Int) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while timer.outstanding < count, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
    XCTAssertEqual(timer.outstanding, count, "wait never registered")
  }

  func testWaitReturnsAtItsDeadline() async throws {
    let timer = DeadlineTimer()
    let start = ContinuousClock.now
    try await timer.wait(until: start.advanced(by: .milliseconds(50)))
    let elapsed = ContinuousClock.now - start

    XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(50))
    XCTAssertLessThan(elapsed, Self.slack)
    XCTAssertEqual(timer.outstanding, 0)
  }

  func testAPassedDeadlineReturnsAtOnce() async throws {
    let timer = DeadlineTimer()
    try await timer.wait(until: .now)
    XCTAssertEqual(timer.outstanding, 0)
  }

  func testCancellationWhileWaitingThrowsAtOnce() async throws {
    let timer = DeadlineTimer()
    let task = Task { try await timer.wait(until: .now.advanced(by: .seconds(60))) }
    try await waitUntilOutstanding(timer, 1)

    let start = ContinuousClock.now
    task.cancel()
    do {
      try await task.value
      XCTFail("expected CancellationError")
    } catch is CancellationError {}

    XCTAssertLessThan(ContinuousClock.now - start, Self.slack)
    XCTAssertEqual(timer.outstanding, 0)
  }

  func testCancellationBeforeWaitingIsHonoured() async throws {
    let timer = DeadlineTimer()
    let task = Task {
      // already cancelled by the time it reaches the timer
      while !Task.isCancelled {
        await Task.yield()
      }
      try await timer.wait(until: .now.advanced(by: .seconds(60)))
    }
    task.cancel()
    do {
      try await task.value
      XCTFail("expected CancellationError")
    } catch is CancellationError {}

    XCTAssertEqual(timer.outstanding, 0)
  }

  /// The loop sleeps until the earliest deadline it knows of, so a wait due sooner
  /// must wake it rather than wait behind the later one.
  func testAnEarlierDeadlineAddedLaterIsNotLate() async throws {
    let timer = DeadlineTimer()
    let long = Task { try await timer.wait(until: .now.advanced(by: .seconds(60))) }
    try await waitUntilOutstanding(timer, 1)
    // let the loop settle on the long deadline
    try await Task.sleep(for: .milliseconds(50))

    let start = ContinuousClock.now
    try await timer.wait(until: start.advanced(by: .milliseconds(50)))
    XCTAssertLessThan(ContinuousClock.now - start, Self.slack)

    long.cancel()
    _ = try? await long.value
    XCTAssertEqual(timer.outstanding, 0)
  }

  func testConcurrentWaitsAllReturn() async throws {
    let timer = DeadlineTimer()
    let start = ContinuousClock.now
    try await withThrowingTaskGroup(of: Void.self) { group in
      for milliseconds in [90, 30, 60] {
        group.addTask {
          try await timer.wait(until: start.advanced(by: .milliseconds(milliseconds)))
        }
      }
      try await group.waitForAll()
    }
    XCTAssertLessThan(ContinuousClock.now - start, Self.slack)
    XCTAssertEqual(timer.outstanding, 0)
  }

  /// What a busy connection does: each request's timeout is cancelled by its response.
  func testCancelledWaitsLeaveNothingBehind() async throws {
    let timer = DeadlineTimer()
    for _ in 0..<1000 {
      let task = Task { try await timer.wait(until: .now.advanced(by: .seconds(60))) }
      task.cancel()
      _ = try? await task.value
    }
    XCTAssertEqual(timer.outstanding, 0)
  }
}
