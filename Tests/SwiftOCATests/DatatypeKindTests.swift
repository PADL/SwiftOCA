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

final class DatatypeKindTests: XCTestCase {
  private func name(_ type: Any.Type) -> String {
    switch OcaDatatypeKind(of: type) {
    case let .base(base): "base \(base.name)"
    case .blob: "blob"
    case .longBlob: "long blob"
    case let .optional(wrapped): "optional \(wrapped)"
    case let .list(element): "list \(element)"
    case let .map(key, value): "map \(key) \(value)"
    case let .bounded(value): "bounded \(value)"
    case let .enumeration(cases): "enumeration \(cases.count)"
    case let .rawValue(raw): "raw \(raw)"
    case .structure: "structure"
    case .other: "other"
    }
  }

  func testEachKindOfDatatypeIsRecognised() {
    XCTAssertEqual(name(OcaBoolean.self), "base OcaBoolean")
    XCTAssertEqual(name(OcaDB.self), "base OcaFloat32")
    XCTAssertEqual(name(OcaUint8.self), "base OcaUint8")
    XCTAssertEqual(name(OcaString.self), "base OcaString")
    XCTAssertEqual(name(OcaLongBlob.self), "long blob")
    XCTAssertEqual(name(OcaBlob.self), "blob")
    XCTAssertEqual(name(OcaString?.self), "optional String")
    XCTAssertEqual(name(OcaList<OcaUint16>.self), "list UInt16")
    XCTAssertEqual(name(OcaMap<OcaUint16, OcaString>.self), "map UInt16 String")
    XCTAssertEqual(name(OcaBoundedPropertyValue<OcaDB>.self), "bounded Float")
    XCTAssertEqual(name(OcaMuteState.self), "enumeration \(OcaMuteState.allCases.count)")
    XCTAssertEqual(name(OcaPort.self), "structure")
    XCTAssertEqual(name(OcaRoot.self), "other")
  }
}
