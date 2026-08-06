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

/// A connection whose `write` reports partial progress, as the stream backends do:
/// each suspends mid-PDU and resumes from an offset, which is what lets a second
/// writer interleave its bytes with the first.
private final class ChunkedWriteConnection: Ocp1Connection, @unchecked Sendable {
  nonisolated(unsafe) var datagram = false
  nonisolated(unsafe) private(set) var chunks = [UInt8]()
  nonisolated(unsafe) private(set) var maxInFlight = 0
  nonisolated(unsafe) private(set) var didEnterWrite = false
  /// how long the first writer occupies the transport, to park a second one in the queue
  nonisolated(unsafe) var holdFirstWrite: Duration = .zero
  /// a throwing suspension partway through the PDU, so an aborted write truncates it
  nonisolated(unsafe) var midWritePause: Duration = .zero
  private var inFlight = 0
  private var entered = 0

  override nonisolated var connectionPrefix: String { "oca/chunked" }

  override var isDatagram: Bool { datagram }

  override var heartbeatTime: Duration { .zero }

  override func read(_ length: Int) async throws -> Data {
    try await Task.sleep(for: .seconds(3600))
    throw Ocp1Error.notConnected
  }

  override func write(_ data: Data) async throws -> Int {
    didEnterWrite = true
    inFlight += 1
    entered += 1
    let isFirst = entered == 1
    maxInFlight = max(maxInFlight, inFlight)
    defer { inFlight -= 1 }

    if isFirst, holdFirstWrite > .zero {
      try await Task.sleep(for: holdFirstWrite)
    }

    // Bounded, so serialisation holding the second writer out does not deadlock.
    for _ in 0..<64 where entered < 2 {
      await Task.yield()
    }

    for (offset, byte) in data.enumerated() {
      if offset == data.count / 2, midWritePause > .zero {
        try await Task.sleep(for: midWritePause)
      }
      chunks.append(byte)
      await Task.yield()
    }
    return data.count
  }

  nonisolated var runs: Int {
    var n = 0
    var last: UInt8?
    for c in chunks where c != last {
      n += 1; last = c
    }
    return n
  }

  nonisolated func byteCount(_ tag: UInt8) -> Int {
    chunks.count { $0 == tag }
  }
}

@OcaConnection
private func makeConnection() -> ChunkedWriteConnection {
  ChunkedWriteConnection(options: Ocp1ConnectionOptions())
}

private func pdu(_ tag: UInt8, count: Int = 8) -> Data {
  Data(repeating: tag, count: count)
}

private func waitUntil(
  _ condition: @Sendable () -> Bool,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  while !condition(), ContinuousClock.now < deadline {
    await Task.yield()
  }
  XCTAssertTrue(condition(), "condition never became true", file: file, line: line)
}

final class WriteSerialisationTests: XCTestCase {
  /// Submits one writer at a time, each confirmed to have reached the queue before the next
  /// starts. Staggered sleeps cannot order tasks reliably, and then submission order — the
  /// thing under test — is not defined.
  private func enqueueInOrder(
    on connection: ChunkedWriteConnection,
    tags: [UInt8],
    pduSize: Int
  ) async -> [Task<Void, Never>] {
    let queue = await connection.writeQueue
    var writers = [Task<Void, Never>]()
    for (i, tag) in tags.enumerated() {
      writers.append(Task { try? await connection.sendMessagePduData(pdu(tag, count: pduSize)) })
      if i == 0 {
        await waitUntil { connection.didEnterWrite }
        continue
      }
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while await queue.pending < i, ContinuousClock.now < deadline {
        await Task.yield()
      }
      let depth = await queue.pending
      XCTAssertEqual(depth, i, "writer \(i) did not reach the queue")
    }
    return writers
  }

  private func sendConcurrently(
    on connection: ChunkedWriteConnection,
    tags: [UInt8]
  ) async {
    await withTaskGroup(of: Void.self) { group in
      for tag in tags {
        group.addTask {
          try? await connection.sendMessagePduData(pdu(tag))
        }
      }
    }
  }

