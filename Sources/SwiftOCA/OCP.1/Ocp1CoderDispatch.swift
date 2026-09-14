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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A type the OCP.1 coder marshals itself rather than through `Codable`: `Data`,
/// written raw; lists and maps, prefixed by a count; and blobs, prefixed by a
/// length and moved in bulk.
///
/// The coders look this up on the static type of a value, so an `Optional`
/// reaches its wrapped type through `Optional`'s own conformance, the same way in
/// both directions.
protocol _Ocp1CoderSpecial {
  static func _ocp1Encode(_ value: Self, into encoder: Ocp1EncoderImpl) throws
  static func _ocp1Decode(from decoder: Ocp1DecoderImpl) throws -> Self
}

extension _Ocp1CoderSpecial {
  /// For a coder holding the type only as `any _Ocp1CoderSpecial.Type`, where
  /// `value` is known to be a `Self`.
  static func _ocp1Encode(unchecked value: some Any, into encoder: Ocp1EncoderImpl) throws {
    try _ocp1Encode(value as! Self, into: encoder)
  }

  /// For a coder holding the type only as `any _Ocp1CoderSpecial.Type`, where
  /// `T` is known to be `Self`.
  static func _ocp1Decode<T>(unchecked _: T.Type, from decoder: Ocp1DecoderImpl) throws -> T {
    try _ocp1Decode(from: decoder) as! T
  }
}

// Both casts are made out of line, on the erased metatype: see `erasedCast` in
// Ocp2Decoder.swift for the optimiser bug this avoids.

@inline(never)
func _ocp1CoderSpecialType(_ type: Any.Type) -> (any _Ocp1CoderSpecial.Type)? {
  type as? any _Ocp1CoderSpecial.Type
}

@inline(never)
func _ocp1IsLongList(_ type: Any.Type) -> Bool {
  type is any Ocp1LongList.Type
}

extension Data: _Ocp1CoderSpecial {
  /// Raw, with no length: on decode, a `Data` takes the rest of the input.
  static func _ocp1Encode(_ value: Data, into encoder: Ocp1EncoderImpl) throws {
    value.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
      encoder.appendBytes(buffer)
    }
  }

  static func _ocp1Decode(from decoder: Ocp1DecoderImpl) throws -> Data {
    decoder.decodeRemainingBytes()
  }
}

extension Array: _Ocp1CoderSpecial where Element: Codable {
  static func _ocp1Encode(_ value: [Element], into encoder: Ocp1EncoderImpl) throws {
    try encoder.encodeCount(value.count, of: Self.self)
    // the element type is looked up once, not per element
    if let special = _ocp1CoderSpecialType(Element.self) {
      for element in value {
        try special._ocp1Encode(unchecked: element, into: encoder)
      }
    } else {
      for element in value {
        try element.encode(to: encoder)
      }
    }
  }

  static func _ocp1Decode(from decoder: Ocp1DecoderImpl) throws -> [Element] {
    let count = try decoder.decodeCount(of: Self.self)
    var array = [Element]()
    // the count is untrusted, so reserve no more than the input could hold
    array.reserveCapacity(Swift.min(count, decoder.remainingCount))
    if let special = _ocp1CoderSpecialType(Element.self) {
      for _ in 0..<count {
        try array.append(special._ocp1Decode(unchecked: Element.self, from: decoder))
      }
    } else {
      for _ in 0..<count {
        try array.append(Element(from: decoder))
      }
    }
    return array
  }
}

extension Dictionary: _Ocp1CoderSpecial where Key: Codable, Value: Codable {
  static func _ocp1Encode(_ value: [Key: Value], into encoder: Ocp1EncoderImpl) throws {
    try encoder.encodeCount(value.count, of: Self.self)
    for (key, element) in value {
      try encoder.encode(key)
      try encoder.encode(element)
    }
  }

  static func _ocp1Decode(from decoder: Ocp1DecoderImpl) throws -> [Key: Value] {
    let count = try decoder.decodeCount(of: Self.self)
    var dictionary = [Key: Value]()
    dictionary.reserveCapacity(Swift.min(count, decoder.remainingCount))
    for _ in 0..<count {
      let key = try decoder.decode(Key.self)
      let value = try decoder.decode(Value.self)
      // a map is a set of items identified by key: the first of a duplicate wins
      if dictionary.index(forKey: key) == nil {
        dictionary[key] = value
      }
    }
    return dictionary
  }
}

extension Ocp1BlobRepresentable {
  static func _ocp1Encode(_ value: Self, into encoder: Ocp1EncoderImpl) throws {
    try encoder.encodeBlob(value.blobData, lengthTagWidth: lengthTagWidth)
  }

  static func _ocp1Decode(from decoder: Ocp1DecoderImpl) throws -> Self {
    try Self(blobData: decoder.decodeBlob(lengthTagWidth: lengthTagWidth))
  }
}
