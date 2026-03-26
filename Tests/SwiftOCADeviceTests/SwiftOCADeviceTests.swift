//
// Copyright (c) 2023 PADL Software Pty Ltd
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

@OcaDevice
final class MyBooleanActuator: SwiftOCADevice.OcaBooleanActuator, OcaGroupPeerToPeerMember,
  @unchecked Sendable
{
  nonisolated(unsafe) weak var group: SwiftOCADevice.OcaGroup<MyBooleanActuator>?

  override class var classID: OcaClassID { OcaClassID(parent: super.classID, 65280) }

  func set(to value: Bool) async { setting = value }
}

final class _MyBooleanActuator: SwiftOCA.OcaBooleanActuator, @unchecked
Sendable {
  override class var classID: OcaClassID { OcaClassID(parent: super.classID, 65280) }
}

extension OcaGetPortNameParameters: Equatable {
  public static func == (lhs: OcaGetPortNameParameters, rhs: OcaGetPortNameParameters) -> Bool {
    lhs.portID == rhs.portID
  }
}

extension Ocp1Parameters: Equatable {
  public static func == (lhs: Ocp1Parameters, rhs: Ocp1Parameters) -> Bool {
    lhs.parameterData == rhs.parameterData && lhs.parameterCount == rhs.parameterCount
  }
}

extension Ocp1Command: Equatable {
  public static func == (lhs: SwiftOCA.Ocp1Command, rhs: SwiftOCA.Ocp1Command) -> Bool {
    lhs.commandSize == rhs.commandSize &&
      lhs.handle == rhs.handle &&
      lhs.targetONo == rhs.targetONo &&
      lhs.methodID == rhs.methodID &&
      lhs.parameters == rhs.parameters
  }
}

extension Character {
  var ascii: UInt8 {
    UInt8(unicodeScalars.first!.value)
  }
}

final class SwiftOCADeviceTests: XCTestCase {
  let testBlockONo: OcaONo = 10001
  let testGroupONo: OcaONo = 5001

  func testLoopbackDevice() async throws {
    try await OcaClassRegistry.shared.register(_MyBooleanActuator.self)

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)

    let testBlock = try await SwiftOCADevice
      .OcaBlock<MyBooleanActuator>(
        objectNumber: testBlockONo,
        deviceDelegate: device,
        addToRootBlock: true
      )
    let matrix = try await SwiftOCADevice
      .OcaMatrix<MyBooleanActuator>(
        rows: 4,
        columns: 2,
        deviceDelegate: device,
        addToRootBlock: true
      )

    let matrixMembers = await matrix.members
    for x in 0..<matrixMembers.nX {
      for y in 0..<matrixMembers.nY {
        let coordinate = OcaVector2D(x: OcaMatrixCoordinate(x), y: OcaMatrixCoordinate(y))
        let actuator = try await MyBooleanActuator(
          role: "Actuator \(x),\(y)",
          deviceDelegate: device,
          addToRootBlock: false
        )
        try await matrix.add(member: actuator, at: coordinate)
        try await testBlock.add(actionObject: actuator)
      }
    }

    let jsonSerializationExpectation =
      XCTestExpectation(description: "Ensure JSON serialization round-trips")
    let jsonObject = try await device.rootBlock.serialize()
    let jsonResultData = try JSONSerialization.data(withJSONObject: jsonObject)
    let decoded = try JSONSerialization.jsonObject(with: jsonResultData) as! [String: Any]
    XCTAssertEqual(decoded as NSDictionary, jsonObject as NSDictionary)
    jsonSerializationExpectation.fulfill()
    await fulfillment(of: [jsonSerializationExpectation], timeout: 1)

    let connection = await OcaLocalConnection(endpoint)
    let endpointTask = Task { try? await endpoint.run() }
    try await connection.connect()

    let deviceExpectation = XCTestExpectation(description: "Check device properties")
    var oNo = await connection.deviceManager.objectNumber
    XCTAssertEqual(oNo, OcaDeviceManagerONo)
    oNo = await connection.subscriptionManager.objectNumber
    XCTAssertEqual(oNo, OcaSubscriptionManagerONo)
    let path = await matrix.objectNumberPath
    Task { @OcaDevice in XCTAssertEqual(path, [matrix.objectNumber]) }
    deviceExpectation.fulfill()
    await fulfillment(of: [deviceExpectation], timeout: 1)

