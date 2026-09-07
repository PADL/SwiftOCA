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

/// Decodes OCA values from JSON per AES70-4 clause 8, leniently: member names match
/// case-insensitively, a single-parameter object is accepted whatever its member is
/// called, enumerations may be spelled by name or number, and an integer may arrive
/// as a string.
public struct Ocp2Decoder {
  public var userInfo: [CodingUserInfoKey: Any] = [:]

  public init() {}

  /// Decodes a method's parameters from the OCP.2 `Parameters` object. `nil` stands
  /// for an omitted `Parameters` member.
  public func decodeParameters<T: Decodable>(
    _ type: T.Type,
    from object: [String: Any]?,
    parameterNames: [String]? = nil
  ) throws -> T {
    let object = object ?? [:]
    let state = Ocp2DecodingState(userInfo: userInfo)

    if type is OcaRoot.Placeholder.Type {
      return OcaRoot.Placeholder() as! T
    }

    if type is Ocp1ParametersReflectable.Type {
      let fieldNames = Ocp2Naming.fieldNames(of: type)
      let names = Ocp2Naming.parameterNames(explicit: parameterNames, fieldNames: fieldNames)
      let frame = Ocp2NamingFrame(parameterNames: names, fieldNames: fieldNames)
      return try T(from: Ocp2DecoderImpl(state: state, json: object, codingPath: [], frame: frame))
    }

    // a single parameter: by name if we can find it, else the sole member
    let name = parameterNames?.first ?? Ocp2Naming.unnamedParameter
    if let json = Self.member(named: name, in: object) {
      return try state.decode(type, from: json, codingPath: [])
    }
    if object.count == 1, let json = object.values.first {
      return try state.decode(type, from: json, codingPath: [])
    }
    if object.isEmpty, let optional = type as? any ExpressibleByNilLiteral.Type {
      return optional.init(nilLiteral: ()) as! T
    }
    throw Ocp1Error.status(.parameterError)
  }

  public func decodeParameters<T: Decodable>(
    _ type: T.Type,
    from data: Data,
    parameterNames: [String]? = nil
  ) throws -> T {
    let object: [String: Any]? = data.isEmpty ? nil : try Ocp2JSON.parseObject(data)
    return try decodeParameters(type, from: object, parameterNames: parameterNames)
  }

  /// Decodes a free-standing value.
  public func decodeValue<T: Decodable>(_ type: T.Type, from json: Any) throws -> T {
    try Ocp2DecodingState(userInfo: userInfo).decode(type, from: json, codingPath: [])
  }

  static func member(named name: String, in object: [String: Any]) -> Any? {
    if let json = object[name] {
      return json
    }
    for (key, json) in object where Ocp2Naming.matches(key, name) {
      return json
    }
    return nil
  }
}

final class Ocp2DecodingState {
  let userInfo: [CodingUserInfoKey: Any]

  init(userInfo: [CodingUserInfoKey: Any]) {
    self.userInfo = userInfo
  }

