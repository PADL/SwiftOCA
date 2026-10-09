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
import SwiftOCAXMI
import XCTest

/// Reads an excerpt of the AES70-2 class model and compares what a device's class
/// manager says of the same classes and datatypes with it.
final class XMIRoundTripTests: XCTestCase {
  private static func model() throws -> OcaXMIModel {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "AES70-2-excerpt", withExtension: "xmi", subdirectory: "Resources"))
    return try OcaXMIModel(contentsOf: url)
  }

  @OcaDevice
  /// A device with an object of each class the excerpt describes, and its class manager,
  /// which holds the device only weakly.
  private static func device() async throws -> (OcaDevice, SwiftOCADevice.OcaClassManager) {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await SwiftOCADevice.OcaGain(role: "Gain", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaMute(role: "Mute", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaIdentificationSensor(role: "Identify", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaDelayExtended(role: "Delay", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaTimeSource(role: "Time", deviceDelegate: device)
    return try await (device, SwiftOCADevice.OcaClassManager(deviceDelegate: device))
  }

  /// What the device describes otherwise than the model, one line for each difference.
  @OcaDevice
  private static func differences() async throws -> [String] {
    let model = try model()
    let (device, manager) = try await device()
    defer { withExtendedLifetime(device) {} }
    let described = manager.controlClasses
    var differences = [String]()
    func compare(_ what: String, _ ours: String, _ model: String) {
      if ours != model { differences.append("\(what): device \(ours), model \(model)") }
    }
    func signature(_ parameters: [OcaClassParameterDescriptor]) -> String {
      parameters.map { "\($0.direction) \($0.name.lowercased()): \($0.typeName)" }.joined(separator: ", ")
    }
    for modelClass in model.classes {
      guard let ours = described.first(where: { $0.classID == modelClass.classID }) else {
        differences.append("\(modelClass.name): not described by the device")
        continue
      }
      compare("\(modelClass.name) name", ours.name, modelClass.name)
      compare("\(modelClass.name) deprecated", "\(ours.isDeprecated)", "\(modelClass.isDeprecated)")
      for property in modelClass.properties {
        let what = "\(modelClass.name) property \(property.propertyID) \(property.name)"
        guard let mine = ours.properties.first(where: { $0.propertyID == property.propertyID }) else {
          differences.append("\(what): not described by the device"); continue
        }
        compare("\(what) name", mine.name, property.name)
        compare("\(what) type", mine.typeName, property.typeName)
        compare("\(what) read only", "\(mine.isReadOnly)", "\(property.isReadOnly)")
        compare("\(what) static", "\(mine.isStatic)", "\(property.isStatic)")
        compare("\(what) deprecated", "\(mine.isDeprecated)", "\(property.isDeprecated)")
      }
      for method in modelClass.methods {
        let what = "\(modelClass.name) method \(method.methodID) \(method.name)"
        guard let mine = ours.methods.first(where: { $0.methodID == method.methodID }) else {
          differences.append("\(what): not described by the device"); continue
        }
        compare("\(what) name", mine.name, method.name)
        compare("\(what) parameters", signature(mine.parameters), signature(method.parameters))
        compare("\(what) deprecated", "\(mine.isDeprecated)", "\(method.isDeprecated)")
      }
      for event in modelClass.events {
        let what = "\(modelClass.name) event \(event.eventID) \(event.name)"
        guard let mine = ours.events.first(where: { $0.eventID == event.eventID }) else {
          differences.append("\(what): not described by the device"); continue
        }
        compare("\(what) name", mine.name, event.name)
        compare("\(what) parameters", signature(mine.parameters), signature(event.parameters))
        compare("\(what) deprecated", "\(mine.isDeprecated)", "\(event.isDeprecated)")
      }
    }
    let datatypes = manager.datatypes
    for datatype in model.datatypes {
      guard let mine = datatypes.first(where: { $0.name == datatype.name }) else {
        differences.append("datatype \(datatype.name): not described by the device"); continue
      }
      compare("datatype \(datatype.name)", "\(mine.kind) \(mine.baseTypeName) \(mine.typeArguments)", "\(datatype.kind) \(datatype.baseTypeName) \(datatype.typeArguments)")
      compare("datatype \(datatype.name) deprecated", "\(mine.isDeprecated)", "\(datatype.isDeprecated)")
      func field(_ f: OcaFieldDescriptor) -> String { "\(f.name): \(f.typeName)\(f.isDeprecated ? " deprecated" : "")" }
      compare("datatype \(datatype.name) fields", "\(mine.fields.map(field))", "\(datatype.fields.map(field))")
      func item(_ i: OcaEnumItemDescriptor) -> String { "\(i.name.lowercased())=\(i.value)\(i.isDeprecated ? " deprecated" : "")" }
      compare("datatype \(datatype.name) items", "\(mine.items.map(item))", "\(datatype.items.map(item))")
    }
    return differences
  }

  func testTheModelIsReadAsAClassManagerWouldDescribeIt() throws {
    let model = try Self.model()
    XCTAssertEqual(model.classes.map(\.name), [
      "OcaRoot", "OcaWorker", "OcaActuator", "OcaGain", "OcaMute", "OcaSensor", "OcaIdentificationSensor",
      "OcaDelayExtended",
    ])
    let gain = try XCTUnwrap(model.controlClass(OcaClassID("1.1.1.5"), includeInherited: false))
    XCTAssertEqual(gain.properties, [OcaClassPropertyDescriptor(
      propertyID: OcaPropertyID("4.1"), name: "Gain", typeName: "OcaDB", isReadOnly: false,
      documentation: "Gain in dB."
    )])
    XCTAssertEqual(gain.methods.map(\.name), ["GetGain", "SetGain"])
    XCTAssertEqual(gain.methods[0].parameters.map(\.direction), [.out, .out, .out])
    let root = try XCTUnwrap(model.controlClass(OcaClassID("1"), includeInherited: false))
    XCTAssertEqual(root.properties.filter(\.isStatic).map(\.name), ["ClassID", "ClassVersion"])
    XCTAssertEqual(root.events.map(\.name), ["PropertyChanged"])

    // a class with its ancestors' elements, the root's first
    let inherited = try XCTUnwrap(model.controlClass(OcaClassID("1.1.1.5"), includeInherited: true))
    XCTAssertEqual(inherited.properties.first?.name, "ClassID")
    XCTAssertEqual(inherited.properties.last?.name, "Gain")
    XCTAssertEqual(inherited.events.map(\.name), ["PropertyChanged"])

    func datatype(_ name: String) throws -> OcaDatatypeDescriptor {
      try XCTUnwrap(model.datatypes.first { $0.name == name }, name)
    }
    let db = try datatype("OcaDB")
    XCTAssertEqual(db, OcaDatatypeDescriptor(
      name: "OcaDB", kind: .typedef, baseTypeName: "OcaFloat32", documentation: db.documentation
    ))
    XCTAssertFalse(db.documentation.isEmpty)
    XCTAssertEqual(try datatype("OcaBoolean").kind, .primitive)
    XCTAssertEqual(try datatype("OcaMuteState").items.map(\.value), [1, 2])
    XCTAssertEqual(try datatype("OcaMuteState").baseTypeName, "OcaUint8")
    XCTAssertEqual(try datatype("OcaDeviceState").kind, .bitset)
    XCTAssertEqual(try datatype("OcaPortID").fields.map(\.name), ["Direction", "Index"])
    XCTAssertEqual(try datatype("OcaPropertyChangedEventData").typeArguments, ["DT"])
    XCTAssertEqual(try datatype("OcaList<OcaPort>").typeArguments, ["OcaPort"])

    // a deprecated element is marked so, unless a live one has its ID: a renamed copy
    XCTAssertTrue(try XCTUnwrap(model.controlClass(OcaClassID("1.1.1.7.1"), includeInherited: false)).isDeprecated)
    XCTAssertFalse(gain.isDeprecated)
    XCTAssertTrue(try datatype("OcaDelayValue").isDeprecated)
    // stereotyped deprecated first, so its kind is the second of its stereotypes
    let reference = try datatype("OcaTimeReferenceType")
    XCTAssertEqual(reference.kind, .enum)
    XCTAssertTrue(reference.isDeprecated)
    XCTAssertFalse(reference.items.isEmpty)
    XCTAssertFalse(try datatype("OcaMuteState").isDeprecated)
    XCTAssertEqual(root.methods.filter { $0.methodID == OcaMethodID("1.3") }.map(\.name), ["SetLockNoReadWrite"])
    XCTAssertFalse(root.methods.contains(where: \.isDeprecated))

    // each element's documentation, its entities decoded and EA's markup kept
    XCTAssertEqual(gain.documentation, "Gain (or attenuation) element.")
    let setGain = try XCTUnwrap(gain.methods.first { $0.name == "SetGain" })
    XCTAssertEqual(setGain.documentation, "Sets the value of the <b>Gain </b>property.")
    XCTAssertEqual(setGain.parameters.map(\.documentation), ["Value to which the gain property shall be set if the method succeeds"])
    // an event is an operation whose one parameter, its data, is documented in its own right
    let changed = try XCTUnwrap(root.events.first)
    XCTAssertEqual(changed.parameters.map(\.direction), [.in])
    XCTAssertEqual(changed.parameters.map(\.typeName), ["OcaPropertyChangedEventData"])
    XCTAssertFalse(changed.documentation.isEmpty)
    XCTAssertFalse(try XCTUnwrap(changed.parameters.first).documentation.isEmpty)
    XCTAssertTrue(try datatype("OcaPortID").documentation.hasPrefix("Unique identifier of input or output Port"))
    XCTAssertTrue(try datatype("OcaPortID").fields[0].documentation.contains("named <b>Mode</b>"))
    XCTAssertEqual(try datatype("OcaPropertyChangeType").items.first?.documentation, "Current value has changed.")
  }

  /// A device's class manager describes the classes and datatypes of the excerpt as the
  /// model does, but for what is listed here, each for the reason it gives.
  func testADeviceDescribesTheModelsClassesAndDatatypesAsTheModelDoes() async throws {
    let differences = try await Self.differences()
    XCTAssertEqual(differences, [
      // not implemented by SwiftOCADevice, so not described
      "OcaWorker method 2.3 AddPort: not described by the device",
      "OcaWorker method 2.4 DeletePort: not described by the device",
      // a typedef of a list is named for its elements
      "OcaWorker method 2.13 GetPath parameters: device out rolepath: OcaList<OcaString>, out onopath: OcaList<OcaONo>, model out rolepath: OcaRolePath, out onopath: OcaONoPath",
      // OCP.2 upper-cases a Swift name's first letter only; peers match names case-insensitively
      #"datatype OcaPort fields: device ["Owner: OcaONo", "Id: OcaPortID", "Role: OcaString"], model ["Owner: OcaONo", "ID: OcaPortID", "Role: OcaString"]"#,
    ])
  }

  /// The model names a setter after what it sets, which is not always the property:
  /// OcaDeviceManager's SetEnabled sets ControlEnabled, since Enabled was its old name.
  func testASetterNamedForASuffixOfThePropertyMakesItWritable() throws {
    let document = """
    <?xml version="1.0" encoding="UTF-8"?>
    <xmi:XMI xmi:version="2.1" xmlns:uml="http://schema.omg.org/spec/UML/2.1" xmlns:xmi="http://schema.omg.org/spec/XMI/2.1">
    <uml:Model xmi:type="uml:Model" name="EA_Model"/>
    <xmi:Extension extender="Enterprise Architect"><elements>
    <element xmi:idref="E1" xmi:type="uml:Class" name="OcaThing"><properties stereotype="controlClass"/>
    <attributes>
    <attribute xmi:idref="A0" name="ClassID"><initial body="1.3.9"/></attribute>
    <attribute xmi:idref="A1" name="ControlEnabled"><style value="03p08"/><properties type="OcaBoolean"/></attribute>
    <attribute xmi:idref="A2" name="Enabled"><style value="03p08"/><stereotype stereotype="deprecated"/><properties type="OcaBoolean"/></attribute>
    <attribute xmi:idref="A3" name="LoggingEnabled"><style value="03p18"/><properties type="OcaBoolean"/></attribute>
    <attribute xmi:idref="A4" name="Busy"><style value="03p10"/><properties type="OcaBoolean"/></attribute>
    </attributes>
    <operations>
    <operation xmi:idref="O1" name="GetEnabled"><style value="03m11"/></operation>
    <operation xmi:idref="O2" name="SetEnabled"><style value="03m12"/></operation>
    <operation xmi:idref="O3" name="SetLoggingEnabled"><style value="03m25"/></operation>
    </operations>
    </element>
    </elements></xmi:Extension>
    </xmi:XMI>
    """
    let model = try OcaXMIModel(data: Data(document.utf8))
    let thing = try XCTUnwrap(model.classes.first)
    let writable = Dictionary(uniqueKeysWithValues: thing.properties.map { ($0.name, !$0.isReadOnly) })
    XCTAssertEqual(writable, ["ControlEnabled": true, "LoggingEnabled": true, "Busy": false])
  }
}
#endif
