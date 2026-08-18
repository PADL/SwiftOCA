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
private let _jsonPositiveInfinity = "Infinity"
private let _jsonNegativeInfinity = "-Infinity"
private let _jsonNaN = "NaN"

/// A JSONEncoder that spells non-finite numbers as strings.
package func _jsonEncoder() -> JSONEncoder {
  let encoder = JSONEncoder()
  encoder.nonConformingFloatEncodingStrategy = .convertToString(
    positiveInfinity: _jsonPositiveInfinity,
    negativeInfinity: _jsonNegativeInfinity,
    nan: _jsonNaN
  )
  return encoder
}

/// A JSONDecoder that revives `_jsonEncoder()`'s non-finite spellings.
package func _jsonDecoder() -> JSONDecoder {
  let decoder = JSONDecoder()
  decoder.nonConformingFloatDecodingStrategy = .convertFromString(
    positiveInfinity: _jsonPositiveInfinity,
    negativeInfinity: _jsonNegativeInfinity,
    nan: _jsonNaN
  )
  return decoder
}

/// A non-finite number in a hand-built JSON container bypasses JSONEncoder;
/// replace it with its .convertFromString spelling.
package func _jsonNonFiniteSafe(_ value: any Sendable) -> any Sendable {
  guard let float = value as? any BinaryFloatingPoint, !float.isFinite else { return value }
  if float.isNaN { return _jsonNaN }
  return float.sign == .minus ? _jsonNegativeInfinity : _jsonPositiveInfinity
}

/// Re-encode `value` for a *typed* destination: non-finite numbers round-trip
/// through their string spelling back to real floats, so the result is NOT
/// necessarily valid for a JSONSerialization container — use the untyped
/// overload when the destination is one.
package func reencodeAsValidJSONObject<Value: Codable>(_ value: some Codable) throws -> Value {
  try _jsonDecoder().decode(Value.self, from: _jsonEncoder().encode(value))
}

/// Re-encode `value` into JSONSerialization-safe types; non-finite numbers
/// come back as their string spelling.
package func reencodeAsValidJSONObject(_ value: some Codable) throws -> any Sendable {
  try JSONDecoder().decode(AnyDecodable.self, from: _jsonEncoder().encode(value))
    .value as! any Sendable
}

enum OcaJSONPropertyKeys: String {
  case type
  case members
}
#endif
