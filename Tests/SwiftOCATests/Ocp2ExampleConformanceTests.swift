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
import XCTest

/// Runs the AES70-4 supporting-file example PDUs through the OCP.2 codec, read from
/// disk rather than transcribed so that a revised draft is picked up: every example
/// must decode and re-encode, and every X-series (malformed) example must be
/// rejected. Point `AES70_4_EXAMPLES` at the supporting-files directory to run it,
/// and set `AES70_4_OUT` to also write each re-encoded PDU there for validation
/// against the Annex A schema. Skipped otherwise.
final class Ocp2ExampleConformanceTests: XCTestCase {
  func testStandardExamples() throws {
    guard let path = ProcessInfo.processInfo.environment["AES70_4_EXAMPLES"] else {
      throw XCTSkip("set AES70_4_EXAMPLES to the AES70-4 supporting-files directory")
    }
    let directory = URL(fileURLWithPath: path)
    let out = ProcessInfo.processInfo.environment["AES70_4_OUT"].map { URL(fileURLWithPath: $0) }
    let files = try FileManager.default.contentsOfDirectory(atPath: path)
      .filter { $0.hasPrefix("example-") && $0.hasSuffix(".json") }
      .sorted()
    XCTAssertFalse(files.isEmpty, "no examples in \(path)")

    for file in files {
      let data = try Data(contentsOf: directory.appendingPathComponent(file))
      let malformed = file.hasPrefix("example-X")
      do {
        let (type, messages) = try OcaControlProtocol.ocp2.decodePdu(data)
        guard !malformed else {
          XCTFail("\(file): malformed example was accepted")
          continue
        }
        let encoded = try OcaControlProtocol.ocp2.encodePdu(messages, type: type)
        if let out {
          try encoded.write(to: out.appendingPathComponent(file))
        }
        print("CONFORMANCE PASS \(file): \(messages.count) message(s) of \(type)")
      } catch {
        if malformed {
          print("CONFORMANCE PASS \(file): rejected (\(error))")
        } else {
          XCTFail("\(file): \(error)")
        }
      }
    }
  }
}
#endif