  func decode<T: Decodable>(
    _ type: T.Type,
    from json: Any,
    codingPath: [any CodingKey]
  ) throws -> T {
    if type == Data.self {
      return try Ocp2JSON.data(from: json) as! T
    }
    // identifier datatypes have array or string forms (AES70-4 8.11.1)
    if type == OcaPropertyID.self {
      let (defLevel, index) = try _ocp2ElementID(from: json)
      return OcaPropertyID(defLevel: defLevel, propertyIndex: index) as! T
    }
    if type == OcaMethodID.self {
      let (defLevel, index) = try _ocp2ElementID(from: json)
      return OcaMethodID(defLevel: defLevel, methodIndex: index) as! T
    }
    if type == OcaEventID.self {
      let (defLevel, index) = try _ocp2ElementID(from: json)
      return OcaEventID(defLevel: defLevel, eventIndex: index) as! T
    }
    if type == OcaClassID.self {
      return try OcaClassID(ocp2JSON: json) as! T
    }
    if type == OcaOrganizationID.self {
      return try OcaOrganizationID(Ocp2JSON.string(from: json)) as! T
    }
    if let blobType = type as? any Ocp1BlobRepresentable.Type {
      return try blobType.init(blobData: Ocp2JSON.data(from: json)) as! T
    }
    if let mapType = type as? any Ocp1MapRepresentable.Type {
      return try mapType.init(ocp2State: self, json: json, codingPath: codingPath) as! T
    }
    if let string = json as? String, let enumType = type as? any CaseIterable.Type {
      // an enumeration spelled by name: match the Swift case name
      if let value = Self.enumCase(named: string, of: enumType) as? T {
        return value
      }
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return try T(from: Ocp2DecoderImpl(state: self, json: json, codingPath: codingPath, frame: nil))
  }

  private static func enumCase(named name: String, of type: any CaseIterable.Type) -> Any? {
    func cases(_ type: (some CaseIterable).Type) -> [Any] {
      type.allCases.map { $0 }
    }
    return cases(type).first { Ocp2Naming.matches(String(describing: $0), name) }
  }
}

struct Ocp2DecoderImpl: Decoder {
  let state: Ocp2DecodingState
  let json: Any
  let codingPath: [any CodingKey]
  let frame: Ocp2NamingFrame?

  var userInfo: [CodingUserInfoKey: Any] {
    state.userInfo
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    guard let object = json as? [String: Any] else {
      throw DecodingError.typeMismatch(
        [String: Any].self,
        .init(codingPath: codingPath, debugDescription: "expected a JSON object")
      )
    }
    return .init(KeyedOcp2DecodingContainer(
      state: state,
      object: object,
      codingPath: codingPath,
      frame: frame
    ))
  }

  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    guard let array = json as? [Any] else {
      throw DecodingError.typeMismatch(
        [Any].self,
        .init(codingPath: codingPath, debugDescription: "expected a JSON array")
      )
    }
    return UnkeyedOcp2DecodingContainer(state: state, array: array, codingPath: codingPath)
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    SingleValueOcp2DecodingContainer(state: state, json: json, codingPath: codingPath)
  }
}

package extension Decoder {
  var _isOcp2Decoder: Bool {
    self is Ocp2DecoderImpl
  }
}

struct KeyedOcp2DecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let state: Ocp2DecodingState
  let object: [String: Any]
  let codingPath: [any CodingKey]
  let frame: Ocp2NamingFrame?

  var allKeys: [Key] {
    object.keys.compactMap { Key(stringValue: $0) }
  }

  /// The member for `key`: by its model name when this is a parameter record, then by
  /// its derived wire name, then by its Swift name, all case-insensitively; finally, a
  /// one-field record accepts a one-member object whatever the member is called.
  private func lookup(_ key: Key) -> Any? {
    let swiftName = key.stringValue
    if let frame, let name = frame.wireName(for: key),
       let json = Ocp2Decoder.member(named: name, in: object)
    {
      return json
    }
    // the derived wire name differs from the Swift name only in its first letter,
    // so one case-insensitive search covers both
    if let json = Ocp2Decoder.member(named: swiftName, in: object) {
      return json
    }
    if let frame, frame.fieldNames.count == 1, object.count == 1 {
      return object.values.first
    }
    return nil
  }

  private func require(_ key: Key) throws -> Any {
    guard let json = lookup(key) else {
      throw DecodingError.keyNotFound(
        key,
        .init(codingPath: codingPath, debugDescription: "no member for \(key.stringValue)")
      )
    }
    return json
  }

  func contains(_ key: Key) -> Bool {
    lookup(key) != nil
  }

  func decodeNil(forKey key: Key) throws -> Bool {
    guard let json = lookup(key) else { return true }
    return Ocp2JSON.isNull(json)
  }

  func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
    try Ocp2JSON.bool(from: require(key))
  }

  func decode(_ type: String.Type, forKey key: Key) throws -> String {
    try Ocp2JSON.string(from: require(key))
  }

  func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
    try Ocp2JSON.double(from: require(key))
  }

  func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
    try Float(Ocp2JSON.double(from: require(key)))
  }

  func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
    try Ocp2JSON.integer(
      type,
      from: require(key)
    )
  }

  func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
    try Ocp2JSON.integer(
      type,
      from: require(key)
    )
  }

  func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
    try Ocp2JSON.integer(
      type,
      from: require(key)
    )
  }

  func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
    try Ocp2JSON.integer(
      type,
      from: require(key)
    )
  }

  func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
    try Ocp2JSON.integer(
      type,
      from: require(key)
    )
  }

  func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
    try Ocp2JSON.integer(
      type,
      from: require(key)
    )
  }

  func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
    try Ocp2JSON.integer(
      type,
      from: require(key)
    )
  }

  func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
    try Ocp2JSON.integer(
      type,
      from: require(key)
    )
  }

  func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
    try Ocp2JSON.integer(
      type,
      from: require(key)
    )
  }

  func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
    try Ocp2JSON.integer(
      type,
      from: require(key)
    )
  }

  func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
    try state.decode(type, from: require(key), codingPath: codingPath + [key])
  }

  func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type,
    forKey key: Key
  ) throws -> KeyedDecodingContainer<NestedKey> {
    try Ocp2DecoderImpl(
      state: state,
      json: require(key),
      codingPath: codingPath + [key],
      frame: nil
    )
    .container(keyedBy: type)
  }

  func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
    try Ocp2DecoderImpl(
      state: state,
      json: require(key),
      codingPath: codingPath + [key],
      frame: nil
    )
    .unkeyedContainer()
  }

  func superDecoder() throws -> any Decoder {
    Ocp2DecoderImpl(state: state, json: object, codingPath: codingPath, frame: nil)
  }

  func superDecoder(forKey key: Key) throws -> any Decoder {
    try Ocp2DecoderImpl(
      state: state,
      json: require(key),
      codingPath: codingPath + [key],
      frame: nil
    )
  }
}

