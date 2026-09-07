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
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

/// A controller and a device speaking OCP.2 in-process.
final class Ocp2LoopbackTests: XCTestCase {
  private struct Harness {
    let device: OcaDevice
    let endpoint: OcaLocalDeviceEndpoint
    let connection: OcaLocalConnection
    let endpointTask: Task<(), Never>

    func tearDown() async {
      try? await connection.disconnect()
      endpointTask.cancel()
    }
  }

  /// A vector property is one wrapper standing in for two properties, so its OCP.2
  /// parameters are named after the vector record's fields. Regression: the storage
  /// borrowed OcaRoot's property 1.1 and named them `ClassID`.
  func testVectorPropertyRoundTripsOverOcp2() async throws {
    let harness = try await makeHarness()
    defer { Task { await harness.tearDown() } }

    let matrixONo: OcaONo = 0x0001_0200
    _ = try await SwiftOCADevice.OcaMatrix<SwiftOCADevice.OcaRoot>(
      rows: 4,
      columns: 2,
      objectNumber: matrixONo,
      role: "Matrix",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    let matrix: SwiftOCA.OcaMatrix = try await harness.connection.resolve(
      object: OcaObjectIdentification(
        oNo: matrixONo,
        classIdentification: SwiftOCA.OcaMatrix.classIdentification
      )
    )

    // `size` is deliberately not exercised: OcaMatrix.GetSize returns the model's
    // six-field MatrixSize while the client property is a two-field vector, which is
    // a structural divergence from AES70-2A rather than a naming one.
    // both directions must name the OCP.2 parameters after the vector's own fields
    // (X, Y), not after some other property the storage borrowed an ID from
    let xy = try await matrix.$currentXY._getValue(matrix, flags: [])
    XCTAssertEqual(xy.x, 0xFFFF) // the wildcard coordinate a fresh matrix starts at
    XCTAssertEqual(xy.y, 0xFFFF)

    // the type-erased setter was a stub before; it now goes through the same
    // `setValueIfMutable` naming path the wrapper's own setter uses
    try await matrix.$currentXY._setValue(matrix, OcaVector2D<OcaMatrixCoordinate>(x: 1, y: 1))
    let updated = try await matrix.$currentXY._getValue(matrix, flags: [])
    XCTAssertEqual(updated.x, 1)
    XCTAssertEqual(updated.y, 1)
  }

  private func makeHarness() async throws -> Harness {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device, controlProtocol: .ocp2)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(
      endpoint,
      options: Ocp1ConnectionOptions(controlProtocol: .ocp2)
    )
    try await connection.connect()
    return Harness(device: device, endpoint: endpoint, connection: connection, endpointTask: endpointTask)
  }