    let controllerExpectation =
      XCTestExpectation(description: "Check rootBlock controller properties")
    let members = try await connection.rootBlock.resolveActionObjects()
    let deviceMembers = await device.rootBlock.actionObjects
    XCTAssertEqual(members.map(\.objectNumber), deviceMembers.map(\.objectNumber))
    controllerExpectation.fulfill()

    await fulfillment(of: [controllerExpectation], timeout: 1)

    let controllerExpectation2 =
      XCTestExpectation(description: "Check test block controller properties")
    let clientTestBlock: SwiftOCA.OcaBlock = try await connection
      .resolve(object: OcaObjectIdentification(
        oNo: testBlockONo,
        classIdentification: SwiftOCA.OcaBlock.classIdentification
      ))
    XCTAssertNotNil(clientTestBlock)
    let resolvedClientTestBlockActionObjects = try await clientTestBlock.resolveActionObjects()
    let testBlockMembers = await testBlock.actionObjects
    XCTAssertEqual(
      resolvedClientTestBlockActionObjects.map(\.objectNumber),
      testBlockMembers.map(\.objectNumber)
    )
    controllerExpectation2.fulfill()

    await fulfillment(of: [controllerExpectation2], timeout: 1)

    let datasetParamStorageExpectation =
      XCTestExpectation(description: "Check dataset parameter storage provider")
    let basePath = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let storageProvider = try OcaFileDatasetStorageProvider(
      basePath: basePath,
      deviceDelegate: device
    )
    await device.setDatasetStorageProvider(storageProvider)
    let testDataset = try await connection.rootBlock.constructDataset(
      classID: SwiftOCA.OcaDataset.classID,
      name: "test",
      type: OcaParamDatasetMimeType,
      maxSize: 1024,
      initialContents: .init()
    )
    try await connection.rootBlock.store(currentParameterData: testDataset)
    // deregister to make sure we find it again, not the cached copy
    try await device.deregister(objectNumber: testDataset)
    try await connection.rootBlock.apply(paramDataset: testDataset)
    datasetParamStorageExpectation.fulfill()

    let datasetPatchStorageExpectation =
      XCTestExpectation(description: "Check dataset patch storage provider")
    let deviceManager = await device.deviceManager!
    let patchONo = try await deviceManager.storePatch(
      patchDatasetONo: nil,
      name: "global_patch",
      paramDatasetONos: [testDataset],
      controller: nil,
      createIfAbsent: true
    )
    try await deviceManager.applyPatch(datasetONo: patchONo, controller: nil)
    datasetPatchStorageExpectation.fulfill()

