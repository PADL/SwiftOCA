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

/// A map in which a key may have more than one value, held as each key's values.
///
/// It is marshaled as an `OcaMap` is, one item per value (AES70-3 8.2.3, AES70-4 8.8):
/// a key with several values is repeated, once per value, and a key with none is not
/// written. It is not an `OcaMap` of lists, which would put a count before each key's
/// values.
public struct OcaMultiMap<K: Hashable, V> {
  public var dictionary: [K: [V]]

  public init() {
    dictionary = [:]
  }

  public init(_ dictionary: [K: [V]]) {
    self.dictionary = dictionary
  }

  /// The values of a key, empty for a key with none.
  public subscript(key: K) -> [V] {
    get { dictionary[key] ?? [] }
    set { dictionary[key] = newValue.isEmpty ? nil : newValue }
  }

  /// As `Dictionary`'s, for code written when this was a dictionary of each key's values.
  public subscript(key: K, default defaultValue: @autoclosure () -> [V]) -> [V] {
    get { dictionary[key] ?? defaultValue() }
    set { self[key] = newValue }
  }

  public var keys: Dictionary<K, [V]>.Keys { dictionary.keys }

  /// Each key's values.
  public var values: Dictionary<K, [V]>.Values { dictionary.values }

  /// The number of items it is marshaled as, one per value.
  public var itemCount: Int {
    dictionary.values.reduce(0) { $0 + $1.count }
  }

  public mutating func append(_ value: V, forKey key: K) {
    dictionary[key, default: []].append(value)
  }

  /// Calls `block` with each item, a key with one of its values.
  public func forEachItem(_ block: (K, V) throws -> ()) rethrows {
    for (key, values) in dictionary {
      for value in values {
        try block(key, value)
      }
    }
  }
}

extension OcaMultiMap: Collection {
  public typealias Index = Dictionary<K, [V]>.Index
  public typealias Element = Dictionary<K, [V]>.Element

  public var startIndex: Index { dictionary.startIndex }
  public var endIndex: Index { dictionary.endIndex }
  public func index(after i: Index) -> Index { dictionary.index(after: i) }
  public subscript(position: Index) -> Element { dictionary[position] }
}

extension OcaMultiMap: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (K, [V])...) {
    var dictionary = [K: [V]]()
    for (key, values) in elements {
      dictionary[key, default: []].append(contentsOf: values)
    }
    self.init(dictionary)
  }
}

extension OcaMultiMap: Sendable where K: Sendable, V: Sendable {}

extension OcaMultiMap: Equatable where V: Equatable {}

extension OcaMultiMap: Hashable where V: Hashable {}

/// Coders other than OCP.1 and OCP.2, which marshal it themselves, see each key's values.
extension OcaMultiMap: Codable where K: Codable, V: Codable {
  public init(from decoder: any Decoder) throws {
    try self.init(decoder.singleValueContainer().decode([K: [V]].self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(dictionary)
  }
}
