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

/// Owns a write queue, as a connection or controller does, over a transport that holds each
/// write until released, as a peer that has stopped reading would.
private actor StalledTransport {
  let queue = Ocp1WriteQueue()
  private(set) var written = [Int]()
  private(set) var entered = 0
  private var release: CheckedContinuation<Void, Never>?

  /// Queues a write of `bytes`, tagged `tag`, without waiting for it.
  func enqueue(_ tag: Int, bytes: Int, budget: Int) throws {
    try queue.enqueue(bytes: bytes, maximumBacklogBytes: budget) { [self] in
      await self.write(tag)
    }
  }

  private func write(_ tag: Int) async {
    entered += 1
    await withCheckedContinuation { release = $0 }
    written.append(tag)
  }

  /// Lets the write in the transport finish.
  func releaseOne() {
    release?.resume()
    release = nil
  }


  var backlogBytes: Int { queue.backlogBytes }
}

final class WriteBacklogTests: XCTestCase {
  func testQueuedWritesReturnAtOnceAndRunInOrder() async throws {
    let transport = StalledTransport()
    let started = ContinuousClock.now
    for tag in 1...3 {
      try await transport.enqueue(tag, bytes: 10, budget: 100)
    }
    XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(100), "enqueue waited on the transport")
    // the first write is in the transport; the two behind it are the backlog
    let entered = await waitUntil { await transport.entered == 1 }
    XCTAssertTrue(entered)
    let waiting = await transport.backlogBytes
    XCTAssertEqual(waiting, 20)
    for count in 1...3 {
      let inTransport = await waitUntil { await transport.entered == count }
      XCTAssertTrue(inTransport, "write \(count) did not reach the transport")
      await transport.releaseOne()
      let done = await waitUntil { await transport.written.count == count }
      XCTAssertTrue(done, "write \(count) did not finish")
    }
    let written = await transport.written
    XCTAssertEqual(written, [1, 2, 3])
    let empty = await transport.backlogBytes
    XCTAssertEqual(empty, 0)
  }

  func testABacklogPastTheBudgetIsRefused() async throws {
    let transport = StalledTransport()
    try await transport.enqueue(1, bytes: 10, budget: 25) // taken by the transport at once
    let entered = await waitUntil { await transport.entered == 1 }
    XCTAssertTrue(entered)
    try await transport.enqueue(2, bytes: 10, budget: 25)
    try await transport.enqueue(3, bytes: 10, budget: 25)
    do {
      try await transport.enqueue(4, bytes: 10, budget: 25)
      XCTFail("a fourth write was taken past the budget")
    } catch let error as Ocp1Error {
      XCTAssertEqual(error, .writeBacklogExceeded)
    }
    // what waited is dropped with the refusal, and the queue stays refused: the owner is
    // on its way out; only the write already in the transport goes out
    let dropped = await transport.backlogBytes
    XCTAssertEqual(dropped, 0)
    await transport.releaseOne()
    let finished = await waitUntil { await transport.written == [1] }
    XCTAssertTrue(finished)
    try? await Task.sleep(for: .milliseconds(50))
    let reached = await transport.entered
    XCTAssertEqual(reached, 1, "a dropped write reached the transport")
    do {
      try await transport.enqueue(5, bytes: 10, budget: 25)
      XCTFail("a write was taken after the budget was passed")
    } catch let error as Ocp1Error {
      XCTAssertEqual(error, .writeBacklogExceeded)
    }
  }

  func testAWriteToAnEmptyBacklogIsTakenWhateverItsSize() async throws {
    let transport = StalledTransport()
    try await transport.enqueue(1, bytes: 1000, budget: 25)
    let entered = await waitUntil { await transport.entered == 1 }
    XCTAssertTrue(entered)
    await transport.releaseOne()
    let drained = await waitUntil { await transport.written == [1] }
    XCTAssertTrue(drained)
    try await transport.enqueue(2, bytes: 1000, budget: 25)
  }

}