struct UnkeyedOcp2DecodingContainer: UnkeyedDecodingContainer {
  let state: Ocp2DecodingState
  let array: [Any]
  let codingPath: [any CodingKey]
  private(set) var currentIndex = 0

  init(state: Ocp2DecodingState, array: [Any], codingPath: [any CodingKey]) {
    self.state = state
    self.array = array
    self.codingPath = codingPath
  }

  var count: Int? {
    array.count
  }

  var isAtEnd: Bool {
    currentIndex >= array.count
  }

  private func peek() throws -> Any {
    guard !isAtEnd else {
      throw DecodingError.valueNotFound(
        Any.self,
        .init(codingPath: codingPath, debugDescription: "unkeyed container is at end")
      )
    }
    return array[currentIndex]
  }

  /// The element is consumed only if `convert` succeeds, so a caller can probe
  /// one representation and fall back to another.
  private mutating func take<T>(_ convert: (Any) throws -> T) throws -> T {
    let value = try convert(peek())
    currentIndex += 1
    return value
  }

  mutating func decodeNil() throws -> Bool {
    guard !isAtEnd else { return true }
    if Ocp2JSON.isNull(array[currentIndex]) {
      currentIndex += 1
      return true
    }
    return false
  }

  mutating func decode(_ type: Bool.Type) throws -> Bool {
    try take { try Ocp2JSON.bool(from: $0) }
  }

  mutating func decode(_ type: String
    .Type) throws -> String
  {
    try take { try Ocp2JSON.string(from: $0) }
  }

  mutating func decode(_ type: Double
    .Type) throws -> Double
  {
    try take { try Ocp2JSON.double(from: $0) }
  }

  mutating func decode(_ type: Float
    .Type) throws -> Float
  {
    try take { try Float(Ocp2JSON.double(from: $0)) }
  }

  mutating func decode(_ type: Int.Type) throws -> Int {
    try take { try Ocp2JSON.integer(
      type,
      from: $0
    ) }
  }

  mutating func decode(_ type: Int8.Type) throws -> Int8 {
    try take { try Ocp2JSON.integer(
      type,
      from: $0
    ) }
  }

