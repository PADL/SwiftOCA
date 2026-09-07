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

/// Encodes OCA values to JSON per AES70-4 clause 8: blobs as base64, maps as arrays of
/// `[key, value]` pairs, class and element IDs as arrays, enums as numbers, composite
/// datatypes as objects keyed by field name.
public struct Ocp2Encoder {
  public var userInfo: [CodingUserInfoKey: Any] = [:]

  public init() {}

  /// Encodes a method's parameters as the OCP.2 `Parameters` object.
  ///
  /// A parameter record (`Ocp1ParametersReflectable`) becomes one member per stored
  /// property, named by `parameterNames` in declaration order and then by the derived
  /// wire name. Anything else is a single parameter named `parameterNames.first`, or
  /// `Ocp2Naming.unnamedParameter` when no name was supplied.
  public func encodeParameters(
    _ value: some Encodable,
    parameterNames: [String]? = nil
  ) throws -> [String: Any] {
    if value is OcaRoot.Placeholder {
      return [:]
    }

    let state = Ocp2EncodingState(userInfo: userInfo)

    if type(of: value) is Ocp1ParametersReflectable.Type {
      let fieldNames = Ocp2Naming.fieldNames(of: type(of: value))
      let names = Ocp2Naming.parameterNames(explicit: parameterNames, fieldNames: fieldNames)
      let node = Ocp2EncodingNode()
      node.frame = Ocp2NamingFrame(parameterNames: names, fieldNames: fieldNames)
      try value.encode(to: Ocp2EncoderImpl(state: state, node: node, codingPath: []))
      if let object = node.object {
        return Ocp2EncodingNode.json(object: object)
      }
      // a record that encoded itself as something other than an object
      return [names.first ?? Ocp2Naming.unnamedParameter: node.json()]
    }

    let node = try state.encode(value, codingPath: [])
    return [parameterNames?.first ?? Ocp2Naming.unnamedParameter: node.json()]
  }

  /// Serialised form of `encodeParameters`.
  public func encodeParametersData(
    _ value: some Encodable,
    parameterNames: [String]? = nil
  ) throws -> Data {
    try Ocp2JSON.serialize(encodeParameters(value, parameterNames: parameterNames))
  }

  /// Encodes a free-standing value (a property value, event data, a struct field).
  public func encodeValue(_ value: some Encodable) throws -> Any {
    let state = Ocp2EncodingState(userInfo: userInfo)
    return try state.encode(value, codingPath: []).json()
  }
}

/// The names of a top-level parameter record: the wire name for each Swift field,
/// by exact field name (the synthesized `CodingKey`) with a case-insensitive
/// fallback for hand-written keys.
struct Ocp2NamingFrame {
  let parameterNames: [String]
  let fieldNames: [String]
  private let byField: [String: String]

  init(parameterNames: [String], fieldNames: [String]) {
    self.parameterNames = parameterNames
    self.fieldNames = fieldNames
    var byField = [String: String]()
    for (index, field) in fieldNames.enumerated() where index < parameterNames.count {
      byField[field] = parameterNames[index]
    }
    self.byField = byField
  }

  /// The wire name for `key`, or `nil` when the key is not a field of the record.
  func wireName(for key: any CodingKey) -> String? {
    let swiftName = key.stringValue
    if let name = byField[swiftName] {
      return name
    }
    guard let index = fieldNames.firstIndex(where: { Ocp2Naming.matches($0, swiftName) }),
          index < parameterNames.count
    else { return nil }
    return parameterNames[index]
  }

  func name(for key: any CodingKey, position: Int) -> String {
    if let name = wireName(for: key) {
      return name
    }
    if position < parameterNames.count, position >= fieldNames.count {
      return parameterNames[position]
    }
    return Ocp2Naming.wireName(key.stringValue)
  }
}

/// A node in the JSON tree under construction. Containers are structs holding a
/// reference to the node they fill.
final class Ocp2EncodingNode {
  var value: Any?
  var object: [(String, Ocp2EncodingNode)]?
  var array: [Ocp2EncodingNode]?
  var frame: Ocp2NamingFrame?

