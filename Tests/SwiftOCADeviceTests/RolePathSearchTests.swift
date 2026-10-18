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
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

/// `findActionObjectsByRolePath` finds what a role path names, searching from the block it
/// is sent to.
final class RolePathSearchTests: XCTestCase {
  private actor Controller: OcaController {
    nonisolated var flags: OcaControllerFlags { [] }
    func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {}
  }

  private var device: OcaDevice!
  private let controller = Controller()
  private var outer: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>!
  private var inner: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>!
  private var outerGain: SwiftOCADevice.OcaGain!
  private var innerGain: SwiftOCADevice.OcaGain!
  private var rootGain: SwiftOCADevice.OcaGain!

  override func setUp() async throws {
    device = OcaDevice()
    try await device.initializeDefaultObjects()
    // Outer/Gain, Outer/Inner/Gain and a Gain in the root block share a role
    outer = try await SwiftOCADevice.OcaBlock(role: "Outer", deviceDelegate: device)
    inner = try await SwiftOCADevice.OcaBlock(
      role: "Inner",
      deviceDelegate: device,
      addToRootBlock: false
    )
    try await outer.add(actionObject: inner)
    outerGain = try await SwiftOCADevice.OcaGain(
      role: "Gain",
      deviceDelegate: device,
      addToRootBlock: false
    )
    try await outer.add(actionObject: outerGain)
    innerGain = try await SwiftOCADevice.OcaGain(
      role: "Gain",
      deviceDelegate: device,
      addToRootBlock: false
    )
    try await inner.add(actionObject: innerGain)
    rootGain = try await SwiftOCADevice.OcaGain(role: "Gain", deviceDelegate: device)
  }

  private func search(
    _ path: OcaNamePath,
    from block: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>? = nil
  ) async throws -> [OcaONo] {
    let rootBlock = await device.rootBlock!
    return try await (block ?? rootBlock).findActionObjectsByRolePath(
      searchPath: path,
      resultFlags: .oNo,
      from: controller
    ).compactMap(\.oNo)
  }

  func testEachPathNamesOneObject() async throws {
    let rootGain = try await search(["Gain"])
    let outerGain = try await search(["Outer", "Gain"])
    let innerGain = try await search(["Outer", "Inner", "Gain"])
    let inner = try await search(["Outer", "Inner"])
    XCTAssertEqual(rootGain, [self.rootGain.objectNumber])
    XCTAssertEqual(outerGain, [self.outerGain.objectNumber])
    XCTAssertEqual(innerGain, [self.innerGain.objectNumber])
    XCTAssertEqual(inner, [self.inner.objectNumber])
  }

  func testPathsAreRelativeToTheBlockSearched() async throws {
    let fromOuter = try await search(["Inner", "Gain"], from: outer)
    let gainOfOuter = try await search(["Gain"], from: outer)
    XCTAssertEqual(fromOuter, [innerGain.objectNumber])
    XCTAssertEqual(gainOfOuter, [outerGain.objectNumber])
  }

  func testPathsThatNameNothing() async throws {
    let empty = try await search([])
    let missing = try await search(["Outer", "Nothing"])
    let tooDeep = try await search(["Outer", "Gain", "Gain"])
    let skipping = try await search(["Inner", "Gain"])
    XCTAssertEqual(empty, [])
    XCTAssertEqual(missing, [])
    XCTAssertEqual(tooDeep, [])
    // a path starts at the block searched, so cannot skip a level
    XCTAssertEqual(skipping, [])
  }
}
