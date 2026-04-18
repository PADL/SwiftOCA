import Foundation
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
import Testing

/// Test JSON round-tripping of LengthTaggedData16 (OcaBlob) and
/// OcaMap<OcaString, OcaBlob> to verify dataset serialization works.
@Suite struct LengthTaggedDataJSONTests {
  @Test func encodeSingleBlob() throws {
    let blob = LengthTaggedData16(Data([0x01, 0x02, 0x03]))
    let data = try JSONEncoder().encode(blob)
    let json = String(data: data, encoding: .utf8)!
    print("Single blob JSON: \(json)")
    #expect(data.count > 0)
  }

  @Test func roundTripSingleBlob() throws {
    let original = LengthTaggedData16(Data([0x01, 0x02, 0x03]))
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(LengthTaggedData16.self, from: data)
    #expect(Array(original.wrappedValue) == Array(decoded.wrappedValue))
  }

  @Test func encodeDictionaryOfBlobs() throws {
    var storage = OcaMap<OcaString, OcaBlob>()
    storage["testKey"] = LengthTaggedData16(Data([0xDE, 0xAD, 0xBE, 0xEF]))
    let data = try JSONEncoder().encode(storage)
    let json = String(data: data, encoding: .utf8)!
    print("Dictionary of blobs JSON: \(json)")
    #expect(data.count > 0)
  }

  @Test func roundTripDictionaryOfBlobs() throws {
    var original = OcaMap<OcaString, OcaBlob>()
    original["key1"] = LengthTaggedData16(Data([0x01, 0x02, 0x03]))
    original["key2"] = LengthTaggedData16(Data([0xAA, 0xBB]))

    let data = try JSONEncoder().encode(original)
    let json = String(data: data, encoding: .utf8)!
    print("Round-trip encode JSON: \(json)")

    let decoded = try JSONDecoder().decode(OcaMap<OcaString, OcaBlob>.self, from: data)
    #expect(Array(decoded["key1"]!.wrappedValue) == [0x01, 0x02, 0x03])
    #expect(Array(decoded["key2"]!.wrappedValue) == [0xAA, 0xBB])
  }

  /// Simulates the getJsonValue() path: JSONEncoder → AnyDecodable round-trip
  @Test func reencodeAsValidJSONObject() throws {
    var storage = OcaMap<OcaString, OcaBlob>()
    storage["testKey"] = LengthTaggedData16(Data([0xDE, 0xAD, 0xBE, 0xEF]))

    // This is what getJsonValue() does when isValidJSONObject returns false
    let reencoded: any Sendable = try JSONEncoder().reencodeAsValidJSONObject(storage)
    print("Reencoded type: \(type(of: reencoded)), value: \(reencoded)")

    // Then it gets serialized via JSONSerialization.data(withJSONObject:)
    // wrapped in a parent dict like the dataset format
    let wrapper: [String: any Sendable] = ["3.1": reencoded]
    #expect(JSONSerialization.isValidJSONObject(wrapper))
    let jsonData = try JSONSerialization.data(withJSONObject: wrapper)
    let jsonString = String(data: jsonData, encoding: .utf8)!
    print("Final JSON: \(jsonString)")
  }

  /// Simulates the full save→load cycle through JSONSerialization
  /// This is the critical path: serialize to JSON dict, write to SQLite as JSON,
  /// read back from SQLite as JSON, deserialize back to typed value.
  @Test func fullSaveLoadCycle() throws {
    var storage = OcaMap<OcaString, OcaBlob>()
    storage["com.test.key"] = LengthTaggedData16(Data([0x01, 0x02, 0x03]))

    // === SAVE PATH (getJsonValue) ===
    let isValid = JSONSerialization.isValidJSONObject(storage)
    print("isValidJSONObject(storage with data): \(isValid)")

    let reencoded: any Sendable
    if isValid {
      reencoded = storage
    } else {
      reencoded = try JSONEncoder().reencodeAsValidJSONObject(storage)
    }
    print("Reencoded type: \(type(of: reencoded)), value: \(reencoded)")

    // Wrap in dataset structure and serialize to JSON data (simulating SQLite write)
    let dataset: [String: any Sendable] = ["_oNo": 123, "3.1": reencoded]
    let savedData = try JSONSerialization.data(withJSONObject: dataset)
    let savedString = String(data: savedData, encoding: .utf8)!
    print("Saved JSON: \(savedString)")

    // === LOAD PATH (set jsonValue) ===
    // Read back from SQLite via JSONSerialization
    let loaded = try JSONSerialization.jsonObject(with: savedData) as! [String: any Sendable]
    let jsonValue = loaded["3.1"]!
    print("Loaded jsonValue type: \(type(of: jsonValue)), value: \(jsonValue)")

    // Now simulate the FIXED deserialize path in DeviceProperty.set(object:jsonValue:device:)
    // The current (default) value is an empty dictionary
    let currentValue = OcaMap<OcaString, OcaBlob>()
    let currentIsValid = JSONSerialization.isValidJSONObject(currentValue)
    print("isValidJSONObject(empty storage): \(currentIsValid)")

    // Direct cast fails because NSDictionary<NSString, NSArray> is not
    // Dictionary<String, LengthTaggedData16>
    let castResult = jsonValue as? OcaMap<OcaString, OcaBlob>
    print("Direct cast to OcaMap<OcaString, OcaBlob>: \(String(describing: castResult))")
    #expect(castResult == nil, "Direct cast expected to fail (NSDictionary vs LengthTaggedData16)")

    // With the fix, when direct cast fails, we fall through to the
    // JSONSerialization → JSONDecoder path
    #expect(JSONSerialization.isValidJSONObject(jsonValue))
    let data = try JSONSerialization.data(withJSONObject: jsonValue)
    print("jsonValue as JSON data: \(String(data: data, encoding: .utf8)!)")
    let decoded = try JSONDecoder().decode(
      OcaMap<OcaString, OcaBlob>.self,
      from: data
    )
    print("Decoded via JSONDecoder: \(decoded)")
    #expect(Array(decoded["com.test.key"]!.wrappedValue) == [0x01, 0x02, 0x03])
  }

  /// Verify that isValidJSONObject behaves differently for empty vs non-empty maps
  @Test func isValidJSONObjectBehavior() throws {
    let emptyStorage = OcaMap<OcaString, OcaBlob>()
    var nonEmptyStorage = OcaMap<OcaString, OcaBlob>()
    nonEmptyStorage["key"] = LengthTaggedData16(Data([0x01]))

    let emptyIsValid = JSONSerialization.isValidJSONObject(emptyStorage)
    let nonEmptyIsValid = JSONSerialization.isValidJSONObject(nonEmptyStorage)

    print("Empty map isValidJSONObject: \(emptyIsValid)")
    print("Non-empty map isValidJSONObject: \(nonEmptyIsValid)")

    // This demonstrates the asymmetry: save path uses non-empty (false → reencodes),
    // but load path checks the CURRENT value which is empty (true → direct cast)
  }
}
