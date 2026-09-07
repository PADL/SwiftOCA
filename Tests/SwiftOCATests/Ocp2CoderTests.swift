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
@testable import SwiftOCA
import XCTest

/// AES70-4 clause 8 marshaling, and the naming rules SwiftOCA layers on it.
final class Ocp2CoderTests: XCTestCase {
  private func json(_ text: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
  }

  private func object(_ text: String) throws -> [String: Any] {
    try XCTUnwrap(json(text) as? [String: Any])
  }

  // MARK: parameter records

  func testParameterRecordUsesDerivedNames() throws {
    let params = OcaBlock.FindActionObjectsByRoleParameters(
      searchName: "Master Gain",
      nameComparisonType: .exact,
      searchClassID: "1.1.1.5",
      resultFlags: .oNo
    )
    let encoded = try Ocp2Encoder().encodeParameters(params)
    XCTAssertEqual(encoded["SearchName"] as? String, "Master Gain")
    XCTAssertEqual(encoded["NameComparisonType"] as? Int, 0)
    XCTAssertEqual(encoded["SearchClassID"] as? [Int], [1, 1, 1, 5])
    XCTAssertEqual(encoded["ResultFlags"] as? Int, 1)
    XCTAssertEqual(encoded.count, 4)
  }

  func testParameterRecordDecodesSpecExampleA01() throws {
    // example A01, with the enumeration spelled by name
    let parameters = try object("""
    {
      "SearchName" : "Master Gain",
      "NameComparisonType" : "Exact",
      "SearchClassID" : [ 1, 1, 1, 5 ],
      "ResultFlags" : 1
    }
    """)
    let params = try Ocp2Decoder().decodeParameters(
      OcaBlock.FindActionObjectsByRoleParameters.self,
      from: parameters
    )
    XCTAssertEqual(params.searchName, "Master Gain")
    XCTAssertEqual(params.nameComparisonType, .exact)
    XCTAssertEqual(params.searchClassID, "1.1.1.5")
    XCTAssertEqual(params.resultFlags, .oNo)
  }

  func testParameterRecordMatchesNamesCaseInsensitively() throws {
    let parameters = try object("""
    {"searchname": "x", "namecomparisontype": 2, "SEARCHCLASSID": [1, 1], "resultflags": 3}
    """)
    let params = try Ocp2Decoder().decodeParameters(
      OcaBlock.FindActionObjectsByRoleParameters.self,
      from: parameters
    )
    XCTAssertEqual(params.searchName, "x")
    XCTAssertEqual(params.nameComparisonType, .contains)
    XCTAssertEqual(params.searchClassID, "1.1")
  }

  func testExplicitParameterNamesOverrideFieldNames() throws {
    // GetGain returns Gain, minGain, maxGain, which SwiftOCA holds in a generic
    // bounded value whose fields are named value, minValue, maxValue
    let value = OcaBoundedPropertyValue<Float>(value: -3.5, minValue: -100, maxValue: 10)
    let names = Ocp2Naming.boundedWireNames("Gain")
    let encoded = try Ocp2Encoder().encodeParameters(value, parameterNames: names)
    XCTAssertEqual(encoded["Gain"] as? Double, -3.5)
    XCTAssertEqual(encoded["MinGain"] as? Double, -100)
    XCTAssertEqual(encoded["MaxGain"] as? Double, 10)

    let decoded = try Ocp2Decoder().decodeParameters(
      OcaBoundedPropertyValue<Float>.self,
      from: encoded,
      parameterNames: names
    )
    XCTAssertEqual(decoded, value)

    // a peer that spells the names differently still gets through
    let spelledDifferently = try object("""
    {"gain": -3.5, "MinGain": -100, "MAXGAIN": 10}
    """)
    XCTAssertEqual(
      try Ocp2Decoder().decodeParameters(
        OcaBoundedPropertyValue<Float>.self,
        from: spelledDifferently,
        parameterNames: names
      ),
      value
    )
  }

  // MARK: single parameters

  func testSingleParameterIsNamed() throws {
    let encoded = try Ocp2Encoder().encodeParameters(Float(-3.5), parameterNames: ["Gain"])
    XCTAssertEqual(encoded as? [String: Double], ["Gain": -3.5])

    let unnamed = try Ocp2Encoder().encodeParameters(Float(-3.5))
    XCTAssertEqual(unnamed as? [String: Double], [Ocp2Naming.unnamedParameter: -3.5])
  }

