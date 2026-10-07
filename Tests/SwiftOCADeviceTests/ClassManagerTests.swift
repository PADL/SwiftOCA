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

@_spi(SwiftOCAPrivate) import SwiftOCA
@testable import SwiftOCADevice
import XCTest

/// The class manager seen by a controller, over a connection of its own to a device
/// with a gain on it.
final class ClassManagerTests: XCTestCase {
  private struct Harness {
    let connection: OcaLocalConnection
    let endpointTask: Task<Void, Never>
    let classManager: SwiftOCA.OcaClassManager

    func tearDown() async {
      try? await connection.disconnect()
      endpointTask.cancel()
    }
  }

  private func makeHarness() async throws -> Harness {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await SwiftOCADevice.OcaGain(role: "Gain", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaFloat32Actuator(role: "Float", deviceDelegate: device)
    let made = await device.classManager
    XCTAssertNotNil(made, "the device makes its class manager with its other managers")
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(endpoint)
    try await connection.connect()
    let classManager: SwiftOCA.OcaClassManager = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: SwiftOCA.OcaClassManager.objectNumber,
        classIdentification: SwiftOCA.OcaClassManager.classIdentification
      )
    )
    return Harness(connection: connection, endpointTask: endpointTask, classManager: classManager)
  }

  func testAClassIsDescribedWithItsOwnElementsOrItsAncestorsToo() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    let gain = try await h.classManager.getControlClass(
      classID: SwiftOCADevice.OcaGain.classID, includeInherited: false
    )
    XCTAssertEqual(gain.classID, SwiftOCADevice.OcaGain.classID)
    XCTAssertEqual(gain.name, "OcaGain")
    let property = try XCTUnwrap(gain.properties.first { $0.propertyID == OcaPropertyID(defLevel: 4, propertyIndex: 1) })
    XCTAssertEqual(property.name, "gain")
    // the type as declared, a typealias kept, a bounded property's being its value's
    XCTAssertEqual(property.typeName, "OcaDB")
    XCTAssertFalse(property.isReadOnly)
    // its own elements only: nothing of OcaRoot's or OcaWorker's
    XCTAssertTrue(gain.properties.allSatisfy { $0.propertyID.defLevel == 4 })

    let inherited = try await h.classManager.getControlClass(
      classID: SwiftOCADevice.OcaGain.classID, includeInherited: true
    )
    let label = try XCTUnwrap(inherited.properties.first { $0.name == "label" })
    XCTAssertEqual(label.propertyID.defLevel, 2)
    XCTAssertEqual(label.typeName, "OcaString")
    XCTAssertFalse(label.isReadOnly)
    XCTAssertGreaterThan(inherited.properties.count, gain.properties.count)
  }

  func testATypeIsNamedAsDeclaredOnlyWhereThatIsAnAES70Name() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    // declared with the generic class's parameter: named for the type it is at run time
    let float = try await h.classManager.getControlClass(
      classID: SwiftOCADevice.OcaFloat32Actuator.classID, includeInherited: true
    )
    let setting = try XCTUnwrap(float.properties.first { $0.name == "setting" })
    XCTAssertEqual(setting.typeName, "OcaFloat32")
    let declared = await SwiftOCADevice.OcaFloat32Actuator.devicePropertyTypeNames
    XCTAssertNil(declared["setting"])
  }

  func testEveryClassOfTheDevicesObjectsIsListed() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    let classes = try await h.classManager.getControlClasses()
    let ids = Set(classes.map(\.classID))
    XCTAssertTrue(ids.contains(SwiftOCADevice.OcaGain.classID))
    XCTAssertTrue(ids.contains(SwiftOCA.OcaClassManager.classID))
    // the class manager describes its own methods
    let own = try XCTUnwrap(classes.first { $0.classID == SwiftOCA.OcaClassManager.classID })
    let method = try XCTUnwrap(own.methods.first { $0.name == "GetControlClass" })
    XCTAssertEqual(method.parameters.map(\.name), ["ClassID", "IncludeInherited"])
    XCTAssertEqual(method.parameters.map(\.typeName), ["OcaClassID", "OcaBoolean"])
    let list = try XCTUnwrap(own.methods.first { $0.name == "GetControlClasses" })
    XCTAssertEqual(list.resultTypeName, "OcaList<OcaClassDescriptor>")
    // a generic class by its own name
    XCTAssertTrue(classes.contains { $0.name == "OcaBlock" })
    XCTAssertEqual(ids.count, classes.count, "each class once")
  }

  func testAClassNoObjectIsOfIsAParameterError() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    do {
      _ = try await h.classManager.getControlClass(classID: OcaClassID("1.1.1.99"), includeInherited: false)
      XCTFail("no object is of the class")
    } catch let Ocp1Error.status(status) {
      XCTAssertEqual(status, .parameterError)
    }
  }
}