  func json() -> Any {
    if let object {
      return Self.json(object: object)
    }
    if let array {
      return array.map { $0.json() }
    }
    return value ?? NSNull()
  }

  static func json(object: [(String, Ocp2EncodingNode)]) -> [String: Any] {
    var dict = [String: Any]()
    for (key, node) in object {
      dict[key] = node.json()
    }
    return dict
  }

  func adopt(_ other: Ocp2EncodingNode) {
    value = other.value
    object = other.object
    array = other.array
  }
}

final class Ocp2EncodingState {
  let userInfo: [CodingUserInfoKey: Any]

  init(userInfo: [CodingUserInfoKey: Any]) {
    self.userInfo = userInfo
  }

  /// Encodes `value` into a fresh node, handling the types whose OCP.2 form is not
  /// what their `Codable` conformance produces.
  func encode(_ value: some Encodable, codingPath: [any CodingKey]) throws -> Ocp2EncodingNode {
    let node = Ocp2EncodingNode()
    switch value {
    // primitives are leaves: their own `encode(to:)` would hand them straight back
    case let bool as Bool:
      node.value = bool
    case let string as String:
      node.value = string
    case let int as Int:
      node.value = int
    case let int as Int8:
      node.value = Int(int)
    case let int as Int16:
      node.value = Int(int)
    case let int as Int32:
      node.value = Int(int)
    case let int as Int64:
      node.value = int
    case let uint as UInt:
      node.value = UInt64(uint)
    case let uint as UInt8:
      node.value = Int(uint)
    case let uint as UInt16:
      node.value = Int(uint)
    case let uint as UInt32:
      node.value = Int(uint)
    case let uint as UInt64:
      node.value = uint
    // identifier datatypes have array or string forms (AES70-4 8.11.1)
    case let id as OcaPropertyID:
      node.value = _ocp2ElementID(id.defLevel, id.propertyIndex)
    case let id as OcaMethodID:
      node.value = _ocp2ElementID(id.defLevel, id.methodIndex)
    case let id as OcaEventID:
      node.value = _ocp2ElementID(id.defLevel, id.eventIndex)
    case let classID as OcaClassID:
      node.value = classID.ocp2JSON
    case let organization as OcaOrganizationID:
      node.value = organization.description
    case let data as Data:
      node.value = Ocp2JSON.base64(data)
    case let blob as any Ocp1BlobRepresentable:
      node.value = Ocp2JSON.base64(blob.blobData)
    case let map as any Ocp1MapRepresentable:
      var items = [Ocp2EncodingNode]()
      try map.withMapItems { key, item in
        let pair = Ocp2EncodingNode()
        pair.array = try [encode(key, codingPath: codingPath), encode(item, codingPath: codingPath)]
        items.append(pair)
      }
      node.array = items
    case let double as Double:
      node.value = Ocp2JSON.json(double)
    case let float as Float:
      node.value = Ocp2JSON.json(float)
    default:
      try value.encode(to: Ocp2EncoderImpl(state: self, node: node, codingPath: codingPath))
    }
    return node
  }
}

struct Ocp2EncoderImpl: Encoder {
  let state: Ocp2EncodingState
  let node: Ocp2EncodingNode
  let codingPath: [any CodingKey]

  var userInfo: [CodingUserInfoKey: Any] {
    state.userInfo
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    if node.object == nil {
      node.object = []
    }
    return .init(KeyedOcp2EncodingContainer(state: state, node: node, codingPath: codingPath))
  }

  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    if node.array == nil {
      node.array = []
    }
    return UnkeyedOcp2EncodingContainer(state: state, node: node, codingPath: codingPath)
  }

  func singleValueContainer() -> any SingleValueEncodingContainer {
    SingleValueOcp2EncodingContainer(state: state, node: node, codingPath: codingPath)
  }
}

package extension Encoder {
  var _isOcp2Encoder: Bool {
    self is Ocp2EncoderImpl
  }
}

