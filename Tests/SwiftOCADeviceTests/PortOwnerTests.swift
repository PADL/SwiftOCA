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

/// A port's owner is the worker that has it, whichever block holds the signal path.
final class PortOwnerTests: XCTestCase {
  private var device: OcaDevice!
  private var block: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaWorker>!
  private var gain: SwiftOCADevice.OcaGain!
  private var mute: SwiftOCADevice.OcaMute!

  override func setUp() async throws {
    device = OcaDevice()
    try await device.initializeDefaultObjects()
    block = try await SwiftOCADevice.OcaBlock(
      objectNumber: 0x12000,
      role: "Block",
      deviceDelegate: device,
      addToRootBlock: false
    )
    gain = try await SwiftOCADevice.OcaGain(
      role: "Gain",
      deviceDelegate: device,
      addToRootBlock: false
    )
    mute = try await SwiftOCADevice.OcaMute(
      role: "Mute",
      deviceDelegate: device,
      addToRootBlock: false
    )
    try await block.add(actionObject: gain)
    try await block.add(actionObject: mute)
  }

  private func signalPath(at index: OcaUint16) async throws -> OcaSignalPath {
    let signalPath = await block.signalPaths[index]
    return try XCTUnwrap(signalPath)
  }

  func testMembersOwnTheirPorts() async throws {
    try await block.connect(gain, to: mute, width: 2)

    for index: OcaUint16 in 1...2 {
      let signalPath = try await signalPath(at: index)
      XCTAssertEqual(signalPath.sourcePort.owner, gain.objectNumber)
      XCTAssertEqual(signalPath.sinkPort.owner, mute.objectNumber)
    }
    let gainPorts = await gain.ports
    let mutePorts = await mute.ports
    XCTAssertEqual(gainPorts.map(\.owner), [gain.objectNumber, gain.objectNumber])
    XCTAssertEqual(mutePorts.map(\.owner), [mute.objectNumber, mute.objectNumber])
  }

  func testABlockOwnsItsOwnPorts() async throws {
    let member: SwiftOCADevice.OcaWorker = gain
    try await block.connect(block, to: member)
    try await block.connect(member, to: block)

    let toMember = try await signalPath(at: 1)
    XCTAssertEqual(toMember.sourcePort.owner, block.objectNumber)
    XCTAssertEqual(toMember.sinkPort.owner, gain.objectNumber)

    let toBlock = try await signalPath(at: 2)
    XCTAssertEqual(toBlock.sourcePort.owner, gain.objectNumber)
    XCTAssertEqual(toBlock.sinkPort.owner, block.objectNumber)

    let blockPorts = await block.ports
    XCTAssertEqual(blockPorts.map(\.owner), [block.objectNumber, block.objectNumber])
  }

  func testDeletingAPathLeavesItsPortsWithTheirOwners() async throws {
    try await block.connect(gain, to: mute)
    try await block.delete(signalPathAt: 1)

    let signalPaths = await block.signalPaths
    XCTAssertTrue(signalPaths.isEmpty)
    let gainPorts = await gain.ports
    let mutePorts = await mute.ports
    XCTAssertEqual(gainPorts.map(\.owner), [gain.objectNumber])
    XCTAssertEqual(mutePorts.map(\.owner), [mute.objectNumber])
  }

  func testRenamingAPortKeepsItsOwner() async throws {
    try await block.connect(gain, to: mute)

    let id = await gain.ports[0].id
    try await gain.setName("Renamed", ofPort: id)

    let port = await gain.ports[0]
    XCTAssertEqual(port.owner, gain.objectNumber)
    XCTAssertEqual(port.role, "Renamed")
  }
}
