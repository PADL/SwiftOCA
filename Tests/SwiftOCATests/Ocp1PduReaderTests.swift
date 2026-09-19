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
import XCTest

final class Ocp1PduReaderTests: XCTestCase {
  private actor Feed {
    private var chunks: [Data]
    private(set) var readCount = 0

    init(_ chunks: [Data]) {
      self.chunks = chunks
    }

    func read() -> Data {
      readCount += 1
      return chunks.isEmpty ? Data() : chunks.removeFirst()
    }
  }

  private func pdu(bodySize: Int = 0) -> Data {
    let totalSize = OcaConnection.MinimumPduSize + bodySize
    var bytes: [UInt8] = [Ocp1SyncValue, 0, 1]
    bytes += withUnsafeBytes(of: UInt32(totalSize - 1).bigEndian) { Array($0) }
    bytes += [OcaMessageType.ocaCmd.rawValue, 0, 0]
    bytes += [UInt8](repeating: 0xA5, count: bodySize)
    return Data(bytes)
  }

  private func assertError(
    _ expected: Ocp1Error,
    operation: () async throws -> (),
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      try await operation()
      XCTFail("expected \(expected)", file: file, line: line)
    } catch let error as Ocp1Error {
      XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
      XCTFail("expected Ocp1Error, got \(error)", file: file, line: line)
    }
  }

  func testStreamOverreadKeepsCompleteSuccessorWithoutAnotherRead() async throws {
    let first = pdu(bodySize: 3)
    let second = pdu(bodySize: 7)
    let feed = Feed([first + second])
    let reader = OcaControlProtocol.ocp1.makeReader(
      preservesPduBoundaries: false,
      maximumPduSize: 1024
    )

    let actualFirst = try await reader.nextPdu { _, _ in await feed.read() }
    let actualSecond = try await reader.nextPdu { _, _ in await feed.read() }
    let readCount = await feed.readCount
    XCTAssertEqual(actualFirst, first)
    XCTAssertEqual(actualSecond, second)
    XCTAssertEqual(readCount, 1)
  }

  func testStreamPduSplitAtEveryByte() async throws {
    let expected = pdu(bodySize: 11)
    let feed = Feed(expected.map { Data([$0]) })
    let reader = OcaControlProtocol.ocp1.makeReader(
      preservesPduBoundaries: false,
      maximumPduSize: expected.count
    )

    let actual = try await reader.nextPdu { _, _ in await feed.read() }
    XCTAssertEqual(actual, expected)
  }

  func testTruncatedPacketDoesNotConsumeFollowingPacket() async throws {
    let valid = pdu(bodySize: 5)
    let feed = Feed([valid.dropLast(), valid])
    let reader = OcaControlProtocol.ocp1.makeReader(
      preservesPduBoundaries: true,
      maximumPduSize: 1024
    )

    await assertError(.invalidPduSize) {
      _ = try await reader.nextPdu { _, _ in await feed.read() }
    }
    let readCount = await feed.readCount
    let next = try await reader.nextPdu { _, _ in await feed.read() }
    XCTAssertEqual(readCount, 1)
    XCTAssertEqual(next, valid)
  }

  func testPacketWithTrailingBytesIsRejected() async {
    let packet = pdu() + Data([0xFF])
    let reader = OcaControlProtocol.ocp1.makeReader(
      preservesPduBoundaries: true,
      maximumPduSize: 1024
    )

    await assertError(.invalidPduSize) {
      _ = try await reader.nextPdu { _, _ in packet }
    }
  }

  func testEmptyPacketIsIgnoredRatherThanEndOfStream() async throws {
    let expected = pdu(bodySize: 3)
    let feed = Feed([Data(), Data(), expected])
    let reader = OcaControlProtocol.ocp1.makeReader(
      preservesPduBoundaries: true,
      maximumPduSize: 1024
    )

    let actual = try await reader.nextPdu { _, _ in await feed.read() }
    let readCount = await feed.readCount
    XCTAssertEqual(actual, expected)
    XCTAssertEqual(readCount, 3)
  }

  func testMaximumPduSizeIncludesSyncByte() async throws {
    let maximumPduSize = 64
    let exact = pdu(bodySize: maximumPduSize - OcaConnection.MinimumPduSize)
    let accepted = OcaControlProtocol.ocp1.makeReader(
      preservesPduBoundaries: true,
      maximumPduSize: maximumPduSize
    )
    let actual = try await accepted.nextPdu { _, _ in exact }
    XCTAssertEqual(actual, exact)

    let tooLarge = pdu(bodySize: maximumPduSize - OcaConnection.MinimumPduSize + 1)
    let rejected = OcaControlProtocol.ocp1.makeReader(
      preservesPduBoundaries: true,
      maximumPduSize: maximumPduSize
    )
    await assertError(.invalidPduSize) {
      _ = try await rejected.nextPdu { _, _ in tooLarge }
    }
  }
}
