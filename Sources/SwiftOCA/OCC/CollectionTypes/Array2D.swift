//
// Copyright (c) 2023 PADL Software Pty Ltd
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

/// AES70 `OcaList2D`: a fixed-size grid of `nX` columns by `nY` rows, laid out as `nY`
/// contiguous rows of `nX` elements. Indexing, `init(arrayOfArrays:)` and both coders all
/// read `items` that way — OCP.1 as the flat run of elements behind the two dimensions,
/// JSON as an array of rows.
public struct OcaArray2D<Element: Sendable>: Sendable {
  public let nX, nY: Int
  public private(set) var items: [Element]

  public init(nX: Int, nY: Int, defaultValue: Element) {
    self.nX = nX
    self.nY = nY
    items = [Element](repeating: defaultValue, count: nX * nY)
  }

  public init(nX: OcaUint16, nY: OcaUint16, defaultValue: Element) {
    self.init(nX: Int(nX), nY: Int(nY), defaultValue: defaultValue)
  }

  /// Fails unless every row is the same length.
  public init?(arrayOfArrays rows: [[Element]]) {
    let columnCount = rows.first?.count ?? 0
    guard rows.allSatisfy({ $0.count == columnCount }) else { return nil }

    nX = columnCount
    nY = rows.count
    items = Array(rows.joined())
  }

  /// The grid as `nY` rows of `nX` elements; the inverse of `init(arrayOfArrays:)`.
  public var arrayOfArrays: [[Element]] {
    (0..<nY).map { y in Array(items[(y * nX)..<((y + 1) * nX)]) }
  }

  private func indexIsValid(x: Int, y: Int) -> Bool {
    x >= 0 && x < nX && y >= 0 && y < nY
  }

  public var count: Int {
    nX * nY
  }

  public subscript(x: Int, y: Int) -> Element {
    get {
      assert(indexIsValid(x: x, y: y), "Index out of range")
      return items[(y * nX) + x]
    }
    set {
      assert(indexIsValid(x: x, y: y), "Index out of range")
      items[(y * nX) + x] = newValue
    }
  }

  public mutating func insert(_ newElement: Element, x: Int, y: Int) {
    items.insert(newElement, at: (y * nX) + x)
  }

  @discardableResult
  public mutating func remove(x: Int, y: Int) -> Element {
    items.remove(at: (y * nX) + x)
  }

  public func map<T>(
    defaultValue: T,
    _ transform: (Element) throws -> T
  ) rethrows -> OcaArray2D<T> {
    var mapped = OcaArray2D<T>(nX: nX, nY: nY, defaultValue: defaultValue)
    mapped.items = try items.map(transform)
    return mapped
  }

  public func asyncMap<T>(
    defaultValue: T,
    _ transform: sending (Element) async throws -> T
  ) async rethrows -> OcaArray2D<T> {
    var mapped = OcaArray2D<T>(nX: nX, nY: nY, defaultValue: defaultValue)
    mapped.items = try await items.asyncMap(transform)
    return mapped
  }

  public func forEach(_ body: (Element) throws -> ()) rethrows {
    try items.forEach(body)
  }
}

extension OcaArray2D: Codable where Element: Codable {
  public init(from decoder: Decoder) throws {
    if decoder._isOcp1Decoder {
      var container = try decoder.unkeyedContainer()
      nX = try Int(container.decode(OcaUint16.self))
      nY = try Int(container.decode(OcaUint16.self))

      items = [Element]()
      items.reserveCapacity(Int(nX * nY))
      for index in 0..<count {
        try items.insert(container.decode(Element.self), at: index)
      }
    } else {
      let container = try decoder.singleValueContainer()
      let items = try container.decode([[Element]].self)

      guard let array2D = Self(arrayOfArrays: items) else {
        throw DecodingError
          .dataCorrupted(DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "OcaArray2D must have consistent dimensions"
          ))
      }

      self = array2D
    }
  }

  public func encode(to encoder: Encoder) throws {
    if encoder._isOcp1Encoder {
      var container = encoder.unkeyedContainer()
      try container.encode(OcaUint16(nX))
      try container.encode(OcaUint16(nY))
      for index in 0..<count {
        try container.encode(items[index])
      }
    } else {
      var container = encoder.singleValueContainer()
      try container.encode(arrayOfArrays)
    }
  }
}

extension OcaArray2D: Equatable where Element: Equatable {}

extension OcaArray2D: Hashable where Element: Hashable {}