struct KeyedOcp2EncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
  let state: Ocp2EncodingState
  let node: Ocp2EncodingNode
  let codingPath: [any CodingKey]

  private func name(for key: Key) -> String {
    if let frame = node.frame {
      return frame.name(for: key, position: node.object?.count ?? 0)
    }
    return Ocp2Naming.wireName(key.stringValue)
  }

  private func append(_ child: Ocp2EncodingNode, forKey key: Key) {
    let name = name(for: key)
    node.object?.append((name, child))
  }

  mutating func encodeNil(forKey key: Key) throws {
    let child = Ocp2EncodingNode()
    child.value = NSNull()
    append(child, forKey: key)
  }

  mutating func encode(_ value: Bool, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  mutating func encode(_ value: String, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  mutating func encode(_ value: Double, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  mutating func encode(_ value: Float, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  mutating func encode(_ value: Int, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  mutating func encode(_ value: Int8, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  mutating func encode(_ value: Int16, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  mutating func encode(_ value: Int32, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  mutating func encode(_ value: Int64, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  mutating func encode(_ value: UInt, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  mutating func encode(_ value: UInt8, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  mutating func encode(_ value: UInt16, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  mutating func encode(_ value: UInt32, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  mutating func encode(_ value: UInt64, forKey key: Key) throws {
    try encodeLeaf(value, forKey: key)
  }

  private mutating func encodeLeaf(_ value: some Encodable, forKey key: Key) throws {
    try append(state.encode(value, codingPath: codingPath + [key]), forKey: key)
  }

  mutating func encode(_ value: some Encodable, forKey key: Key) throws {
    try append(state.encode(value, codingPath: codingPath + [key]), forKey: key)
  }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy keyType: NestedKey.Type,
    forKey key: Key
  ) -> KeyedEncodingContainer<NestedKey> {
    let child = Ocp2EncodingNode()
    child.object = []
    append(child, forKey: key)
    return .init(KeyedOcp2EncodingContainer<NestedKey>(
      state: state,
      node: child,
      codingPath: codingPath + [key]
    ))
  }

  mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
    let child = Ocp2EncodingNode()
    child.array = []
    append(child, forKey: key)
    return UnkeyedOcp2EncodingContainer(state: state, node: child, codingPath: codingPath + [key])
  }

  mutating func superEncoder() -> any Encoder {
    Ocp2EncoderImpl(state: state, node: node, codingPath: codingPath)
  }

  mutating func superEncoder(forKey key: Key) -> any Encoder {
    let child = Ocp2EncodingNode()
    append(child, forKey: key)
    return Ocp2EncoderImpl(state: state, node: child, codingPath: codingPath + [key])
  }
}

struct UnkeyedOcp2EncodingContainer: UnkeyedEncodingContainer {
  let state: Ocp2EncodingState
  let node: Ocp2EncodingNode
  let codingPath: [any CodingKey]

  var count: Int {
    node.array?.count ?? 0
  }

  private func append(_ child: Ocp2EncodingNode) {
    node.array?.append(child)
  }

  mutating func encodeNil() throws {
    let child = Ocp2EncodingNode()
    child.value = NSNull()
    append(child)
  }

  mutating func encode(_ value: some Encodable) throws {
    try append(state.encode(value, codingPath: codingPath))
  }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy keyType: NestedKey.Type
  ) -> KeyedEncodingContainer<NestedKey> {
    let child = Ocp2EncodingNode()
    child.object = []
    append(child)
    return .init(KeyedOcp2EncodingContainer<NestedKey>(
      state: state,
      node: child,
      codingPath: codingPath
    ))
  }

  mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
    let child = Ocp2EncodingNode()
    child.array = []
    append(child)
    return UnkeyedOcp2EncodingContainer(state: state, node: child, codingPath: codingPath)
  }

  mutating func superEncoder() -> any Encoder {
    let child = Ocp2EncodingNode()
    append(child)
    return Ocp2EncoderImpl(state: state, node: child, codingPath: codingPath)
  }
}

struct SingleValueOcp2EncodingContainer: SingleValueEncodingContainer {
  let state: Ocp2EncodingState
  let node: Ocp2EncodingNode
  let codingPath: [any CodingKey]

  mutating func encodeNil() throws {
    node.value = NSNull()
  }

  mutating func encode(_ value: some Encodable) throws {
    try node.adopt(state.encode(value, codingPath: codingPath))
  }
}
#endif
