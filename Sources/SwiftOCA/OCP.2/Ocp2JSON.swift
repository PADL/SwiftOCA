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

/// Thin shims over `JSONSerialization`, plus the numeric conversions the coder
/// needs. JSON values are the Foundation container types: `[String: Any]`, `[Any]`,
/// `String`, `Bool`, integers, `Double`, and `NSNull`.
package enum Ocp2JSON {
  /// JSON has no spelling for non-finite numbers; these are the ones
  /// `JSONDecoder.convertFromString` accepts, shared with the property export.
  static let positiveInfinity = "Infinity"
  static let negativeInfinity = "-Infinity"
  static let nan = "NaN"

  package static func serialize(_ object: Any) throws -> Data {
    guard JSONSerialization.isValidJSONObject(object) else {
      throw Ocp1Error.status(.badFormat)
    }
    return try JSONSerialization.data(withJSONObject: object, options: [])
  }

  package static func parse(_ data: Data) throws -> Any {
    do {
      return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
      throw Ocp1Error.status(.badFormat)
    }
  }

  package static func parseObject(_ data: Data) throws -> [String: Any] {
    guard let object = try parse(data) as? [String: Any] else {
      throw Ocp1Error.status(.badFormat)
    }
    return object
  }

  static func isNull(_ json: Any) -> Bool {
    json is NSNull
  }

  // MARK: numbers

  static func integer<I: FixedWidthInteger>(_: I.Type, from json: Any) throws -> I {
    if let bool = json as? Bool, Swift.type(of: json) == Bool.self {
      return bool ? 1 : 0
    }
    if let int = json as? Int, let value = I(exactly: int) {
      return value
    }
    if let int = json as? Int64, let value = I(exactly: int) {
      return value
    }
    if let uint = json as? UInt64, let value = I(exactly: uint) {
      return value
    }
    if let double = json as? Double {
      guard double.isFinite, double == double.rounded(), let value = I(exactly: double) else {
        throw Ocp1Error.status(.parameterOutOfRange)
      }
      return value
    }
    // AES70-4's own examples send an object number as a string
    if let string = json as? String, let value = I(string) {
      return value
    }
    throw Ocp1Error.status(.badFormat)
  }

  static func double(from json: Any) throws -> Double {
    if let double = json as? Double {
      return double
    }
    if let int = json as? Int {
      return Double(int)
    }
    if let int = json as? Int64 {
      return Double(int)
    }
    if let uint = json as? UInt64 {
      return Double(uint)
    }
    if let string = json as? String {
      switch string {
      case positiveInfinity: return .infinity
      case negativeInfinity: return -.infinity
      case nan: return .nan
      default:
        if let value = Double(string) { return value }
      }
    }
    throw Ocp1Error.status(.badFormat)
  }

  static func bool(from json: Any) throws -> Bool {
    if let bool = json as? Bool {
      return bool
    }
    if let int = json as? Int {
      return int != 0
    }
    throw Ocp1Error.status(.badFormat)
  }

  static func string(from json: Any) throws -> String {
    guard let string = json as? String else {
      throw Ocp1Error.status(.badFormat)
    }
    return string
  }

  /// Non-finite doubles are spelled as strings.
  static func json(_ double: Double) -> Any {
    if double.isNaN { return nan }
    if double.isInfinite { return double < 0 ? negativeInfinity : positiveInfinity }
    return double
  }

  /// A float is re-parsed from its shortest decimal spelling so it serialises with
  /// single precision digits rather than a double's 17.
  static func json(_ float: Float) -> Any {
    if float.isNaN { return nan }
    if float.isInfinite { return float < 0 ? negativeInfinity : positiveInfinity }
    return Double(String(float)) ?? Double(float)
  }

  // MARK: blobs

  static func base64(_ data: Data) -> String {
    data.base64EncodedString()
  }

  static func data(from json: Any) throws -> Data {
    if let string = json as? String {
      guard let data = Data(base64Encoded: string) else {
        throw Ocp1Error.status(.badFormat)
      }
      return data
    }
    // tolerate an array of byte values
    if let array = json as? [Any] {
      return try Data(array.map { try integer(UInt8.self, from: $0) })
    }
    throw Ocp1Error.status(.badFormat)
  }
}

/// Lets the JSON export convert coder output into `Sendable` containers.
package extension Ocp2JSON {
  static func sendable(_ json: Any) -> any Sendable {
    switch json {
    case let object as [String: Any]:
      return object.mapValues { sendable($0) }
    case let array as [Any]:
      return array.map { sendable($0) }
    case let string as String:
      return string
    case let bool as Bool where Swift.type(of: json) == Bool.self:
      return bool
    case let int as Int:
      return int
    case let int as Int64:
      return int
    case let uint as UInt64:
      return uint
    case let double as Double:
      return double
    case is NSNull:
      return NSNull()
    default:
      return String(describing: json)
    }
  }
}
#endif
