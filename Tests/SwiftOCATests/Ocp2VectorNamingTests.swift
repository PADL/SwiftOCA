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
import XCTest

/// Each stage of naming a vector record's OCP.2 parameters, pinned separately. A
/// vector is a generic record (`OcaVector2D<T>`) whose parameters are named after
/// its fields, so these exercise reflection, encoding, decoding and the client
/// wrapper's own naming in isolation.
final class Ocp2VectorNamingTests: XCTestCase {
  func testReflectionFindsTheVectorFields() {
    XCTAssertEqual(Ocp2Naming.fieldNames(of: OcaVector2D<OcaMatrixCoordinate>.self), ["x", "y"])
  }

  func testEncoderFlattensTheVectorUnderItsFieldNames() throws {
    let object = try Ocp2Encoder().encodeParameters(
      OcaVector2D<OcaMatrixCoordinate>(x: 1, y: 2),
      parameterNames: []
    )
    XCTAssertEqual(object.keys.sorted(), ["X", "Y"])
  }

  func testDecoderReadsTheFlattenedVector() throws {
    let data = try Ocp2JSON.serialize(["X": 1, "Y": 2])
    let value = try Ocp2Decoder().decodeParameters(OcaVector2D<OcaMatrixCoordinate>.self, from: data)
    XCTAssertEqual(value.x, 1)
    XCTAssertEqual(value.y, 2)
  }

  func testVectorStorageBorrowsNoPropertyName() {
    // the storage stands in for two properties, so it must not resolve to any one
    let matrix = OcaMatrix(objectNumber: 0x0001_0200)
    let name = matrix.propertyName(for: OcaPropertyID("0.0"))
    XCTAssertNil(name)
  }
}
#endif
