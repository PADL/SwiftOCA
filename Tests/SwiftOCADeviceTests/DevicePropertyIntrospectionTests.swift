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
@preconcurrency import XCTest

/// A Swift subclass that adds behaviour but is the same OCA class as its parent.
private final class _RelabelledGain: SwiftOCADevice.OcaGain {}

/// A proprietary subclass, which defines a property at the level below its parent's.
private final class _TrimmedGain: SwiftOCADevice.OcaGain {
  override class var classID: OcaClassID {
    OcaClassID(parent: super.classID, authority: OcaClassID.OcaAllianceCompanyID, 1)
  }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("5.1"),
    getMethodID: OcaMethodID("5.1"),
    setMethodID: OcaMethodID("5.2")
  )
  var trim: OcaDB = 0
}

final class DevicePropertyIntrospectionTests: XCTestCase {
  @OcaDevice
  private func makeGain<T: SwiftOCADevice.OcaGain>(_ type: T.Type = T.self) async throws -> T {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    return try await T(role: "Gain", deviceDelegate: device, addToRootBlock: true)
  }

  @OcaDevice
  func testDescribesDeclaredProperties() async throws {
    let gain: SwiftOCADevice.OcaGain = try await makeGain()
    let properties = gain.devicePropertyDescriptions
    XCTAssertEqual(properties.map(\.propertyID), properties.map(\.propertyID).sorted())

    let enabled = try XCTUnwrap(properties.first { $0.name == "enabled" })
    XCTAssertEqual(enabled.propertyID, OcaPropertyID("2.1"))
    XCTAssertEqual(enabled.getMethodID, OcaMethodID("2.1"))
    XCTAssertEqual(enabled.setMethodID, OcaMethodID("2.2"))
    XCTAssertTrue(enabled.isSettable)
    XCTAssertTrue(enabled.valueType == Bool.self)
    XCTAssertEqual(enabled.ocp2GetNames, ["Enabled"])
    XCTAssertEqual(enabled.ocp2SetName, "Enabled")

    // the model's own spelling where the declaration gives one
    let ports = try XCTUnwrap(properties.first { $0.name == "ports" })
    XCTAssertEqual(ports.ocp2GetNames, ["OcaPorts"])
    XCTAssertFalse(ports.isSettable)
    XCTAssertTrue(ports.valueType == [OcaPort].self)
  }

  @OcaDevice
  func testABoundedPropertyIsDescribedByItsValue() async throws {
    let gain: SwiftOCADevice.OcaGain = try await makeGain()
    let property = try XCTUnwrap(gain.devicePropertyDescriptions.first { $0.name == "gain" })
    XCTAssertEqual(property.propertyID, OcaPropertyID("4.1"))
    XCTAssertTrue(property.valueType == OcaDB.self)
    XCTAssertEqual(property.ocp2GetNames, ["Gain", "MinGain", "MaxGain"])
    XCTAssertEqual(property.ocp2SetName, "Gain")
  }

  @OcaDevice
  func testPropertiesAreGroupedByTheClassThatDefinesThem() async throws {
    let gain: SwiftOCADevice.OcaGain = try await makeGain()
    let classes = gain.deviceClassDescriptions
    XCTAssertEqual(classes.map(\.classID), ["1", "1.1", "1.1.1", "1.1.1.5"])
    XCTAssertTrue(classes.last?.type == SwiftOCADevice.OcaGain.self)
    XCTAssertEqual(classes.last?.properties.map(\.name), ["gain"])
    XCTAssertTrue(classes[1].properties.contains { $0.name == "enabled" })
    XCTAssertEqual(
      classes.flatMap(\.properties).map(\.propertyID),
      gain.devicePropertyDescriptions.map(\.propertyID)
    )
  }

  @OcaDevice
  func testASwiftSubclassWithItsParentsClassIDIsTheSameClass() async throws {
    let gain: _RelabelledGain = try await makeGain()
    let classes = gain.deviceClassDescriptions
    XCTAssertEqual(classes.map(\.classID), ["1", "1.1", "1.1.1", "1.1.1.5"])
    XCTAssertTrue(classes.last?.type == SwiftOCADevice.OcaGain.self)
  }

  @OcaDevice
  func testAProprietarySubclassDefinesPropertiesAtItsOwnLevel() async throws {
    let gain: _TrimmedGain = try await makeGain()
    let classes = gain.deviceClassDescriptions
    XCTAssertEqual(classes.count, 5)
    XCTAssertEqual(classes.last?.classID, _TrimmedGain.classID)
    XCTAssertEqual(classes.last?.properties.map(\.name), ["trim"])
    XCTAssertEqual(classes[3].properties.map(\.name), ["gain"])
  }

  func testFieldNamesFollowTheEncoder() throws {
    XCTAssertEqual(Ocp2Encoder.fieldName("sourcePort"), "SourcePort")
    let encoded = try XCTUnwrap(Ocp2Encoder().encodeValue(OcaPortID(mode: .input, index: 1))
      as? [String: Any])
    XCTAssertEqual(Set(encoded.keys), [Ocp2Encoder.fieldName("mode"), Ocp2Encoder.fieldName("index")])
  }
}
