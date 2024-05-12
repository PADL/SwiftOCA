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
@testable import SwiftOCADevice
import XCTest

final class MyBooleanActuator: SwiftOCADevice.OcaBooleanActuator, OcaGroupPeerToPeerMember {
  weak var group: SwiftOCADevice.OcaGroup<MyBooleanActuator>?

  override class var classID: OcaClassID { OcaClassID(parent: super.classID, 65280) }

  func set(to value: Bool) async { setting = value }
}

final class _MyBooleanActuator: SwiftOCA.OcaBooleanActuator {
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
    await OcaClassRegistry.shared.register(_MyBooleanActuator.self)

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
    let jsonObject = await device.rootBlock.jsonObject
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
      Thread.detachNewThread { [self] in
        wait(for: expectations, timeout: timeout, enforceOrder: enforceOrder)
        continuation.resume()
      }
    }
  }
}
