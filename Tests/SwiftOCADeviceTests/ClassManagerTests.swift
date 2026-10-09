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

/// A gain whose value's generic argument is inferred, not written.
@OcaDeviceClass
private final class InferredGain: SwiftOCADevice.OcaActuator {
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  var gain = OcaBoundedPropertyValue(value: OcaDB(0), in: -144...20)
}

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
    _ = try await SwiftOCADevice.OcaLevelSensor(role: "Level", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaMute(role: "Mute", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaMatrix<SwiftOCADevice.OcaWorker>(
      rows: 2, columns: 2, deviceDelegate: device, addToRootBlock: false
    )
    // made after most objects, so it describes what the device already has
    _ = try await SwiftOCADevice.OcaClassManager(deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaIdentificationSensor(role: "Identify", deviceDelegate: device)
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(endpoint)
    try await connection.connect()
    let classManager: SwiftOCA.OcaClassManager = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: OcaClassManagerONo,
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
    XCTAssertEqual(property.name, "Gain")
    // the type as declared, a typealias kept, a bounded property's being its value's
    XCTAssertEqual(property.typeName, "OcaDB")
    XCTAssertFalse(property.isReadOnly)
    // its own elements only: nothing of OcaRoot's or OcaWorker's
    XCTAssertTrue(gain.properties.allSatisfy { $0.propertyID.defLevel == 4 })

    let inherited = try await h.classManager.getControlClass(
      classID: SwiftOCADevice.OcaGain.classID, includeInherited: true
    )
    let label = try XCTUnwrap(inherited.properties.first { $0.name == "Label" })
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
    let setting = try XCTUnwrap(float.properties.first { $0.name == "Setting" })
    XCTAssertEqual(setting.typeName, "OcaFloat32")
    let declared = await SwiftOCADevice.OcaFloat32Actuator.devicePropertyTypeNames
    XCTAssertNil(declared["setting"])

    // a bounded getter's results as the model has them: the value and its bounds, each
    // an out parameter of the type the signature writes
    let level = try await h.classManager.getControlClass(
      classID: SwiftOCADevice.OcaLevelSensor.classID, includeInherited: false
    )
    let getReading = try XCTUnwrap(level.methods.first { $0.name == "GetReading" })
    XCTAssertEqual(getReading.parameters.map(\.name), ["Reading", "MinReading", "MaxReading"])
    XCTAssertEqual(getReading.parameters.map(\.typeName), ["OcaDB", "OcaDB", "OcaDB"])
    XCTAssertEqual(getReading.parameters.map(\.direction), [.out, .out, .out])
  }

  @OcaDevice
  func testATypeWhoseArgumentsAreInferredIsNamedByTheRunTime() async {
    // the source says only OcaBoundedPropertyValue, so the run time names it
    XCTAssertNil(InferredGain.devicePropertyTypeNames["gain"])
  }

  func testAGenericDatatypeIsATemplateNamedInAES70Terms() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    // no Swift base type's name leaks into a datatype's or its arguments' names
    let swiftNames: Set = [
      "Bool", "String", "Int8", "Int16", "Int32", "Int64",
      "UInt8", "UInt16", "UInt32", "UInt64", "Float", "Double",
    ]
    let all = try await h.classManager.$datatypes._getValue(h.classManager, flags: [])
    for datatype in all {
      let names = [datatype.name, datatype.baseTypeName] + datatype.typeArguments + datatype.fields.map(\.typeName)
      let words = names.flatMap { $0.split { !$0.isLetter && !$0.isNumber }.map(String.init) }
      XCTAssertTrue(swiftNames.isDisjoint(with: words), "\(datatype.name): \(names)")
    }
    // a vector property is two of the model's, of the typedef it is declared with
    XCTAssertNil(all.first { $0.name.hasPrefix("OcaVector2D") })
    let coordinate = try await h.classManager.getDatatype(name: "OcaMatrixCoordinate")
    XCTAssertEqual(coordinate.kind, .typedef)
    XCTAssertEqual(coordinate.baseTypeName, "OcaUint16")
    let matrix = try await h.classManager.getControlClass(
      classID: SwiftOCADevice.OcaMatrix<SwiftOCADevice.OcaWorker>.classID, includeInherited: false
    )
    let xy = matrix.properties.filter { ["X", "Y"].contains($0.name) }
    XCTAssertEqual(xy.map(\.propertyID), [OcaPropertyID("3.1"), OcaPropertyID("3.2")])
    XCTAssertEqual(xy.map(\.typeName), ["OcaMatrixCoordinate", "OcaMatrixCoordinate"])
    let setXY = try XCTUnwrap(matrix.methods.first { $0.name == "SetCurrentXY" })
    XCTAssertEqual(setXY.parameters.map(\.name), ["X", "Y"])
    // a type coded as a template is named for the template, not Swift's generic
    let members = try XCTUnwrap(matrix.methods.first { $0.name == "GetMembers" })
    XCTAssertEqual(members.parameters.map(\.typeName), ["OcaList2D<OcaONo>"])
    XCTAssertFalse(all.contains { $0.name.contains("OcaArray2D") })

    // the model's OcaInterval, with AES70.js's Bounds
    let interval = SwiftOCA.OcaInterval<OcaUint16>.templateDescriptor
    XCTAssertEqual(interval.typeArguments, ["DT"])
    XCTAssertEqual(interval.fields.map(\.name), ["Min", "Max", "Bounds"])
  }

  func testARecordsFieldsAreNamedOnlyFromSeveralWrittenParameters() {
    XCTAssertEqual(
      OcaAnyMethodDescriptor.declaredNames(["OcaDB", "OcaBoolean"], fieldCount: 2, isRecord: true),
      ["OcaDB", "OcaBoolean"]
    )
    // one name for a record is the record's own, not its one field's
    XCTAssertNil(OcaAnyMethodDescriptor.declaredNames(["OcaFooParameters"], fieldCount: 1, isRecord: true))
    XCTAssertEqual(OcaAnyMethodDescriptor.declaredNames(["OcaDB"], fieldCount: 1, isRecord: false), ["OcaDB"])
    XCTAssertNil(OcaAnyMethodDescriptor.declaredNames(["OcaDB"], fieldCount: 2, isRecord: true))
  }

  func testOcaRootsClassPropertiesAreStatic() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    let root = try await h.classManager.getControlClass(classID: SwiftOCADevice.OcaRoot.classID, includeInherited: false)
    let leading = root.properties.prefix(3).map { "\($0.propertyID) \($0.name) \($0.typeName) \($0.isStatic)" }
    XCTAssertEqual(leading, ["1.1 ClassID OcaClassID true", "1.2 ClassVersion OcaClassVersionNumber true", "1.3 ObjectNumber OcaONo false"])
    XCTAssertTrue(root.properties.prefix(3).allSatisfy(\.isReadOnly))
  }

  func testTheDatatypesTheClassesReferToAreDescribedAsTheModelHasThem() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    let db = try await h.classManager.getDatatype(name: "OcaDB")
    XCTAssertEqual(db, OcaDatatypeDescriptor(name: "OcaDB", kind: .typedef, baseTypeName: "OcaFloat32"))
    let float = try await h.classManager.getDatatype(name: "OcaFloat32")
    XCTAssertEqual(float.kind, .primitive)
    let mute = try await h.classManager.getDatatype(name: "OcaMuteState")
    XCTAssertEqual(mute.kind, .enum)
    XCTAssertEqual(mute.items.map(\.name), ["Muted", "Unmuted"])
    let list = try await h.classManager.getDatatype(name: "OcaList<OcaClassDescriptor>")
    XCTAssertEqual(list.kind, .template)
    XCTAssertEqual(list.baseTypeName, "OcaList")
    XCTAssertEqual(list.typeArguments, ["OcaClassDescriptor"])
    let descriptor = try await h.classManager.getDatatype(name: "OcaClassDescriptor")
    XCTAssertEqual(descriptor.kind, .struct)
    XCTAssertEqual(descriptor.fields.map(\.name), ["ClassID", "ClassVersion", "Name", "Properties", "Methods", "Events"])

    let all = try await h.classManager.$datatypes._getValue(h.classManager, flags: [])
    XCTAssertEqual(Set(all.map(\.name)).count, all.count, "each datatype once")
    // every type a descriptor names is itself described
    let names = Set(all.map(\.name))
    // a fixed length blob's argument is its length, not a type
    let arguments = all.flatMap(\.typeArguments).filter { Int($0) == nil }
    // a struct's type arguments are its parameters, which its fields may name
    let referred = all.flatMap { datatype in
      [datatype.baseTypeName] + datatype.fields.map(\.typeName).filter { !(datatype.kind == .struct && datatype.typeArguments.contains($0)) }
    } + arguments.filter { argument in !all.contains { $0.kind == .struct && $0.typeArguments.contains(argument) } }
    XCTAssertEqual(Set(referred.filter { !$0.isEmpty }).subtracting(names), [])

    // an enum is coded as the integer it is based on
    XCTAssertEqual(mute.baseTypeName, "OcaUint8")

    // a type coded otherwise than its Swift declaration, described as it is coded
    let members = try await h.classManager.getDatatype(name: "OcaList2D<OcaONo>")
    XCTAssertEqual(members.kind, .template)
    XCTAssertEqual(members.baseTypeName, "OcaList2D")
    XCTAssertEqual(members.typeArguments, ["OcaONo"])
    let classIDField = try await h.classManager.getDatatype(name: "OcaClassIDField")
    XCTAssertEqual(classIDField.kind, .struct)
    let organization = try await h.classManager.getDatatype(name: "OcaBlobFixedLen<3>")
    XCTAssertEqual(organization.kind, .template)
  }

  func testAClassListsItsEventsAndItsPropertiesAccessorsAsMethods() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    let root = try await h.classManager.getControlClass(classID: SwiftOCADevice.OcaRoot.classID, includeInherited: false)
    XCTAssertEqual(root.events, [OcaClassEventDescriptor(
      eventID: OcaPropertyChangedEventID, name: "PropertyChanged", eventDataTypeName: "OcaPropertyChangedEventData"
    )])
    let changed = try await h.classManager.getDatatype(name: "OcaPropertyChangedEventData")
    XCTAssertEqual(changed.fields.map(\.typeName), ["OcaPropertyID", "DT", "OcaPropertyChangeType"])

    // a class's own events only, unless its ancestors' are asked for
    let gain = try await h.classManager.getControlClass(classID: SwiftOCADevice.OcaGain.classID, includeInherited: false)
    XCTAssertEqual(gain.events, [])
    let inherited = try await h.classManager.getControlClass(classID: SwiftOCADevice.OcaGain.classID, includeInherited: true)
    XCTAssertEqual(inherited.events.map(\.name), ["PropertyChanged"])

    // a bounded property's getter returns its value and range; its setter takes its value
    let getGain = try XCTUnwrap(gain.methods.first { $0.name == "GetGain" })
    XCTAssertEqual(getGain.methodID, OcaMethodID("4.1"))
    XCTAssertEqual(getGain.parameters.map(\.direction), [.out, .out, .out])
    XCTAssertEqual(getGain.parameters.map(\.typeName), ["OcaDB", "OcaDB", "OcaDB"])
    let setGain = try XCTUnwrap(gain.methods.first { $0.name == "SetGain" })
    XCTAssertEqual(setGain.parameters.map(\.name), ["Gain"])
    XCTAssertEqual(setGain.parameters.map(\.direction), [.in])
    // in method ID order
    let ids = inherited.methods.map { [Int($0.methodID.defLevel), Int($0.methodID.methodIndex)] }
    XCTAssertEqual(ids, ids.sorted { $0.lexicographicallyPrecedes($1) })
  }

  func testEveryClassOfTheDevicesObjectsIsListed() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    let classes = try await h.classManager.$controlClasses._getValue(h.classManager, flags: [])
    let ids = Set(classes.map(\.classID))
    XCTAssertTrue(ids.contains(SwiftOCADevice.OcaGain.classID))
    XCTAssertTrue(ids.contains(SwiftOCA.OcaClassManager.classID))
    // the class manager describes its own methods
    let own = try XCTUnwrap(classes.first { $0.classID == SwiftOCA.OcaClassManager.classID })
    let method = try XCTUnwrap(own.methods.first { $0.name == "GetControlClass" })
    XCTAssertEqual(method.parameters.map(\.name), ["ClassID", "IncludeInherited", "Descriptor"])
    XCTAssertEqual(method.parameters.map(\.typeName), ["OcaClassID", "OcaBoolean", "OcaClassDescriptor"])
    XCTAssertEqual(method.parameters.map(\.direction), [.in, .in, .out])
    // its lists are properties, read with their getters
    XCTAssertEqual(own.properties.map(\.name), ["ControlClasses", "Datatypes"])
    XCTAssertEqual(own.properties.map(\.isReadOnly), [true, true])
    let list = try XCTUnwrap(own.methods.first { $0.name == "GetControlClasses" })
    XCTAssertEqual(list.methodID, OcaMethodID("3.1"))
    XCTAssertEqual(list.parameters.map(\.name), ["ControlClasses"])
    XCTAssertEqual(list.parameters.map(\.typeName), ["OcaList<OcaClassDescriptor>"])
    XCTAssertEqual(list.parameters.map(\.direction), [.out])
    // a generic class by its own name
    XCTAssertTrue(classes.contains { $0.name == "OcaBlock" })
    XCTAssertEqual(ids.count, classes.count, "each class once")
  }

  @OcaDevice
  func testAClassGoesWithItsLastObjectAndTheRestStayInClassIDOrder() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let mute = try await SwiftOCADevice.OcaMute(role: "Mute", deviceDelegate: device)
    // made after one object and before another: it describes both
    let manager = try await SwiftOCADevice.OcaClassManager(deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaGain(role: "Gain", deviceDelegate: device)
    let before = manager.controlClasses.map(\.classID)
    XCTAssertTrue(before.contains(SwiftOCADevice.OcaMute.classID))
    XCTAssertTrue(before.contains(SwiftOCADevice.OcaGain.classID))
    XCTAssertEqual(before, before.sorted { $0.fields.lexicographicallyPrecedes($1.fields) })

    try await device.deregister(object: mute)
    XCTAssertEqual(manager.controlClasses.map(\.classID), before.filter { $0 != SwiftOCADevice.OcaMute.classID })
  }

}