  func testSingleParameterIsAcceptedWhateverItsName() throws {
    for text in ["{\"Gain\": -3.5}", "{\"gain\": -3.5}", "{\"Value\": -3.5}", "{\"anything\": -3.5}"] {
      let decoded = try Ocp2Decoder().decodeParameters(
        Float.self,
        from: try object(text),
        parameterNames: ["Gain"]
      )
      XCTAssertEqual(decoded, -3.5, text)
    }
  }

  func testAmbiguousSingleParameterRequiresAName() throws {
    let parameters = try object("{\"a\": 1, \"b\": 2}")
    XCTAssertThrowsError(try Ocp2Decoder().decodeParameters(
      Float.self,
      from: parameters,
      parameterNames: ["Gain"]
    ))
    XCTAssertEqual(
      try Ocp2Decoder().decodeParameters(Int.self, from: parameters, parameterNames: ["b"]),
      2
    )
  }

  func testPlaceholderAndEmptyParameters() throws {
    XCTAssertTrue(try Ocp2Encoder().encodeParameters(OcaRoot.Placeholder()).isEmpty)
    _ = try Ocp2Decoder().decodeParameters(OcaRoot.Placeholder.self, from: nil)
    _ = try Ocp2Decoder().decodeParameters(OcaRoot.Placeholder.self, from: [:])
    let optional: Float? = try Ocp2Decoder().decodeParameters(Float?.self, from: [:])
    XCTAssertNil(optional)
  }

  // MARK: special datatypes

