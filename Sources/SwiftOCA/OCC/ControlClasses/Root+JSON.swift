//
// Copyright (c) 2024 PADL Software Pty Ltd
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
import AnyCodable
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// JSON has no encoding for non-finite numbers, and on Darwin one reaching
/// NSJSONSerialization raises an unrecoverable ObjC exception. Spell them the
/// way JSONDecoder's .convertFromString accepts, so they survive a round-trip.
package let _nonConformingFloatEncodingStrategy = JSONEncoder.NonConformingFloatEncodingStrategy
  .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")

package let _nonConformingFloatDecodingStrategy = JSONDecoder.NonConformingFloatDecodingStrategy
  .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")

/// A non-finite number in a hand-built JSON container bypasses JSONEncoder;
/// replace it with its .convertFromString spelling.
package func _jsonNonFiniteSafe(_ value: any Sendable) -> any Sendable {
  guard let float = value as? any BinaryFloatingPoint, !float.isFinite else { return value }
  if float.isNaN { return "NaN" }
  return float.sign == .minus ? "-Infinity" : "Infinity"
}

package extension JSONEncoder {
  func reencodeAsValidJSONObject<Value: Codable>(_ value: some Codable) throws -> Value {
    nonConformingFloatEncodingStrategy = _nonConformingFloatEncodingStrategy
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = _nonConformingFloatDecodingStrategy
    let data = try encode(value)
    return try decoder.decode(Value.self, from: data)
  }

  func reencodeAsValidJSONObject(_ value: some Codable) throws -> any Sendable {
    nonConformingFloatEncodingStrategy = _nonConformingFloatEncodingStrategy
    let data = try encode(value)
    return try JSONDecoder().decode(AnyDecodable.self, from: data).value as! any Sendable
  }
}

enum OcaJSONPropertyKeys: String {
  case type
  case members
}
#endif