  private func wait(
    timeout: Duration = .seconds(5),
    until condition: @Sendable () async -> Bool
  ) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if await condition() { return true }
      try? await Task.sleep(for: .milliseconds(25))
    }
    return await condition()
  }

  func testConnectsAndReadsManagers() async throws {
    let harness = try await makeHarness()
    defer { Task { await harness.tearDown() } }

    XCTAssertEqual(harness.connection.controlProtocol, .ocp2)
    let controllers = await harness.endpoint.controllers
    XCTAssertEqual(controllers.count, 1)
    let controllerProtocol = await controllers.first?.controlProtocol
    XCTAssertEqual(controllerProtocol, .ocp2)

    // GetClassIdentification (1.1): a parameter record response
    let identification = try await harness.connection.deviceManager.getClassIdentification()
    XCTAssertEqual(identification.classID, SwiftOCA.OcaDeviceManager.classID)

    // GetRole (1.5): a named scalar response
    let role = try await harness.connection.deviceManager.$role._getValue(
      harness.connection.deviceManager,
      flags: []
    )
    XCTAssertFalse(role.isEmpty)

    // GetLockable (1.2): a named boolean response
    let lockable = try await harness.connection.rootBlock.$lockable._getValue(
      harness.connection.rootBlock,
      flags: []
    )
    XCTAssertTrue(lockable)

    // an unknown object number produces a status, not a transport error
    do {
      _ = try await harness.connection.getClassIdentification(objectNumber: 0x7FFF_FFFF)
      XCTFail("expected badONo")
    } catch Ocp1Error.status(.badONo) {}
  }

  func testBoundedPropertyGetAndSet() async throws {
    let harness = try await makeHarness()
    defer { Task { await harness.tearDown() } }

    let deviceGain = try await SwiftOCADevice.OcaGain(
      objectNumber: 0x0001_0010,
      role: "Master Gain",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    let clientGain: SwiftOCA.OcaGain = try await harness.connection.resolve(
      object: OcaObjectIdentification(
        oNo: 0x0001_0010,
        classIdentification: SwiftOCA.OcaGain.classIdentification
      )
    )

    await { @OcaDevice in deviceGain.gain = OcaBoundedPropertyValue(value: -6, in: -100...12) }()

    // GetGain returns Gain, MinGain, MaxGain as separate parameters
    let gain = try await clientGain.$gain._getValue(clientGain, flags: [])
    XCTAssertEqual(gain.value, -6)
    XCTAssertEqual(gain.minValue, -100)
    XCTAssertEqual(gain.maxValue, 12)

    // SetGain takes a single Gain parameter
    try await clientGain.$gain._setValue(clientGain, OcaBoundedPropertyValue<OcaDB>(value: -3.5, in: -100...12))
    let deviceValue = await { @OcaDevice in deviceGain.gain.value }()
    XCTAssertEqual(deviceValue, -3.5)
  }

  func testFindActionObjectsByRole() async throws {
    let harness = try await makeHarness()
    defer { Task { await harness.tearDown() } }

    _ = try await SwiftOCADevice.OcaGain(
      objectNumber: 0x0001_0011,
      role: "Master Gain",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )

    let results = try await harness.connection.rootBlock.find(
      actionObjectsByRole: "Master Gain",
      nameComparisonType: .exact,
      resultFlags: [.oNo, .classIdentification, .role]
    )
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.oNo, 0x0001_0011)
    XCTAssertEqual(results.first?.classIdentification?.classID, SwiftOCA.OcaGain.classID)
    XCTAssertEqual(results.first?.role, "Master Gain")
    XCTAssertNil(results.first?.label)
  }

  func testPropertyChangeNotification() async throws {
    let harness = try await makeHarness()
    defer { Task { await harness.tearDown() } }

    let deviceBlock = try await SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>(
      objectNumber: 0x0001_0020,
      role: "Control",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    let clientBlock: SwiftOCA.OcaBlock = try await harness.connection.resolve(
      object: OcaObjectIdentification(
        oNo: 0x0001_0020,
        classIdentification: SwiftOCA.OcaBlock.classIdentification
      )
    )

    await clientBlock.$label.subscribe(clientBlock)
    let subscribed = await wait { (try? await clientBlock.isSubscribed) == true }
    XCTAssertTrue(subscribed)

    // the device holds an EV2 subscription for this OCP.2 controller
    let controllers = await harness.endpoint.controllers
    let controller = try XCTUnwrap(controllers.first as? OcaLocalController)
    let subscriptions = await controller.subscriptions[0x0001_0020] ?? []
    XCTAssertEqual(subscriptions.count, 1)
    XCTAssertEqual(subscriptions.first?.version, .ev2)

    await { @OcaDevice in deviceBlock.label = "changed" }()
    let observed = await wait {
      if case let .success(value) = clientBlock.$label.currentValue { return value == "changed" }
      return false
    }
    XCTAssertTrue(observed, "property did not observe the device change over OCP.2")

    try await clientBlock.unsubscribe()
    let unsubscribed = await wait { await controller.subscriptions[0x0001_0020]?.isEmpty ?? true }
    XCTAssertTrue(unsubscribed)
  }

  func testEv1SubscriptionsAreRefused() async throws {
    let harness = try await makeHarness()
    defer { Task { await harness.tearDown() } }

    do {
      try await harness.connection.subscriptionManager.addSubscription(
        event: OcaEvent(emitterONo: OcaRootBlockONo, eventID: OcaPropertyChangedEventID),
        subscriber: OcaMethod(oNo: 1055, methodID: OcaMethodID("1.1")),
        subscriberContext: OcaBlob(),
        notificationDeliveryMode: .normal,
        destinationInformation: OcaNetworkAddress()
      )
      XCTFail("EV1 subscription accepted over OCP.2")
    } catch Ocp1Error.status(.notImplemented) {}
  }

  func testLocking() async throws {
    let harness = try await makeHarness()
    defer { Task { await harness.tearDown() } }

    let deviceBlock = try await SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>(
      objectNumber: 0x0001_0030,
      role: "Lockable",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    let clientBlock: SwiftOCA.OcaBlock = try await harness.connection.resolve(
      object: OcaObjectIdentification(
        oNo: 0x0001_0030,
        classIdentification: SwiftOCA.OcaBlock.classIdentification
      )
    )

    try await clientBlock.lockReadOnly()
    let lockState = try await clientBlock.$lockState._getValue(clientBlock, flags: [])
    XCTAssertEqual(lockState, .lockNoWrite)
    let deviceLocked = await { @OcaDevice in deviceBlock.lockState.lockState }()
    XCTAssertEqual(deviceLocked, .lockNoWrite)
    try await clientBlock.unlock()
  }
}
#endif

#if NonEmbeddedBuild
/// The controller-side JSON export is the OCP.2 representation of the object.
final class Ocp2JsonExportTests: XCTestCase {
  func testJsonValueMatchesOcp2Marshaling() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device, controlProtocol: .ocp2)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    defer { endpointTask.cancel() }
    let connection = await OcaLocalConnection(
      endpoint,
      options: Ocp1ConnectionOptions(controlProtocol: .ocp2)
    )
    try await connection.connect()
    defer { Task { try? await connection.disconnect() } }

    let deviceGain = try await SwiftOCADevice.OcaGain(
      objectNumber: 0x0001_0040,
      role: "Master Gain",
      deviceDelegate: device,
      addToRootBlock: true
    )
    await { @OcaDevice in
      deviceGain.gain = OcaBoundedPropertyValue(value: -6, in: -.infinity...12)
      deviceGain.label = "Main"
    }()

    let clientGain: SwiftOCA.OcaGain = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: 0x0001_0040,
        classIdentification: SwiftOCA.OcaGain.classIdentification
      )
    )
    let json = await clientGain.jsonObject

    // identity, as OCP.2 marshals it
    XCTAssertEqual(json["ObjectNumber"] as? Int, 0x0001_0040)
    XCTAssertEqual(json["ClassID"] as? [Int], [1, 1, 1, 5])
    XCTAssertEqual(json["ClassVersion"] as? Int, Int(SwiftOCA.OcaGain.classVersion))
    // a bounded property takes the shape of its OCP.2 getter response
    XCTAssertEqual(json["Gain"] as? Double, -6)
    XCTAssertEqual(json["MinGain"] as? String, "-Infinity")
    XCTAssertEqual(json["MaxGain"] as? Double, 12)
    // plain properties under their wire names
    XCTAssertEqual(json["Role"] as? String, "Master Gain")
    XCTAssertEqual(json["Label"] as? String, "Main")
    XCTAssertEqual(json["Lockable"] as? Bool, true)
    // ONo is what the model calls object-number parameters, not this property
    XCTAssertNil(json["ONo"])
    // OCA 1.5B's spelling, not the 2023 model's
    XCTAssertNil(json["minGain"])

    // and it serialises
    XCTAssertTrue(JSONSerialization.isValidJSONObject(json))
  }
}
#endif