  func testEnumerationsEncodeAsNumbersAndDecodeEitherWay() throws {
    XCTAssertEqual(try Ocp2Encoder().encodeValue(OcaStatus.locked) as? Int, 3)
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaStatus.self, from: 3), .locked)
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaStatus.self, from: "OK"), .ok)
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaStatus.self, from: "locked"), .locked)
    XCTAssertEqual(
      try Ocp2Decoder().decodeValue(OcaPropertyChangeType.self, from: "CurrentChanged"),
      .currentChanged
    )
    XCTAssertThrowsError(try Ocp2Decoder().decodeValue(OcaStatus.self, from: "NoSuchStatus"))
  }

  func testClassIDs() throws {
    let standard: OcaClassID = "1.1.1.5"
    XCTAssertEqual(try Ocp2Encoder().encodeValue(standard) as? [Int], [1, 1, 1, 5])
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaClassID.self, from: [1, 1, 1, 5]), standard)

    let proprietary = OcaClassID(
      parent: standard,
      authority: OcaOrganizationID((0xFA, 0x2A, 0xE9)),
      "2300.1"
    )
    let encoded = try XCTUnwrap(try Ocp2Encoder().encodeValue(proprietary) as? [Any])
    XCTAssertEqual(encoded.count, 7)
    XCTAssertEqual(encoded[4] as? [String], nil)
    let authority = try XCTUnwrap(encoded[4] as? [Any])
    XCTAssertEqual(authority[0] as? Int, 65535)
    XCTAssertEqual(authority[1] as? String, "FA2AE9")
    XCTAssertEqual(encoded[5] as? Int, 2300)
    XCTAssertEqual(encoded[6] as? Int, 1)
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaClassID.self, from: encoded), proprietary)
  }

  func testElementIDs() throws {
    XCTAssertEqual(try Ocp2Encoder().encodeValue(OcaPropertyID("4.1")) as? [Int], [4, 1])
    XCTAssertEqual(try Ocp2Encoder().encodeValue(OcaMethodID("4.2")) as? [Int], [4, 2])
    XCTAssertEqual(try Ocp2Encoder().encodeValue(OcaEventID("1.1")) as? [Int], [1, 1])
    // the optional third element is a comment
    XCTAssertEqual(
      try Ocp2Decoder().decodeValue(OcaPropertyID.self, from: [4, 1, "Gain"] as [Any]),
      OcaPropertyID("4.1")
    )
    XCTAssertEqual(
      try Ocp2Decoder().decodeValue(OcaMethodID.self, from: [4, 2]),
      OcaMethodID("4.2")
    )
    // the other coders are unaffected
    let json = try JSONEncoder().encode(OcaPropertyID("4.1"))
    XCTAssertEqual(try JSONDecoder().decode(OcaPropertyID.self, from: json), OcaPropertyID("4.1"))
    let ocp1 = try Ocp1Encoder().encode(OcaMethodID("4.2")) as [UInt8]
    XCTAssertEqual(ocp1, [0, 4, 0, 2])
  }

  func testBlobsAreBase64() throws {
    let blob = OcaBlob(Data([1, 2, 3]))
    XCTAssertEqual(try Ocp2Encoder().encodeValue(blob) as? String, "AQID")
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaBlob.self, from: "AQID"), blob)
    XCTAssertEqual(try Ocp2Encoder().encodeValue(Data([1, 2, 3])) as? String, "AQID")
    XCTAssertEqual(try Ocp2Decoder().decodeValue(Data.self, from: "AQID"), Data([1, 2, 3]))
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaLongBlob.self, from: "AQID").wrappedValue, Data([1, 2, 3]))
  }

  func testMapsAreArraysOfPairs() throws {
    let map: OcaMap<OcaUint16, OcaString> = [1: "left", 2: "right"]
    let encoded = try XCTUnwrap(try Ocp2Encoder().encodeValue(map) as? [[Any]])
    XCTAssertEqual(encoded.count, 2)
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaMap<OcaUint16, OcaString>.self, from: encoded), map)

    let example = try json("[[\"left\",1],[\"right\",2]]")
    XCTAssertEqual(
      try Ocp2Decoder().decodeValue(OcaMap<OcaString, OcaUint8>.self, from: example),
      ["left": 1, "right": 2]
    )

    let multi: OcaMultiMap<OcaUint16, OcaString> = [1: ["a", "b"]]
    let multiEncoded = try Ocp2Encoder().encodeValue(multi)
    XCTAssertEqual(
      try Ocp2Decoder().decodeValue(OcaMultiMap<OcaUint16, OcaString>.self, from: multiEncoded),
      multi
    )
  }

  func testTwoDimensionalArrays() throws {
    let array = try XCTUnwrap(OcaArray2D(arrayOfArrays: [["a", "b", "c"], ["d", "e", "f"]]))
    let encoded = try Ocp2Encoder().encodeValue(array)
    XCTAssertEqual(encoded as? [[String]], [["a", "b", "c"], ["d", "e", "f"]])
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaArray2D<String>.self, from: encoded), array)
  }

  func testNonFiniteFloats() throws {
    XCTAssertEqual(try Ocp2Encoder().encodeValue(Float.infinity) as? String, "Infinity")
    XCTAssertEqual(try Ocp2Encoder().encodeValue(-Double.infinity) as? String, "-Infinity")
    XCTAssertEqual(try Ocp2Encoder().encodeValue(Float.nan) as? String, "NaN")
    XCTAssertEqual(try Ocp2Decoder().decodeValue(Float.self, from: "Infinity"), .infinity)
    XCTAssertTrue(try Ocp2Decoder().decodeValue(Double.self, from: "NaN").isNaN)
    // a float keeps single precision digits
    XCTAssertEqual(try Ocp2Encoder().encodeValue(Float(0.1)) as? Double, 0.1)
  }

  func testIntegersAreRangeCheckedAndAcceptStrings() throws {
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaONo.self, from: "5000"), 5000)
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaUint8.self, from: 255), 255)
    XCTAssertThrowsError(try Ocp2Decoder().decodeValue(OcaUint8.self, from: 256))
    XCTAssertThrowsError(try Ocp2Decoder().decodeValue(OcaUint8.self, from: -1))
    XCTAssertThrowsError(try Ocp2Decoder().decodeValue(OcaUint8.self, from: 1.5))
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaInt16.self, from: -23), -23)
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaUint64.self, from: UInt64.max), UInt64.max)
  }

  func testOrganizationAndModelIdentifiers() throws {
    let organization = OcaOrganizationID((0xFA, 0x2E, 0xE9))
    XCTAssertEqual(try Ocp2Encoder().encodeValue(organization) as? String, "FA2EE9")
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaOrganizationID.self, from: "FA2EE9"), organization)

    let guid = OcaModelGUID(mfrCode: organization, modelCode: (1, 2, 3, 4))
    let encoded = try XCTUnwrap(try Ocp2Encoder().encodeValue(guid) as? [String: Any])
    XCTAssertEqual(encoded["MfrCode"] as? String, "FA2EE9")
    XCTAssertEqual(encoded["ModelCode"] as? String, "AQIDBA==")
    XCTAssertEqual(encoded["Reserved"] as? Int, 0)
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaModelGUID.self, from: encoded), guid)
  }

  func testCompositeDatatypesAreObjectsKeyedByFieldName() throws {
    let identification = OcaClassIdentification(classID: "1.3", classVersion: 1)
    let encoded = try XCTUnwrap(try Ocp2Encoder().encodeValue(identification) as? [String: Any])
    XCTAssertEqual(encoded["ClassID"] as? [Int], [1, 3])
    XCTAssertEqual(encoded["ClassVersion"] as? Int, 1)
    XCTAssertEqual(try Ocp2Decoder().decodeValue(OcaClassIdentification.self, from: encoded), identification)
  }

  func testPropertyChangedEventData() throws {
    let eventData = OcaPropertyChangedEventData<Float>(
      propertyID: "4.1",
      propertyValue: -3.5,
      changeType: .currentChanged
    )
    let encoded = try XCTUnwrap(try Ocp2Encoder().encodeValue(eventData) as? [String: Any])
    XCTAssertEqual(encoded["PropertyID"] as? [Int], [4, 1])
    XCTAssertEqual(encoded["PropertyValue"] as? Double, -3.5)
    XCTAssertEqual(encoded["ChangeType"] as? Int, 1)

    // example A07
    let example = try object("""
    {
      "PropertyID" : [ 4, 1, "Gain" ],
      "PropertyValue" : -3.5,
      "ChangeType" : "CurrentChanged"
    }
    """)
    let decoded = try Ocp2Decoder().decodeValue(OcaPropertyChangedEventData<Float>.self, from: example)
    XCTAssertEqual(decoded.propertyID, "4.1")
    XCTAssertEqual(decoded.propertyValue, -3.5)
    XCTAssertEqual(decoded.changeType, .currentChanged)
  }

  func testOptionalFieldsAreKeyedNotPositional() throws {
    // OcaActionObjectSearchResult omits fields the flags exclude, so members must
    // be matched by name
    let result = OcaObjectSearchResult(
      oNo: 5000,
      classIdentification: OcaClassIdentification(classID: "1.1.1.5", classVersion: 3),
      containerPath: nil,
      role: nil,
      label: nil
    )
    let flags: OcaActionObjectSearchResultFlags = [.oNo, .classIdentification]
    var encoder = Ocp2Encoder()
    encoder.userInfo[OcaObjectSearchResult.FlagsUserInfoKey] = flags
    let encoded = try XCTUnwrap(try encoder.encodeValue([result] as [OcaObjectSearchResult]) as? [[String: Any]])
    XCTAssertEqual(encoded.count, 1)
    XCTAssertEqual(encoded[0]["ONo"] as? Int, 5000)
    XCTAssertNotNil(encoded[0]["ClassIdentification"])

    var decoder = Ocp2Decoder()
    decoder.userInfo[OcaObjectSearchResult.FlagsUserInfoKey] = flags
    let decoded = try decoder.decodeValue([OcaObjectSearchResult].self, from: encoded)
    XCTAssertEqual(decoded.first?.oNo, 5000)
    XCTAssertEqual(decoded.first?.classIdentification?.classID, "1.1.1.5")
    XCTAssertNil(decoded.first?.role)
  }

  func testWireNames() {
    XCTAssertEqual(Ocp2Naming.wireName("gain"), "Gain")
    XCTAssertEqual(Ocp2Naming.wireName("oNo"), "ONo")
    XCTAssertEqual(Ocp2Naming.wireName("_gain"), "Gain")
    XCTAssertEqual(Ocp2Naming.wireName("SearchName"), "SearchName")
    XCTAssertTrue(Ocp2Naming.matches("minGain", "MINGAIN"))
    XCTAssertTrue(Ocp2Naming.matches("_gain", "Gain"))
    XCTAssertFalse(Ocp2Naming.matches("gain", "gains"))
    XCTAssertEqual(Ocp2Naming.boundedWireNames("Gain"), ["Gain", "MinGain", "MaxGain"])
  }
}
#endif