  /// Guards the test below: with the queue bypassed the PDUs must be seen to interleave,
  /// otherwise that assertion would hold for any implementation.
  func testBypassingTheQueueInterleavesPdus() async throws {
    let connection = await makeConnection()
    connection.datagram = true

    await sendConcurrently(on: connection, tags: [0xAA, 0xBB])

    let peak = connection.maxInFlight
    XCTAssertEqual(peak, 2, "writers never overlapped; the serialised case proves nothing")
    XCTAssertGreaterThan(connection.runs, 2, "bytes did not interleave without the queue")
  }

  func testWriteQueueSerialisesStreamPdus() async throws {
    let connection = await makeConnection()

    await sendConcurrently(on: connection, tags: [0xAA, 0xBB, 0xCC, 0xDD])

    let peak = connection.maxInFlight
    XCTAssertEqual(peak, 1, "\(peak) writers were in the transport at once")
    XCTAssertEqual(connection.runs, 4, "PDUs interleaved despite the queue")
    XCTAssertEqual(connection.chunks.count, 32)
  }

  /// Writers that queue behind an occupied transport must drain in submission order.
  /// `runs` alone cannot catch reordering: any permutation of whole PDUs yields one run each.
  func testWriteQueuePreservesSubmissionOrder() async throws {
    let connection = await makeConnection()
    connection.holdFirstWrite = .milliseconds(600)
    connection.midWritePause = .milliseconds(5)

    let tags: [UInt8] = [0xA0, 0xA1, 0xA2, 0xA3]
    let writers = await enqueueInOrder(on: connection, tags: tags, pduSize: 8)
    for writer in writers { _ = await writer.value }

    let expected = tags.flatMap { Array(repeating: $0, count: 8) }
    XCTAssertEqual(connection.chunks, expected, "PDUs were reordered or interleaved")
  }

  /// A backlog deep enough to compact the waiter array must still drain in order.
  func testDeepBacklogDrainsInOrder() async throws {
    let connection = await makeConnection()
    connection.holdFirstWrite = .milliseconds(700)

    let tags = (0..<64).map { UInt8($0) }
    let writers = await enqueueInOrder(on: connection, tags: tags, pduSize: 2)
    for writer in writers { _ = await writer.value }

    let expected = tags.flatMap { [$0, $0] }
    XCTAssertEqual(connection.chunks, expected, "deep backlog reordered or interleaved")
  }

  /// A PDU cancelled before its first byte is dropped whole. Emitting a fragment would
  /// desync framing for every writer behind it on the connection.
  func testCancellingAQueuedWriteEmitsNoBytes() async throws {
    let connection = await makeConnection()
    connection.holdFirstWrite = .milliseconds(600)
    connection.midWritePause = .milliseconds(50)

    let first = Task { try await connection.sendMessagePduData(pdu(0xAA)) }
    await waitUntil { connection.didEnterWrite }

    let queued = Task { try await connection.sendMessagePduData(pdu(0xBB)) }
    try await Task.sleep(for: .milliseconds(100))
    queued.cancel()
    _ = try? await queued.value
    _ = try? await first.value
    try? await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(connection.byteCount(0xBB), 0, "a cancelled queued write emitted a fragment")
    XCTAssertEqual(connection.byteCount(0xAA), 8, "the in-flight write was truncated")
  }

  /// Once a write has begun it must finish: stream backends resume from an offset, so
  /// aborting midway would leave half a PDU on the wire.
  func testCancellingAnInFlightWriteStillCompletesThePdu() async throws {
    let connection = await makeConnection()
    connection.midWritePause = .milliseconds(400)

    let write = Task { try await connection.sendMessagePduData(pdu(0xAA)) }
    await waitUntil { connection.didEnterWrite }
    write.cancel()
    _ = try? await write.value
    try? await Task.sleep(for: .milliseconds(700))

    XCTAssertEqual(connection.byteCount(0xAA), 8, "cancellation truncated an in-flight PDU")
  }
}