    try await connection.disconnect()
    endpointTask.cancel()
  }

  func testPeerToPeerGroup() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)

    let testBlock = try await SwiftOCADevice
      .OcaBlock<MyBooleanActuator>(
        objectNumber: testBlockONo,
        deviceDelegate: device,
        addToRootBlock: true
      )

    let group = try await _OcaPeerToPeerGroup<MyBooleanActuator>(
      objectNumber: testGroupONo,
      deviceDelegate: device,
      addToRootBlock: true
    )

    for i in 0..<10 {
      let actuator = try await MyBooleanActuator(
        role: "Actuator \(i)",
        deviceDelegate: device,
        addToRootBlock: false
      )
      try await testBlock.add(actionObject: actuator)
      try await group.add(member: actuator)
    }

    let connection = await OcaLocalConnection(endpoint)
    let endpointTask = Task { try? await endpoint.run() }
    try await connection.connect()

    let controllerExpectation =
      XCTestExpectation(description: "Check test block controller properties")
    let clientTestBlock: SwiftOCA.OcaBlock = try await connection
      .resolve(object: OcaObjectIdentification(
        oNo: testBlockONo,
        classIdentification: SwiftOCA.OcaBlock.classIdentification
      ))
    XCTAssertNotNil(clientTestBlock)
    let resolvedClientTestBlockActionObjects = try await clientTestBlock.resolveActionObjects()
    let testBlockMembers = await testBlock.actionObjects
    XCTAssertEqual(
      resolvedClientTestBlockActionObjects.map(\.objectNumber),
      testBlockMembers.map(\.objectNumber)
    )
    controllerExpectation.fulfill()
    await fulfillment(of: [controllerExpectation], timeout: 1)

    let allActuators = resolvedClientTestBlockActionObjects
      .compactMap { $0 as? SwiftOCA.OcaBooleanActuator }
    let anActuator = allActuators.first
    XCTAssertNotNil(anActuator)

    for object in allActuators {
      try await object.subscribe()
    }

    anActuator!.setting = .success(true)

    let deviceActuatorExpectation =
      XCTestExpectation(description: "All device actuators in group are set to true")
    try await Task.sleep(for: .milliseconds(100))
    for object in await testBlock.actionObjects {
      let settingValue = await object.setting
      XCTAssertTrue(settingValue)
    }
    deviceActuatorExpectation.fulfill()
    await fulfillment(of: [deviceActuatorExpectation], timeout: 1)

    XCTAssertTrue(allActuators.allSatisfy { $0.setting == .success(true) })
    try await connection.disconnect()
    endpointTask.cancel()
  }

  func testGroupControllerGroup() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)

    let testBlock = try await SwiftOCADevice
      .OcaBlock<MyBooleanActuator>(
        objectNumber: testBlockONo,
        deviceDelegate: device,
        addToRootBlock: true
      )

    let group = try await _OcaGroupControllerGroup<MyBooleanActuator>(
      objectNumber: testGroupONo,
      deviceDelegate: device,
      addToRootBlock: true
    )

    for i in 0..<10 {
      let actuator = try await MyBooleanActuator(
        role: "Actuator \(i)",
        deviceDelegate: device,
        addToRootBlock: false
      )
      try await testBlock.add(actionObject: actuator)
      try await group.add(member: actuator)
    }

    let connection = await OcaLocalConnection(endpoint)
    let endpointTask = Task { try? await endpoint.run() }
    try await connection.connect()

    let controllerExpectation =
      XCTestExpectation(description: "Check test block controller properties")
    let clientTestBlock: SwiftOCA.OcaBlock = try await connection
      .resolve(object: OcaObjectIdentification(
        oNo: testBlockONo,
        classIdentification: SwiftOCA.OcaBlock.classIdentification
      ))
    XCTAssertNotNil(clientTestBlock)

    let resolvedClientTestBlockActionObjects = try await clientTestBlock.resolveActionObjects()
    let testBlockMembers = await testBlock.actionObjects
    XCTAssertEqual(
      resolvedClientTestBlockActionObjects.map(\.objectNumber),
      testBlockMembers.map(\.objectNumber)
    )
    controllerExpectation.fulfill()
    await fulfillment(of: [controllerExpectation], timeout: 1)

    let allActuators = resolvedClientTestBlockActionObjects
      .compactMap { $0 as? SwiftOCA.OcaBooleanActuator }
    let anActuator = allActuators.first
    XCTAssertNotNil(anActuator)

    for object in allActuators {
      try await object.subscribe()
    }

    let clientGroupExpectation =
      XCTestExpectation(description: "Resolved actuator group proxy and set setting to true")

    let clientGroupObject: SwiftOCA.OcaGroup = try await connection
      .resolve(object: OcaObjectIdentification(
        oNo: testGroupONo,
        classIdentification: SwiftOCA.OcaGroup.classIdentification
      ))
    XCTAssertNotNil(clientGroupObject)

    let clientGroupProxy: SwiftOCA.OcaBooleanActuator = try await clientGroupObject
      .resolveGroupController()
    XCTAssertNotNil(clientGroupProxy)
    clientGroupProxy.setting = .success(true)
    clientGroupExpectation.fulfill()

    await fulfillment(of: [clientGroupExpectation], timeout: 1)

    let deviceActuatorExpectation =
      XCTestExpectation(description: "All device actuators in group are set to true")
    try await Task.sleep(for: .milliseconds(100))

    for object in await testBlock.actionObjects {
      let settingValue = await object.setting
      XCTAssertTrue(settingValue)
    }
    deviceActuatorExpectation.fulfill()
    await fulfillment(of: [deviceActuatorExpectation], timeout: 1)

    XCTAssertTrue(allActuators.allSatisfy { $0.setting == .success(true) })
    try await connection.disconnect()
    endpointTask.cancel()
  }

  func testBlockGlobalTypeSerialization() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let globalTypeBlockONo: OcaONo = 20001
    let testGlobalType = OcaGlobalTypeIdentifier(
      authority: OcaOrganizationID((0xFA, 0x2E, 0xE9)),
      id: 12345
    )

    let testBlock = try await SwiftOCADevice
      .OcaBlock<MyBooleanActuator>(
        objectNumber: globalTypeBlockONo,
        deviceDelegate: device,
        addToRootBlock: true
      )
    await Task { @OcaDevice in
      testBlock.globalType = testGlobalType
    }.value

    let actuator = try await MyBooleanActuator(
      role: "TestActuator",
      deviceDelegate: device,
      addToRootBlock: false
    )
    try await testBlock.add(actionObject: actuator)

    // Serialize
    let jsonObject = try await testBlock.serialize()

    // Verify globalType is in the serialized output
    XCTAssertNotNil(jsonObject["3.5"])

    // Round-trip through JSONSerialization (as would happen with real storage)
    let jsonData = try JSONSerialization.data(withJSONObject: jsonObject)
    let decoded = try JSONSerialization.jsonObject(with: jsonData) as! [String: Sendable]

    // Deserialize back — should succeed with matching globalType
    try await testBlock.deserialize(jsonObject: decoded)

    // Now set a mismatched globalType and verify deserialization fails
    let mismatchedGlobalType = OcaGlobalTypeIdentifier(
      authority: OcaOrganizationID((0x01, 0x02, 0x03)),
      id: 99999
    )
    await Task { @OcaDevice in
      testBlock.globalType = mismatchedGlobalType
    }.value

    do {
      try await testBlock.deserialize(jsonObject: decoded)
      XCTFail("Expected globalTypeMismatch error")
    } catch {
      XCTAssertEqual(error as? Ocp1Error, Ocp1Error.globalTypeMismatch)
    }
  }

  /// Test that OcaBoundedDeviceProperty correctly deserializes JSON values after
  /// a JSONSerialization round-trip, where numeric types may change (e.g. Float
  /// is read back as Double, or integer JSON numbers become Int instead of Float).
  func testBoundedPropertyJsonRoundTrip() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    // OcaFloat32Actuator has an @OcaBoundedDeviceProperty<OcaFloat32> at 5.1
    let actuator = try await SwiftOCADevice.OcaFloat32Actuator(
      deviceDelegate: device,
      addToRootBlock: true
    )

    // Set a known value
    await Task { @OcaDevice in
      actuator.setting = OcaBoundedPropertyValue(value: 0.75, in: 0.0...1.0)
    }.value

    // Serialize, round-trip through JSONSerialization, then deserialize
    let jsonObject = try await actuator.serialize()
    let jsonData = try JSONSerialization.data(withJSONObject: jsonObject)
    let decoded = try JSONSerialization.jsonObject(with: jsonData) as! [String: Sendable]

    // This would fail with badFormat before the fix because JSONSerialization
    // deserializes Float as Double and the direct cast to [String: Float] fails
    try await actuator.deserialize(jsonObject: decoded, flags: .ignoreAllErrors)

    let setting = await actuator.setting
    XCTAssertEqual(setting.value, 0.75, accuracy: 0.0001)
    XCTAssertEqual(setting.minValue, 0.0)
    XCTAssertEqual(setting.maxValue, 1.0)
  }

  /// Test that OcaBoundedDeviceProperty handles integer JSON values (e.g. when
  /// the bounds are whole numbers like 0 and 1 that JSON encodes as integers).
  func testBoundedPropertyJsonIntegerValues() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let actuator = try await SwiftOCADevice.OcaInt32Actuator(
      deviceDelegate: device,
      addToRootBlock: true
    )

    await Task { @OcaDevice in
      actuator.setting = OcaBoundedPropertyValue(value: 42, in: 0...100)
    }.value

    let jsonObject = try await actuator.serialize()
    let jsonData = try JSONSerialization.data(withJSONObject: jsonObject)
    let decoded = try JSONSerialization.jsonObject(with: jsonData) as! [String: Sendable]

    try await actuator.deserialize(jsonObject: decoded, flags: .ignoreAllErrors)

    let setting = await actuator.setting
    XCTAssertEqual(setting.value, 42)
    XCTAssertEqual(setting.minValue, 0)
    XCTAssertEqual(setting.maxValue, 100)
  }

  /// Test that OcaBoundedDeviceProperty rejects values outside the deserialized bounds.
  func testBoundedPropertyJsonOutOfRange() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let actuator = try await SwiftOCADevice.OcaFloat32Actuator(
      deviceDelegate: device,
      addToRootBlock: true
    )

    // Construct a JSON object where value exceeds the upper bound
    var jsonObject = try await actuator.serialize()
    jsonObject["5.1"] = ["v": 2.0, "l": 0.0, "u": 1.0] as [String: Double]

    do {
      try await actuator.deserialize(jsonObject: jsonObject)
      XCTFail("Expected badFormat error for out-of-range value")
    } catch {
      XCTAssertEqual(error as? Ocp1Error, Ocp1Error.status(.badFormat))
    }
  }

  /// Test that the serialization filter can ignore properties
  func testSerializationFilterIgnore() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let actuator = try await MyBooleanActuator(
      role: "FilterTest",
      deviceDelegate: device,
      addToRootBlock: true
    )
    await actuator.set(to: true)

    // Serialize without filter — setting (property 5.1) should be present
    let fullJson = try await actuator.serialize()
    XCTAssertNotNil(fullJson["5.1"])

    // Serialize with filter that ignores property 5.1
    let filteredJson = try await actuator.serialize(filter: { _, propertyID, _ in
      propertyID == OcaPropertyID("5.1") ? .ignore : .ok
    })
    XCTAssertNil(filteredJson["5.1"])
    // Other properties should still be present
    XCTAssertNotNil(filteredJson["_oNo"])
  }

  /// Test that the serialization filter can replace property values
  func testSerializationFilterReplace() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let actuator = try await MyBooleanActuator(
      role: "ReplaceTest",
      deviceDelegate: device,
      addToRootBlock: true
    )
    await actuator.set(to: true)

    let json = try await actuator.serialize(filter: { _, propertyID, _ in
      // Replace the setting value with false
      if propertyID == OcaPropertyID("5.1") {
        return .replace(false)
      }
      return .ok
    })
    XCTAssertEqual(json["5.1"] as? Bool, false)
  }

  /// Test that the deserialization filter can ignore properties
  func testDeserializationFilterIgnore() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let actuator = try await MyBooleanActuator(
      role: "DeserFilterTest",
      deviceDelegate: device,
      addToRootBlock: true
    )
    await actuator.set(to: false)

    // Create JSON with setting = true
    var jsonObject = try await actuator.serialize()
    jsonObject["5.1"] = true

    // Deserialize with filter that ignores property 5.1
    try await actuator.deserialize(
      jsonObject: jsonObject,
      filter: { _, propertyID, _ in
        propertyID == OcaPropertyID("5.1") ? .ignore : .ok
      }
    )

    // Setting should remain false since the filter ignored it
    let setting = await actuator.setting
    XCTAssertFalse(setting)
  }

  /// Test that the deserialization filter can replace property values
  func testDeserializationFilterReplace() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let actuator = try await MyBooleanActuator(
      role: "DeserReplaceTest",
      deviceDelegate: device,
      addToRootBlock: true
    )
    await actuator.set(to: false)

    // Create JSON with setting = true
    var jsonObject = try await actuator.serialize()
    jsonObject["5.1"] = true

    // Deserialize with filter that replaces the value with false
    try await actuator.deserialize(
      jsonObject: jsonObject,
      filter: { _, propertyID, _ in
        if propertyID == OcaPropertyID("5.1") {
          return .replace(false)
        }
        return .ok
      }
    )

    let setting = await actuator.setting
    XCTAssertFalse(setting)
  }

  /// Test that the deserialization filter is propagated through blocks
  func testDeserializationFilterPropagatedToChildren() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let testBlock = try await SwiftOCADevice
      .OcaBlock<MyBooleanActuator>(
        objectNumber: testBlockONo,
        deviceDelegate: device,
        addToRootBlock: true
      )
    let actuator = try await MyBooleanActuator(
      role: "BlockChild",
      deviceDelegate: device,
      addToRootBlock: false
    )
    try await testBlock.add(actionObject: actuator)
    await actuator.set(to: false)

    // Serialize the block
    var jsonObject = try await testBlock.serialize()

    // Modify the child's setting in the JSON
    if var actionObjects = jsonObject["3.2"] as? [[String: any Sendable]] {
      actionObjects[0]["5.1"] = true
      jsonObject["3.2"] = actionObjects as [any Sendable]
    }

    // Deserialize with filter that ignores setting changes
    try await testBlock.deserialize(
      jsonObject: jsonObject,
      flags: .ignoreAllErrors,
      filter: { _, propertyID, _ in
        propertyID == OcaPropertyID("5.1") ? .ignore : .ok
      }
    )

    // Child's setting should remain false
    let setting = await actuator.setting
    XCTAssertFalse(setting)
  }

  func testKeyPathUncached() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let testBlock = try await SwiftOCADevice
      .OcaBlock<MyBooleanActuator>(
        objectNumber: testBlockONo,
        deviceDelegate: device,
        addToRootBlock: true
      )
    measure {
      for _ in 0..<10000 {
        let keyPaths = testBlock.allDevicePropertyKeyPathsUncached
        XCTAssertGreaterThan(keyPaths.count, 10)
      }
    }
  }

  func testKeyPathCached() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let testBlock = try await SwiftOCADevice
      .OcaBlock<MyBooleanActuator>(
        objectNumber: testBlockONo,
        deviceDelegate: device,
        addToRootBlock: true
      )
    for _ in 0..<10000 {
      let keyPaths = await testBlock.allDevicePropertyKeyPaths
      XCTAssertGreaterThan(keyPaths.count, 10)
    }
  }
}

