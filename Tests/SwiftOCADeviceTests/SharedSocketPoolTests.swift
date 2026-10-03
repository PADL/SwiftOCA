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

#if os(macOS) || os(iOS)

import FlyingFox
import FlyingSocks
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

@OcaConnectionActor
private func makeConnection(path: String) throws -> OcaFlyingSocksStreamConnection {
  // no automatic reconnect, so a dropped connection stays dropped
  try OcaFlyingSocksStreamConnection(path: path, options: OcaConnectionOptions(flags: []))
}

/// FlyingSocks connections share one socket pool, so disconnecting one connection must
/// neither drop the others nor leave the pool unusable for an immediate reconnect.
final class SharedSocketPoolTests: XCTestCase {
  private func assertResponds(
    _ connection: OcaConnection,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    // a round trip; resolveActionObjects() can answer from the cache
    do {
      let classID = try await connection.rootBlock.getClassIdentification()
      XCTAssertEqual(classID, SwiftOCA.OcaBlock.classIdentification, message, file: file, line: line)
    } catch {
      XCTFail("\(message): \(error)", file: file, line: line)
    }
  }

  private func withEndpoint(_ body: (_ path: String) async throws -> ()) async throws {
    let path = "/tmp/swiftoca-\(UUID().uuidString.prefix(8)).sock"
    defer { unlink(path) }

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaFlyingSocksStreamDeviceEndpoint(path: path, device: device)
    let endpointTask = Task { try await endpoint.run() }
    defer { endpointTask.cancel() }
    try await Task.sleep(for: .milliseconds(200))
    try await body(path)
  }

  func testDisconnectingOneConnectionLeavesOthersAndReconnectWorking() async throws {
    try await withEndpoint { path in

    let a = try await makeConnection(path: path)
    let b = try await makeConnection(path: path)
    try await a.connect()
    try await b.connect()
    await assertResponds(a, "a before disconnect")
    await assertResponds(b, "b before disconnect")

    for round in 0..<5 {
      try await a.disconnect()
      do {
        try await a.connect()
      } catch {
        XCTFail("round \(round): reconnect failed: \(error)")
        break
      }
      await assertResponds(a, "round \(round): a after reconnect")
      await assertResponds(b, "round \(round): b after a disconnected")
      let bConnected = await b.isConnected
      XCTAssertTrue(bConnected, "round \(round): b was dropped when a disconnected")
    }

    try await a.disconnect()
    try await b.disconnect()
    }
  }

  /// Connects arriving together, just after a disconnect, must share one prepared pool.
  func testConcurrentConnectsAfterDisconnectAllSucceed() async throws {
    try await withEndpoint { path in
      for round in 0..<5 {
        let first = try await makeConnection(path: path)
        try await first.connect()
        try await first.disconnect()

        let failures = await withTaskGroup(of: String?.self) { group in
          for i in 0..<8 {
            group.addTask {
              do {
                let connection = try await makeConnection(path: path)
                try await connection.connect()
                _ = try await connection.rootBlock.getClassIdentification()
                try await connection.disconnect()
                return nil
              } catch {
                return "connection \(i): \(error)"
              }
            }
          }
          var failures = [String]()
          for await failure in group { if let failure { failures.append(failure) } }
          return failures
        }
        XCTAssertEqual(failures, [], "round \(round)")
      }
    }
  }
}

#endif
