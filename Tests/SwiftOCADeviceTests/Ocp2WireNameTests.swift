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

/// AES70-4 names a command's and a response's parameters after the model (AES70-2A), and
/// a strict peer matches them by name. These pin the exact keys on the wire, one test per
/// shape a name can take, without needing the model file (see the naming oracles).
final class Ocp2WireNameTests: XCTestCase {
  private static let dynamicsONo: OcaONo = 0x0001_0400
  private static let matrixONo: OcaONo = 0x0001_0500
  private static let applicationONo: OcaONo = 0x0001_0600
  private static let portID = OcaPortID(mode: .input, index: 1)

  /// A device with one object of each shape, served over the OCP.2 local endpoint.
  private struct Fixture {
    let endpoint: OcaLocalDeviceEndpoint
    let endpointTask: Task<(), Never>

    func tearDown() {
      endpointTask.cancel()
    }
  }

  @OcaDevice
  private static func populate(_ device: OcaDevice) async throws {
    _ = try await SwiftOCADevice.OcaDynamics(
      objectNumber: dynamicsONo,
      role: "Dynamics",
      deviceDelegate: device,
      addToRootBlock: true
    )
    _ = try await SwiftOCADevice.OcaMatrix<SwiftOCADevice.OcaWorker>(
      rows: 2,
      columns: 2,
      objectNumber: matrixONo,
      deviceDelegate: device,
      addToRootBlock: true
    )
    let application = try await SwiftOCADevice.OcaMediaTransportApplication(
      objectNumber: applicationONo,
      deviceDelegate: device
    )
    application.ports = [OcaPort(owner: applicationONo, id: portID, name: "In 1")]
  }

  private func makeFixture() async throws -> Fixture {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    try await Self.populate(device)
    let endpoint = try await OcaLocalDeviceEndpoint(device: device, controlProtocol: .ocp2)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    return Fixture(endpoint: endpoint, endpointTask: endpointTask)
  }

  /// One command in, its response's `Parameters` out, over the endpoint's raw channels.
  @OcaDevice
  private static func responseParameters(
    _ fixture: Fixture,
    targetONo: OcaONo,
    methodID: String,
    parameters: String? = nil
  ) async throws -> [String: any Sendable] {
    var command = "{\"Handle\":1,\"TargetONo\":\(targetONo),\"MethodID\":[\(methodID)]"
    if let parameters {
      command += ",\"Parameters\":\(parameters)"
    }
    command += "}"
    let pdu = "{\"ProtocolVersion\":1,\"Commands\":[\(command)]}\n"
    await fixture.endpoint.requestChannel.send(Data(pdu.utf8))
    for await data in fixture.endpoint.responseChannel {
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
      let response = try XCTUnwrap((object["Responses"] as? [[String: Any]])?.first)
      XCTAssertEqual(response["StatusCode"] as? String, "OK", "method \(methodID)")
      return Ocp2JSON.sendableObject(response["Parameters"] as? [String: Any] ?? [:])
    }
    throw Ocp1Error.notConnected
  }

  // MARK: - what the device answers

  func testGetterResponseIsNamedAfterTheModel() async throws {
    let fixture = try await makeFixture()
    defer { fixture.tearDown() }

    // OcaBlock 3.6 GetActionObjectsRecursive → Objects, not ActionObjects
    let parameters = try await Self.responseParameters(fixture, targetONo: OcaRootBlockONo, methodID: "3,6")
    XCTAssertEqual(Set(parameters.keys), ["Objects"])
  }

  func testBoundedGetterResponseCarriesMinAndMax() async throws {
    let fixture = try await makeFixture()
    defer { fixture.tearDown() }

    // OcaDynamics 4.13 GetAttackTime → Time, MinTime, MaxTime
    let parameters = try await Self.responseParameters(fixture, targetONo: Self.dynamicsONo, methodID: "4,13")
    XCTAssertEqual(Set(parameters.keys), ["Time", "MinTime", "MaxTime"])
  }

  func testScalarResponseIsNamed() async throws {
    let fixture = try await makeFixture()
    defer { fixture.tearDown() }

    // OcaMediaTransportApplication 3.4 GetPortName(PortID) → Name, once the "Value" placeholder
    let parameters = try await Self.responseParameters(
      fixture,
      targetONo: Self.applicationONo,
      methodID: "3,4",
      parameters: "{\"PortID\":{\"Mode\":1,\"Index\":1}}"
    )
    XCTAssertEqual(Set(parameters.keys), ["Name"])
    XCTAssertEqual(parameters["Name"] as? String, "In 1")
  }

