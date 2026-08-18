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
@_spi(SwiftOCAPrivate) import SwiftOCA
@testable import SwiftOCADevice
import XCTest

private final class FloatWorker: SwiftOCADevice.OcaWorker {
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("5.1"),
    getMethodID: OcaMethodID("5.1"),
    setMethodID: OcaMethodID("5.2")
  )
  var level: OcaFloat32 = 0
}

/// A dataset holding non-finite numbers (a gain bounded by -inf dB) must both
/// serialize without crashing NSJSONSerialization and restore to the same
/// values — including after a JSONSerialization round-trip, which on Darwin
/// hands values back as NSString/NSNumber.
final class NonFiniteDatasetTests: XCTestCase {
  private let gainPropertyKey = "4.1"
  private let levelPropertyKey = "5.1"

  func testBoundedNonFiniteValuesRoundTrip() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let gain = try await SwiftOCADevice.OcaGain(
      role: "Gain",
      deviceDelegate: device,
      addToRootBlock: false
    )

    var json = try await gain.serialize()
    json[gainPropertyKey] = ["v": "-Infinity", "l": "-Infinity", "u": OcaDB(20)] as [String: any Sendable]
    try await gain.deserialize(jsonObject: json)

    var value = await gain.gain
    XCTAssertEqual(value.value, -.infinity)
    XCTAssertEqual(value.range, -OcaDB.infinity...20)

    // the reserialized form spells the non-finite values as strings and
    // survives NSJSONSerialization, unlike the raw floats it round-trips
    let reserialized = try await gain.serialize()
    XCTAssertTrue(JSONSerialization.isValidJSONObject(reserialized))
    let bounded = reserialized[gainPropertyKey] as? [String: Any]
    XCTAssertEqual(bounded?["v"] as? String, "-Infinity")
    XCTAssertEqual(bounded?["l"] as? String, "-Infinity")
    XCTAssertEqual(bounded?["u"] as? OcaDB, 20)

    // restore from the wire format: on Darwin JSONSerialization yields
    // NSString/NSNumber values, the exact shapes the restore path must accept
    let data = try JSONSerialization.data(withJSONObject: reserialized)
    let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Sendable]
    try await gain.deserialize(jsonObject: decoded)

    value = await gain.gain
    XCTAssertEqual(value.value, -.infinity)
    XCTAssertEqual(value.range, -OcaDB.infinity...20)
  }

  func testBoundedRestoreRejectsOutOfRangeValue() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let gain = try await SwiftOCADevice.OcaGain(
      role: "Gain",
      deviceDelegate: device,
      addToRootBlock: false
    )

    var json = try await gain.serialize()
    json[gainPropertyKey] = ["v": OcaDB(100), "l": OcaDB(0), "u": OcaDB(10)] as [String: any Sendable]
    do {
      try await gain.deserialize(jsonObject: json)
      XCTFail("expected out-of-range value to be rejected")
    } catch Ocp1Error.status(.parameterOutOfRange) {}

    json[gainPropertyKey] = ["v": "NaN", "l": OcaDB(0), "u": OcaDB(10)] as [String: any Sendable]
    do {
      try await gain.deserialize(jsonObject: json)
      XCTFail("expected NaN value to be rejected")
    } catch Ocp1Error.status(.parameterOutOfRange) {}
  }

  func testScalarNonFiniteValueRoundTrips() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let worker = try await FloatWorker(
      role: "Worker",
      deviceDelegate: device,
      addToRootBlock: false
    )

    var json = try await worker.serialize()
    json[levelPropertyKey] = "NaN"
    try await worker.deserialize(jsonObject: json)
    var level = await worker.level
    XCTAssertTrue(level.isNaN)

    let reserialized = try await worker.serialize()
    XCTAssertTrue(JSONSerialization.isValidJSONObject(reserialized))
    XCTAssertEqual(reserialized[levelPropertyKey] as? String, "NaN")

    // a saved scalar fragment must restore after the NSString round-trip that
    // previously fell through every branch of set(object:jsonValue:device:)
    let data = try JSONSerialization.data(withJSONObject: reserialized)
    let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Sendable]
    try await worker.deserialize(jsonObject: decoded)
    level = await worker.level
    XCTAssertTrue(level.isNaN)
  }
}