/// https://github.com/apple/swift-corelibs-xctest/issues/436
extension XCTestCase {
  /// Wait on an array of expectations for up to the specified timeout, and optionally specify
  /// whether they
  /// must be fulfilled in the given order. May return early based on fulfillment of the waited on
  /// expectations.
  ///
  /// - Parameter expectations: The expectations to wait on.
  /// - Parameter timeout: The maximum total time duration to wait on all expectations.
  /// - Parameter enforceOrder: Specifies whether the expectations must be fulfilled in the order
  ///   they are specified in the `expectations` Array. Default is false.
  /// - Parameter file: The file name to use in the error message if
  ///   expectations are not fulfilled before the given timeout. Default is the file
  ///   containing the call to this method. It is rare to provide this
  ///   parameter when calling this method.
  /// - Parameter line: The line number to use in the error message if the
  ///   expectations are not fulfilled before the given timeout. Default is the line
  ///   number of the call to this method in the calling file. It is rare to
  ///   provide this parameter when calling this method.
  ///
  /// - SeeAlso: XCTWaiter
  func fulfillment(
    of expectations: [XCTestExpectation],
    timeout: TimeInterval,
    enforceOrder: Bool = false
  ) async {
    await withCheckedContinuation { continuation in
      // This function operates by blocking a background thread instead of one owned by
      // libdispatch or by the
      // Swift runtime (as used by Swift concurrency.) To ensure we use a thread owned by
      // neither subsystem, use
      // Foundation's Thread.detachNewThread(_:).
      Thread.detachNewThread { @Sendable [self] in
        wait(for: expectations, timeout: timeout, enforceOrder: enforceOrder)
        continuation.resume()
      }
    }
  }
}
