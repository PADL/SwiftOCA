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

/// Writes class manager descriptors as XMI and reads them back.
final class XMIExportTests: XCTestCase {
  /// A device with objects of several kinds of class, among them a deprecated one.
  @OcaDevice
  static func device() async throws -> (OcaDevice, SwiftOCADevice.OcaClassManager) {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await SwiftOCADevice.OcaGain(role: "Gain", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaMute(role: "Mute", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaSwitch(role: "Switch", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaLevelSensor(role: "Level", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaIdentificationSensor(role: "Identify", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaDelayExtended(role: "Delay", deviceDelegate: device)
    _ = try await SwiftOCADevice.OcaTimeSource(role: "Time", deviceDelegate: device)
    // made after the objects, so it describes what the device already has
    return try await (device, SwiftOCADevice.OcaClassManager(deviceDelegate: device))
  }

  /// Each way `ours` and `theirs` differ, by element, so a failure says where.
  private static func differences(
    _ ours: (classes: [OcaClassDescriptor], datatypes: [OcaDatatypeDescriptor]),
    _ theirs: (classes: [OcaClassDescriptor], datatypes: [OcaDatatypeDescriptor])
  ) -> [String] {
    var differences = [String]()
    if ours.classes.map(\.name) != theirs.classes.map(\.name) {
      differences.append("classes: \(ours.classes.map(\.name)) vs \(theirs.classes.map(\.name))")
    }
    for (a, b) in zip(ours.classes, theirs.classes) where a != b {
      for (p, q) in zip(a.properties, b.properties) where p != q { differences.append("\(a.name) property: \(p) vs \(q)") }
      for (m, n) in zip(a.methods, b.methods) where m != n { differences.append("\(a.name) method: \(m) vs \(n)") }
      for (e, f) in zip(a.events, b.events) where e != f { differences.append("\(a.name) event: \(e) vs \(f)") }
      if a.properties.count != b.properties.count || a.methods.count != b.methods.count || a.events.count != b.events.count
        || a.classVersion != b.classVersion || a.isDeprecated != b.isDeprecated || a.documentation != b.documentation
      {
        differences.append("\(a.name): \(a) vs \(b)")
      }
    }
    let theirTypes = Dictionary(theirs.datatypes.map { ($0.name, $0) }) { first, _ in first }
    for d in ours.datatypes where theirTypes[d.name] != d {
      differences.append("datatype \(d.name): \(d) vs \(theirTypes[d.name].map { "\($0)" } ?? "missing")")
    }
    let ourNames = Set(ours.datatypes.map(\.name))
    for d in theirs.datatypes where !ourNames.contains(d.name) {
      differences.append("datatype \(d.name): only read back")
    }
    return differences
  }

  @OcaDevice
  func testADevicesDescriptorsReadBackAsWritten() async throws {
    let (device, manager) = try await Self.device()
    defer { withExtendedLifetime(device) {} }
    let classes = manager.controlClasses
    let datatypes = manager.datatypes
    XCTAssertGreaterThan(classes.count, 10)
    XCTAssertGreaterThan(datatypes.count, 50)
    XCTAssertTrue(classes.contains(where: \.isDeprecated))
    let document = OcaXMIExport.document(classes: classes, datatypes: datatypes)
    let model = try OcaXMIModel(data: Data(document.utf8))
    XCTAssertEqual(Self.differences((classes, datatypes), (model.classes, model.datatypes)), [])
    XCTAssertEqual(model.classes, classes)
    XCTAssertEqual(model.datatypes, datatypes)
  }

  func testTheModelReadsBackAsWritten() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "AES70-2-excerpt", withExtension: "xmi", subdirectory: "Resources"))
    let model = try OcaXMIModel(contentsOf: url)
    let document = OcaXMIExport.document(classes: model.classes, datatypes: model.datatypes)
    let again = try OcaXMIModel(data: Data(document.utf8))
    XCTAssertEqual(Self.differences((model.classes, model.datatypes), (again.classes, again.datatypes)), [])
    XCTAssertEqual(again.classes, model.classes)
    XCTAssertEqual(again.datatypes, model.datatypes)
  }

  @OcaDevice
  func testTheSameModelWritesTheSameDocument() async throws {
    let (device, manager) = try await Self.device()
    defer { withExtendedLifetime(device) {} }
    let first = OcaXMIExport.document(classes: manager.controlClasses, datatypes: manager.datatypes)
    let second = OcaXMIExport.document(classes: manager.controlClasses, datatypes: manager.datatypes)
    XCTAssertEqual(first, second)
    XCTAssertTrue(first.contains(#"<uml:Model xmi:type="uml:Model" name="Device""#))
  }
}
