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
import XCTest

/// A connection whose transport is entirely under the test's control.
///
/// `connect()` is deliberately not used; the tests install a monitor directly,
/// because what is under test is request bookkeeping rather than the connection
/// handshake.
private final class MockConnection: Ocp1Connection, @unchecked Sendable {
  /// how long `write` stalls before reporting success
  nonisolated(unsafe) var writeDelay: Duration = .zero
  /// set when `write` is entered, so a test can tell a stalled write from one
  /// that was never attempted
  nonisolated(unsafe) private(set) var didAttemptWrite = false
  nonisolated(unsafe) var writeError: (any Error)?

  override nonisolated var connectionPrefix: String { "oca/mock" }

  override var isDatagram: Bool { false }

  override var heartbeatTime: Duration { .zero }

  override func read(_ length: Int) async throws -> Data {
    // no device on the other end: block until cancelled
    try await Task.sleep(for: .seconds(3600))
    throw Ocp1Error.notConnected
  }

  override func write(_ data: Data) async throws -> Int {
    didAttemptWrite = true
    if writeDelay > .zero {
      try? await Task.sleep(for: writeDelay)
    }
    if let writeError {
      throw writeError
    }
    return data.count
  }
}

@OcaConnection
private func makeConnection(
  responseTimeout: Duration = .milliseconds(200)
) -> MockConnection {
  MockConnection(options: Ocp1ConnectionOptions(responseTimeout: responseTimeout))
}

@OcaConnection
private func makeMonitor(_ connection: MockConnection) -> Ocp1Connection.Monitor {
  Ocp1Connection.Monitor(connection, id: 1)
}

/// Installs a monitor without going through `connect()`, which would need a
/// live device on the other end.
@OcaConnection
@discardableResult
private func installMonitor(on connection: MockConnection) -> Ocp1Connection.Monitor {
  let monitor = Ocp1Connection.Monitor(connection, id: 1)
  connection.monitor = monitor
  return monitor
}

private func makeResponse(handle: OcaUint32) -> Ocp1Response {
  Ocp1Response(responseSize: 10, handle: handle, statusCode: .ok)
}

/// Waits for a sender to actually suspend. Sleeping a fixed interval instead
/// would let a slow scheduler silently turn these tests into hangs.
private func waitUntilWaiting(
  _ monitor: Ocp1Connection.Monitor,
  handle: OcaUint32,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  while !monitor.isWaiting(handle: handle), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(1))
  }
  XCTAssertTrue(monitor.isWaiting(handle: handle), "sender never suspended", file: file, line: line)
}

final class RequestContinuationTests: XCTestCase {
  private static let handle: OcaUint32 = 4242

  private func response(handle: OcaUint32 = RequestContinuationTests.handle) -> Ocp1Response {
    makeResponse(handle: handle)
  }

  // MARK: - request bookkeeping

  /// A response parsed before the sender suspends must be held, not dropped.
  /// The monitor runs off `@OcaConnection`, so on a fast transport this is the
  /// normal ordering, and dropping it stalled the caller until its timeout.
  func testResponseArrivingBeforeSenderSuspends() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    try monitor.resume(with: response())

