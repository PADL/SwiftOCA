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
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

/// A block that can answer `GetSignalPathsRecursive` as a device lacking it would.
private final class ScriptedBlock: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot> {
  var recursiveStatus: OcaStatus?
  var methodIDs = [OcaMethodID]()

  func set(recursiveStatus: OcaStatus) {
    self.recursiveStatus = recursiveStatus
  }

  override func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    methodIDs.append(command.methodID)
    if command.methodID == SwiftOCA.OcaBlock.Methods.getSignalPathsRecursive.methodID,
       let recursiveStatus
    {
      throw Ocp1Error.status(recursiveStatus)
    }
    return try await super.handleCommand(command, from: controller)
  }
}

private func signalPath(_ role: String) -> OcaSignalPath {
  let port = OcaPort(owner: 1, id: OcaPortID(direction: .output, index: 1), role: role)
  return OcaSignalPath(sourcePort: port, sinkPort: port)
}

private func roles(_ signalPaths: OcaMap<OcaUint16, OcaSignalPath>) -> [String] {
  signalPaths.keys.sorted().map { signalPaths[$0]!.sourcePort.role }
}

/// `GetSignalPathsRecursive` on a nested tree, and the fallback for a device without it.
final class SignalPathsRecursiveTests: XCTestCase {
  private var device: OcaDevice!
  private var endpointTask: Task<(), Never>!
  private var outer: ScriptedBlock!
  private var gain: SwiftOCADevice.OcaGain!

  private func makeBlock(
    objectNumber: OcaONo,
    in container: ScriptedBlock? = nil,
    _ roles: [String]
  ) async throws -> ScriptedBlock {
    let block = try await ScriptedBlock(
      objectNumber: objectNumber,
      role: "Block\(objectNumber)",
      deviceDelegate: device,
      addToRootBlock: container == nil
    )
    try await container?.add(actionObject: block)
    for role in roles {
      _ = try await block.add(signalPath: signalPath(role))
    }
    return block
  }

  /// `outer` holds a gain and two blocks, one deeper, numbered against their nesting.
  private func makeTree() async throws {
    device = OcaDevice()
    try await device.initializeDefaultObjects()
    outer = try await makeBlock(objectNumber: 0x12000, ["outer1", "gone", "outer3"])
    try await outer.delete(signalPathAt: 2)
    gain = try await SwiftOCADevice.OcaGain(
      role: "Gain",
      deviceDelegate: device,
      addToRootBlock: false
    )
    try await outer.add(actionObject: gain)
    let inner = try await makeBlock(objectNumber: 0x13000, in: outer, ["inner"])
    _ = try await makeBlock(objectNumber: 0x11000, in: inner, ["deepest"])
    _ = try await makeBlock(objectNumber: 0x14000, in: outer, [])
  }

  private func makeProxy(controlProtocol: OcaControlProtocol = .ocp1) async throws
    -> SwiftOCA.OcaBlock
  {
    let endpoint = try await OcaLocalDeviceEndpoint(device: device, controlProtocol: controlProtocol)
    endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(
      endpoint,
      options: OcaConnectionOptions(flags: [], controlProtocol: controlProtocol)
    )
    try await connection.connect()
    return try await connection.resolve(object: outer.objectIdentification)
  }

  override func tearDown() async throws {
    endpointTask?.cancel()
  }

  private static let expectedRoles = ["deepest", "outer1", "outer3", "inner"]

  func testTheDeviceRenumbersAcrossBlocks() async throws {
    try await makeTree()
    let signalPaths = try await makeProxy().getSignalPathsRecursive()
    XCTAssertEqual(signalPaths.keys.sorted(), [1, 2, 3, 4])
    XCTAssertEqual(roles(signalPaths), Self.expectedRoles)
  }

  func testTheDeviceAnswersOverOcp2() async throws {
    try await makeTree()
    let signalPaths = try await makeProxy(controlProtocol: .ocp2).getSignalPathsRecursive()
    XCTAssertEqual(roles(signalPaths), Self.expectedRoles)
  }

  func testAnInnerBlockAnswersForItself() async throws {
    try await makeTree()
    let proxy = try await makeProxy()
    let inner: SwiftOCA.OcaBlock = try await proxy.connectionDelegate!.resolve(
      object: device.objects[0x13000]!.objectIdentification
    )
    let signalPaths = try await inner.getSignalPathsRecursive()
    XCTAssertEqual(roles(signalPaths), ["deepest", "inner"])
  }

  func testTheFallbackMatchesTheDeviceOnAMissingMethod() async throws {
    try await makeTree()
    let proxy = try await makeProxy()
    let expected = try await proxy.getSignalPathsRecursive()

    for status in [OcaStatus.notImplemented, .badMethod] {
      await outer.set(recursiveStatus: status)
      let signalPaths = try await proxy.resolveSignalPathsRecursive()
      XCTAssertEqual(signalPaths, expected)
    }
  }

  func testOtherFailuresDoNotFallBack() async throws {
    try await makeTree()
    let proxy = try await makeProxy()
    await outer.set(recursiveStatus: .deviceError)
    do {
      _ = try await proxy.resolveSignalPathsRecursive()
      XCTFail("expected deviceError")
    } catch Ocp1Error.status(.deviceError) {}
    let methodIDs = await outer.methodIDs
    XCTAssertFalse(methodIDs.contains(OcaMethodID("3.9")))
  }

  func testMoreThanAMapHoldsIsABufferOverflow() throws {
    let block = OcaMap(uniqueKeysWithValues: (0..<40000).map { (OcaUint16($0), signalPath("")) })
    let merged = try OcaMap(mergingBlocks: [1: block])
    XCTAssertEqual(merged.count, 40000)
    XCTAssertThrowsError(try OcaMap(mergingBlocks: [1: block, 2: block])) {
      XCTAssertEqual($0 as? Ocp1Error, .status(.bufferOverflow))
    }
  }

  func testAnAnswerLargerThanAPduIsABufferOverflow() async throws {
    try await makeTree()
    let status = await Self.recursiveStatus(of: outer, on: device, maximumSendPduSize: 100)
    XCTAssertEqual(status, .bufferOverflow)
    let enough = await Self.recursiveStatus(of: outer, on: device, maximumSendPduSize: 1500)
    XCTAssertEqual(enough, .ok)
  }

  /// The status of the method, for a controller on a packet transport.
  @OcaDevice
  private static func recursiveStatus(
    of block: ScriptedBlock,
    on device: OcaDevice,
    maximumSendPduSize: Int
  ) async -> OcaStatus? {
    typealias Endpoint = DatagramProxyDeviceEndpoint<Int>
    let (input, _) = AsyncStream<Endpoint.PeerMessagePDU>.makeStream()
    let (_, output) = AsyncStream<Endpoint.PeerMessagePDU>.makeStream()
    guard let endpoint = try? await Endpoint(
      maximumSendPduSize: maximumSendPduSize,
      inputStream: input,
      outputStream: output,
      device: OcaDevice()
    ) else { return nil }
    return await device.handleCommand(
      Ocp1Command(
        handle: 1,
        targetONo: block.objectNumber,
        methodID: SwiftOCA.OcaBlock.Methods.getSignalPathsRecursive.methodID,
        parameters: OcaParameters()
      ),
      from: DatagramProxyController(with: 1, endpoint: endpoint)
    ).statusCode
  }
}
