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
    let classManager = await device.classManager
    return try (device, XCTUnwrap(classManager))
  }

  /// What the device describes otherwise than the model, one line for each difference.
  @OcaDevice
  private static func differences() async throws -> [String] {
    let model = try model()
    let (device, manager) = try await device()
    defer { withExtendedLifetime(device) {} }
    let controller = RoundTripController()
    let described = try await manager.getControlClasses(from: controller)
    var differences = [String]()
    func compare(_ what: String, _ ours: String, _ model: String) {
      if ours != model { differences.append("\(what): device \(ours), model \(model)") }
    }
    for modelClass in model.classes {
      guard let ours = described.first(where: { $0.classID == modelClass.classID }) else {
        differences.append("\(modelClass.name): not described by the device")
        continue
      }
      compare("\(modelClass.name) name", ours.name, modelClass.name)
      for property in modelClass.properties {
        let what = "\(modelClass.name) property \(property.propertyID) \(property.name)"
        guard let mine = ours.properties.first(where: { $0.propertyID == property.propertyID }) else {
          differences.append("\(what): not described by the device"); continue
        }
        compare("\(what) name", mine.name, property.name)
        compare("\(what) type", mine.typeName, property.typeName)
        compare("\(what) read only", "\(mine.isReadOnly)", "\(property.isReadOnly)")
        compare("\(what) static", "\(mine.isStatic)", "\(property.isStatic)")
      }
      for method in modelClass.methods {
        let what = "\(modelClass.name) method \(method.methodID) \(method.name)"
        guard let mine = ours.methods.first(where: { $0.methodID == method.methodID }) else {
          differences.append("\(what): not described by the device"); continue
        }
        compare("\(what) name", mine.name, method.name)
        func signature(_ m: OcaClassMethodDescriptor) -> String {
          m.parameters.map { "\($0.direction) \($0.name.lowercased()): \($0.typeName)" }.joined(separator: ", ")
        }
        compare("\(what) parameters", signature(mine), signature(method))
      }
      for event in modelClass.events {
        let what = "\(modelClass.name) event \(event.eventID) \(event.name)"
        guard let mine = ours.events.first(where: { $0.eventID == event.eventID }) else {
          differences.append("\(what): not described by the device"); continue
        }
        compare("\(what)", "\(mine.name) \(mine.eventDataTypeName)", "\(event.name) \(event.eventDataTypeName)")
      }
    }
    let datatypes = try await manager.getDatatypes(from: controller)
    for datatype in model.datatypes {
      guard let mine = datatypes.first(where: { $0.name == datatype.name }) else {
        differences.append("datatype \(datatype.name): not described by the device"); continue
      }
      compare("datatype \(datatype.name)", "\(mine.kind) \(mine.baseTypeName) \(mine.typeArguments)", "\(datatype.kind) \(datatype.baseTypeName) \(datatype.typeArguments)")
      compare("datatype \(datatype.name) fields", "\(mine.fields.map { "\($0.name): \($0.typeName)" })", "\(datatype.fields.map { "\($0.name): \($0.typeName)" })")
      compare("datatype \(datatype.name) items", "\(mine.items.map { "\($0.name.lowercased())=\($0.value)" })", "\(datatype.items.map { "\($0.name.lowercased())=\($0.value)" })")
    }
    return differences
  }

  func testTheModelIsReadAsAClassManagerWouldDescribeIt() throws {
    let model = try Self.model()
    XCTAssertEqual(model.classes.map(\.name), [
      "OcaRoot", "OcaWorker", "OcaActuator", "OcaGain", "OcaMute", "OcaSensor", "OcaIdentificationSensor",
    ])
    let gain = try XCTUnwrap(model.controlClass(OcaClassID("1.1.1.5"), includeInherited: false))
    XCTAssertEqual(gain.properties, [OcaClassPropertyDescriptor(
      propertyID: OcaPropertyID("4.1"), name: "Gain", typeName: "OcaDB", isReadOnly: false
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
    XCTAssertEqual(try datatype("OcaDB"), OcaDatatypeDescriptor(name: "OcaDB", kind: .typedef, baseTypeName: "OcaFloat32"))
    XCTAssertEqual(try datatype("OcaBoolean").kind, .primitive)
    XCTAssertEqual(try datatype("OcaMuteState").items.map(\.value), [1, 2])
    XCTAssertEqual(try datatype("OcaMuteState").baseTypeName, "OcaUint8")
    XCTAssertEqual(try datatype("OcaDeviceState").kind, .bitset)
    XCTAssertEqual(try datatype("OcaPortID").fields.map(\.name), ["Direction", "Index"])
    XCTAssertEqual(try datatype("OcaPropertyChangedEventData").typeArguments, ["DT"])
    XCTAssertEqual(try datatype("OcaList<OcaPort>").typeArguments, ["OcaPort"])
  }

  /// A device's class manager describes the classes and datatypes of the excerpt as the
  /// model does, but for what is listed here, each for the reason it gives.
  func testADeviceDescribesTheModelsClassesAndDatatypesAsTheModelDoes() async throws {
    let differences = try await Self.differences()
    XCTAssertEqual(differences, [
      // not implemented by SwiftOCADevice, so not described
      "OcaWorker method 2.3 AddPort: not described by the device",
      "OcaWorker method 2.4 DeletePort: not described by the device",
      // SwiftOCA's field names, which OCP.2 sends, are not AES70's; to be renamed
      #"datatype OcaPort fields: device ["Owner: OcaONo", "Id: OcaPortID", "Name: OcaString"], model ["Owner: OcaONo", "ID: OcaPortID", "Role: OcaString"]"#,
      #"datatype OcaPortID fields: device ["Mode: OcaIODirection", "Index: OcaUint16"], model ["Direction: OcaIODirection", "Index: OcaUint16"]"#,
    ])
  }
}

private actor RoundTripController: OcaController {
  nonisolated let flags: OcaControllerFlags = [.supportsLocking]
  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {}
}