    let received = try await monitor.response(for: Self.handle)
    XCTAssertEqual(received.handle, Self.handle)
    XCTAssertEqual(received.statusCode, .ok)
  }

  /// A timeout firing before the sender suspends must also be held. Previously
  /// the sender went on to suspend on a continuation nobody would ever resume,
  /// so the enclosing task group never drained and the call hung forever.
  func testTimeoutFiringBeforeSenderSuspends() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    monitor.resumeTimedOut(handle: Self.handle)

    do {
      _ = try await monitor.response(for: Self.handle)
      XCTFail("expected responseTimeout")
    } catch Ocp1Error.responseTimeout {
      // expected, and — critically — it returns at all
    }
  }

  /// Ordinary ordering: the sender suspends first, the response arrives later.
  func testResponseArrivingAfterSenderSuspends() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    async let pending = monitor.response(for: Self.handle)

    try await waitUntilWaiting(monitor, handle: Self.handle)
    try monitor.resume(with: response())

    let received = try await pending
    XCTAssertEqual(received.handle, Self.handle)
  }

  /// Only the first result is delivered; a late response for a handle that has
  /// already timed out must not resume anything a second time.
  func testFirstResultWins() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    monitor.resumeTimedOut(handle: Self.handle)
    // late response for the same handle: accepted as "was outstanding", ignored
    XCTAssertNoThrow(try monitor.resume(with: response()))

    do {
      _ = try await monitor.response(for: Self.handle)
      XCTFail("expected responseTimeout")
    } catch Ocp1Error.responseTimeout {}
  }

  /// A response for a handle nobody is waiting on is reported so the receive
  /// loop can ignore it rather than treating it as a protocol error.
  func testResponseForUnknownHandleThrowsInvalidHandle() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertThrowsError(try monitor.resume(with: response())) { error in
      XCTAssertEqual(error as? Ocp1Error, .invalidHandle)
    }
  }

  /// Withdrawing after a failed send must not leave the entry behind.
  func testWithdrawnRequestIsNotOutstanding() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    monitor.releaseCommandHandle(Self.handle)

    XCTAssertThrowsError(try monitor.resume(with: response())) { error in
      XCTAssertEqual(error as? Ocp1Error, .invalidHandle)
    }
  }

  /// Two requests cannot share a handle; the second must be refused rather than
  /// overwriting the first, which would strand the first sender forever.
  func testDuplicateWaiterIsRefused() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    async let first = monitor.response(for: Self.handle)
    try await waitUntilWaiting(monitor, handle: Self.handle)

    do {
      _ = try await monitor.response(for: Self.handle)
      XCTFail("expected invalidHandle")
    } catch Ocp1Error.invalidHandle {}

    // the original waiter is still intact and still resumable
    try monitor.resume(with: response())
    let received = try await first
    XCTAssertEqual(received.handle, Self.handle)
  }

  /// Tearing the connection down resumes suspended senders...
  func testStopResumesWaitingSenders() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    async let pending = monitor.response(for: Self.handle)
    try await waitUntilWaiting(monitor, handle: Self.handle)

    monitor.stop()

    do {
      _ = try await pending
      XCTFail("expected notConnected")
    } catch Ocp1Error.notConnected {}
  }

  /// ...and senders that have not suspended yet.
  func testStopReleasesEnrolledSenders() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    monitor.stop()

    do {
      _ = try await monitor.response(for: Self.handle)
      XCTFail("expected notConnected")
    } catch Ocp1Error.notConnected {}
  }

  // MARK: - end-to-end

  /// The regression that motivated the rework: when the write stalls past the
  /// response timeout, `sendCommandRrq` must still return. Previously the
  /// timeout had nowhere to record its result, the operation task suspended
  /// afterwards on an orphaned continuation, and the task group never drained.
  func testStalledWriteStillTimesOut() async throws {
    let responseTimeout = Duration.milliseconds(200)
    let connection = await makeConnection(responseTimeout: responseTimeout)
    connection.writeDelay = .milliseconds(600)
    await installMonitor(on: connection)

    let command = Ocp1Command(
      handle: Self.handle,
      targetONo: 5000,
      methodID: OcaMethodID("2.6")
    )

    let start = ContinuousClock.now
    do {
      _ = try await connection.sendCommandRrq(command)
      XCTFail("expected responseTimeout")
    } catch Ocp1Error.responseTimeout {}
    let elapsed = ContinuousClock.now - start

    XCTAssertTrue(connection.didAttemptWrite)
    // must not hang: bounded by the stalled write, not by the 1h mock read
    XCTAssertLessThan(elapsed, .seconds(5))
  }

  /// A handle that is still outstanding must not be re-enrolled: the 32-bit
  /// wire handle wraps after 2^32 requests, and overwriting the entry would
  /// strand the earlier sender forever.
  func testEnrollRefusesAnOutstandingHandle() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    async let first = monitor.response(for: Self.handle)
    try await waitUntilWaiting(monitor, handle: Self.handle)

    // the collision is refused rather than clobbering the waiting sender
    XCTAssertFalse(monitor.claimCommandHandle(Self.handle))

    // ...and the original sender is still reachable
    try monitor.resume(with: response())
    let received = try await first
    XCTAssertEqual(received.handle, Self.handle)
  }

  /// Re-enrolment is likewise refused while a result is parked but unclaimed.
  func testEnrollRefusesAHandleWithAParkedResult() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    try monitor.resume(with: response())

    XCTAssertFalse(monitor.claimCommandHandle(Self.handle))
    let received = try await monitor.response(for: Self.handle)
    XCTAssertEqual(received.handle, Self.handle)
  }

  /// Cancelling a suspended sender must resume it rather than leaving it parked
  /// on a continuation nobody will ever resume.
  func testCancellationResumesASuspendedSender() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    let handle = Self.handle
    let task = Task { () async -> (any Error)? in
      do {
        _ = try await monitor.response(for: handle)
        return nil
      } catch {
        return error
      }
    }
    try await waitUntilWaiting(monitor, handle: Self.handle)
    task.cancel()

    // expected, and — critically — it returns at all
    let error = await task.value
    XCTAssertTrue(error is CancellationError, "expected CancellationError, got \(error as Any)")
  }

  /// Cancellation arriving before the sender suspends must also be retained.
  func testCancellationBeforeSuspensionIsRetained() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    let handle = Self.handle
    let task = Task { () async -> (any Error)? in
      // already cancelled by the time the body reaches response(for:)
      try? await Task.sleep(for: .milliseconds(200))
      do {
        _ = try await monitor.response(for: handle)
        return nil
      } catch {
        return error
      }
    }
    task.cancel()

    let error = await task.value
    XCTAssertTrue(error is CancellationError, "expected CancellationError, got \(error as Any)")
  }

  /// Teardown must not discard a response that already arrived — reporting
  /// notConnected for a command the device completed could make a caller retry
  /// a non-idempotent operation.
  func testStopPreservesAnAlreadyArrivedResponse() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    try monitor.resume(with: response())

    monitor.stop()

    let received = try await monitor.response(for: Self.handle)
    XCTAssertEqual(received.handle, Self.handle)
    XCTAssertEqual(received.statusCode, .ok)
  }

  /// The sender withdraws on whichever path it exits by, so a result parked
  /// for one that has already given up must not outlive it.
  func testWithdrawDropsAnUncollectedResult() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    try monitor.resume(with: response())

    // the send reported failure, but the device answered anyway. Its sender
    // has thrown by now and will never collect, so the entry has to go.
    monitor.releaseCommandHandle(Self.handle)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
  }

  /// Withdrawing a suspended sender must not strand it either.
  func testWithdrawDoesNotStrandASuspendedSender() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    async let pending = monitor.response(for: Self.handle)
    try await waitUntilWaiting(monitor, handle: Self.handle)

    monitor.releaseCommandHandle(Self.handle)

    // still reachable, so the response can still complete it
    try monitor.resume(with: response())
    let received = try await pending
    XCTAssertEqual(received.handle, Self.handle)
  }

  /// Withdrawing an enrolment nothing has touched does release it.
  func testWithdrawClearsAPendingEnrolment() async throws {
    let connection = await makeConnection()
    let monitor = await makeMonitor(connection)

    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
    monitor.releaseCommandHandle(Self.handle)

    // released, so the handle can be reused
    XCTAssertTrue(monitor.claimCommandHandle(Self.handle))
  }

  /// A send that fails must surface the send error, and must not leave the
  /// request enrolled.
  func testFailedSendWithdrawsRequest() async throws {
    let connection = await makeConnection(responseTimeout: .seconds(30))
    connection.writeError = Ocp1Error.pduSendingFailed
    await installMonitor(on: connection)

    let command = Ocp1Command(
      handle: Self.handle,
      targetONo: 5000,
      methodID: OcaMethodID("2.6")
    )

    do {
      _ = try await connection.sendCommandRrq(command)
      XCTFail("expected a send failure")
    } catch let error as Ocp1Error {
      XCTAssertNotEqual(error, .responseTimeout)
    }

    let outstanding = await connection.statistics.outstandingRequests
    XCTAssertEqual(outstanding, [])
  }
}