  mutating func decode(_ type: Int16.Type) throws -> Int16 {
    try take { try Ocp2JSON.integer(
      type,
      from: $0
    ) }
  }

  mutating func decode(_ type: Int32.Type) throws -> Int32 {
    try take { try Ocp2JSON.integer(
      type,
      from: $0
    ) }
  }

  mutating func decode(_ type: Int64.Type) throws -> Int64 {
    try take { try Ocp2JSON.integer(
      type,
      from: $0
    ) }
  }

  mutating func decode(_ type: UInt.Type) throws -> UInt {
    try take { try Ocp2JSON.integer(
      type,
      from: $0
    ) }
  }

  mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
    try take { try Ocp2JSON.integer(
      type,
      from: $0
    ) }
  }

  mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
    try take { try Ocp2JSON.integer(
      type,
      from: $0
    ) }
  }

  mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
    try take { try Ocp2JSON.integer(
      type,
      from: $0
    ) }
  }

  mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
    try take { try Ocp2JSON.integer(
      type,
      from: $0
    ) }
  }

  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let (state, codingPath) = (state, codingPath)
    return try take { try state.decode(type, from: $0, codingPath: codingPath) }
  }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type
  ) throws -> KeyedDecodingContainer<NestedKey> {
    let (state, codingPath) = (state, codingPath)
    return try take {
      try Ocp2DecoderImpl(state: state, json: $0, codingPath: codingPath, frame: nil)
        .container(keyedBy: type)
    }
  }

  mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
    let (state, codingPath) = (state, codingPath)
    return try take {
      try Ocp2DecoderImpl(state: state, json: $0, codingPath: codingPath, frame: nil)
        .unkeyedContainer()
    }
  }

  mutating func superDecoder() throws -> any Decoder {
    let (state, codingPath) = (state, codingPath)
    return try take { Ocp2DecoderImpl(state: state, json: $0, codingPath: codingPath, frame: nil) }
  }
}

struct SingleValueOcp2DecodingContainer: SingleValueDecodingContainer {
  let state: Ocp2DecodingState
  let json: Any
  let codingPath: [any CodingKey]

  func decodeNil() -> Bool {
    Ocp2JSON.isNull(json)
  }

  func decode(_ type: Bool.Type) throws -> Bool {
    try Ocp2JSON.bool(from: json)
  }

  func decode(_ type: String.Type) throws -> String {
    try Ocp2JSON.string(from: json)
  }

  func decode(_ type: Double.Type) throws -> Double {
    try Ocp2JSON.double(from: json)
  }

  func decode(_ type: Float.Type) throws -> Float {
    try Float(Ocp2JSON.double(from: json))
  }

  func decode(_ type: Int.Type) throws -> Int {
    try Ocp2JSON.integer(type, from: json)
  }

  func decode(_ type: Int8.Type) throws -> Int8 {
    try Ocp2JSON.integer(type, from: json)
  }

  func decode(_ type: Int16.Type) throws -> Int16 {
    try Ocp2JSON.integer(type, from: json)
  }

  func decode(_ type: Int32.Type) throws -> Int32 {
    try Ocp2JSON.integer(type, from: json)
  }

  func decode(_ type: Int64.Type) throws -> Int64 {
    try Ocp2JSON.integer(type, from: json)
  }

  func decode(_ type: UInt.Type) throws -> UInt {
    try Ocp2JSON.integer(type, from: json)
  }

  func decode(_ type: UInt8.Type) throws -> UInt8 {
    try Ocp2JSON.integer(type, from: json)
  }

  func decode(_ type: UInt16.Type) throws -> UInt16 {
    try Ocp2JSON.integer(type, from: json)
  }

  func decode(_ type: UInt32.Type) throws -> UInt32 {
    try Ocp2JSON.integer(type, from: json)
  }

  func decode(_ type: UInt64.Type) throws -> UInt64 {
    try Ocp2JSON.integer(type, from: json)
  }

  func decode<T: Decodable>(_ type: T.Type) throws -> T {
    try state.decode(type, from: json, codingPath: codingPath)
  }
}
#endif