  func testSetterParameterIsNamedSeparatelyFromTheGetter() async throws {
    let fixture = try await makeFixture()
    defer { fixture.tearDown() }

    // OcaDeviceManager 3.17 GetMessage → Message, but 3.18 SetMessage ← Text
    let before = try await Self.responseParameters(
      fixture,
      targetONo: OcaDeviceManagerONo,
      methodID: "3,17"
    )
    XCTAssertEqual(Set(before.keys), ["Message"])

    _ = try await Self.responseParameters(
      fixture,
      targetONo: OcaDeviceManagerONo,
      methodID: "3,18",
      parameters: "{\"Text\":\"on air\"}"
    )
    let after = try await Self.responseParameters(
      fixture,
      targetONo: OcaDeviceManagerONo,
      methodID: "3,17"
    )
    XCTAssertEqual(after["Message"] as? String, "on air")
  }

  func testRecordParametersAreNamedByField() async throws {
    let fixture = try await makeFixture()
    defer { fixture.tearDown() }

    // OcaBlock 3.17 FindActionObjectsByRole: a record in, keyed by the model's field names
    let parameters = try await Self.responseParameters(
      fixture,
      targetONo: OcaRootBlockONo,
      methodID: "3,17",
      parameters: "{\"SearchName\":\"Dynamics\",\"NameComparisonType\":\"Exact\",\"SearchClassID\":[1,1,1,14],\"ResultFlags\":1}"
    )
    let result = try XCTUnwrap(parameters["Result"] as? [[String: any Sendable]])
    XCTAssertEqual(result.map { $0["ONo"] as? Int }, [Int(Self.dynamicsONo)])
  }

  func testVectorGetterIsNamedByField() async throws {
    let fixture = try await makeFixture()
    defer { fixture.tearDown() }

    // OcaMatrix 3.1 GetCurrentXY → X, Y from the vector record, not the property
    let parameters = try await Self.responseParameters(fixture, targetONo: Self.matrixONo, methodID: "3,1")
    XCTAssertEqual(Set(parameters.keys), ["X", "Y"])
  }

  // MARK: - what the client sends

  /// The next command written to an endpoint nobody is serving.
  @OcaDevice
  private static func nextCommand(
    from endpoint: OcaLocalDeviceEndpoint
  ) async throws -> (methodID: [Int], parameters: [String: any Sendable]) {
    for await data in endpoint.requestChannel {
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
      guard let command = (object["Commands"] as? [[String: Any]])?.first else { continue }
      let methodID = try XCTUnwrap(command["MethodID"] as? [Any]).prefix(2).compactMap { $0 as? Int }
      return (methodID, Ocp2JSON.sendableObject(command["Parameters"] as? [String: Any] ?? [:]))
    }
    throw Ocp1Error.notConnected
  }

  func testClientNamesCommandParametersAfterTheModel() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device, controlProtocol: .ocp2)
    let connection = await OcaLocalConnection(
      endpoint,
      options: Ocp1ConnectionOptions(flags: [], controlProtocol: .ocp2)
    )
    try await connection.connect()
    defer { Task { try? await connection.disconnect() } }

    let dynamics: SwiftOCA.OcaDynamics = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: Self.dynamicsONo,
        classIdentification: SwiftOCA.OcaDynamics.classIdentification
      )
    )
    let application: SwiftOCA.OcaMediaTransportApplication = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: Self.applicationONo,
        classIdentification: SwiftOCA.OcaMediaTransportApplication.classIdentification
      )
    )

    // OcaDynamics 4.4 SetFunction(Func): a wrapper's setter, named by its ocp2Name
    let setFunction = Task {
      try? await dynamics.$function._setValue(dynamics, OcaDynamicsFunction.compress)
    }
    let setter = try await Self.nextCommand(from: endpoint)
    setFunction.cancel()
    XCTAssertEqual(setter.methodID, [4, 4])
    XCTAssertEqual(Set(setter.parameters.keys), ["Func"])

    // OcaMediaTransportApplication 3.22 GetEndpoint(ID): a scalar once sent as "Value"
    let getEndpoint = Task {
      _ = try? await application.getEndpoint(1)
    }
    let scalar = try await Self.nextCommand(from: endpoint)
    getEndpoint.cancel()
    XCTAssertEqual(scalar.methodID, [3, 22])
    XCTAssertEqual(Set(scalar.parameters.keys), ["ID"])

    // OcaDeviceManager 3.18 SetMessage(Text): the setter's name is not the getter's
    let deviceManager = await connection.deviceManager
    let setMessage = Task {
      try? await deviceManager.$message._setValue(deviceManager, "on air")
    }
    let differing = try await Self.nextCommand(from: endpoint)
    setMessage.cancel()
    XCTAssertEqual(differing.methodID, [3, 18])
    XCTAssertEqual(Set(differing.parameters.keys), ["Text"])
  }
}

#endif
