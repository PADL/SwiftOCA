//
// Copyright (c) 2024-2026 PADL Software Pty Ltd
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
import XCTest

/// A client class isolated to a global actor, whose property storage Swift lets key paths
/// reach only on that actor.
@OcaConnectionActor
@OcaClass
private final class IsolatedGain: SwiftOCA.OcaActuator, @unchecked Sendable {
  override class var classID: OcaClassID { OcaClassID("1.1.1.5") }

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  var gain: OcaBoundedProperty<OcaDB>.PropertyValue
}

final class PropertyTableTests: XCTestCase {
  func testAClassListsItsPropertiesAfterItsParents() {
    let names = Set(SwiftOCA.OcaGain.propertyKeyPaths.keys)
    XCTAssertTrue(names.isSuperset(of: ["gain", "enabled", "label", "role", "lockable"]))
  }

  func testAMethodsTypesAreNamedAsItsSignatureWritesThem() {
    let getReading = SwiftOCA.OcaLevelSensor.Methods.getReading.erased
    XCTAssertEqual(getReading.resultTypeNames, ["OcaDB"])
    XCTAssertNil(getReading.parameterTypeNames)
  }

  @OcaConnectionActor
  func testAnIsolatedClassListsItsProperties() async {
    let object = IsolatedGain(objectNumber: 0x1000)
    let keyPaths = IsolatedGain.propertyKeyPaths
    XCTAssertTrue(Set(keyPaths.keys).isSuperset(of: ["gain", "enabled", "role"]))
    // the table reaches the property's storage
    let gain = await object.allPropertyKeyPaths["gain"]
    XCTAssertTrue(gain.map { object[keyPath: $0] is any OcaPropertySubjectRepresentable } ?? false)
  }
}
