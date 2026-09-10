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

/// Device objects are `Codable` only because the property and event types that hold
/// them are; decoding one throws a `DecodingError`, rather than trapping or claiming
/// an OCA status.
final class ObjectDecodingTests: XCTestCase {
  @OcaDevice
  private func assertNotDecodable<T: Decodable>(
    _ type: T.Type,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try JSONDecoder().decode(type, from: Data("1".utf8))) { error in
      XCTAssertTrue(error is DecodingError, "\(type): \(error)", file: file, line: line)
    }
  }

  @OcaDevice
  func testDecodingADeviceObjectThrowsDecodingError() async {
    assertNotDecodable(SwiftOCADevice.OcaRoot.self)
    assertNotDecodable(SwiftOCADevice.OcaMatrix<SwiftOCADevice.OcaRoot>.self)
    assertNotDecodable(SwiftOCADevice.OcaDataset.self)
  }
}
