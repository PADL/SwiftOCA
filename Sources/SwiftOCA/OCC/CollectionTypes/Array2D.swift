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

  private func indexIsValid(x: Int, y: Int) -> Bool {
    x >= 0 && x < nX && y >= 0 && y < nY
  }

  public var count: Int {
    nX * nY
  }

  public subscript(x: Int, y: Int) -> Element {
    get {
      assert(indexIsValid(x: x, y: y), "Index out of range")
      return items[(x * nY) + y]
    }
    set {
      assert(indexIsValid(x: x, y: y), "Index out of range")
      items[(x * nY) + y] = newValue
    }
  }

  public mutating func insert(_ newElement: Element, x: Int, y: Int) {
    items.insert(newElement, at: (x * nY) + y)
  }

  @discardableResult
  public mutating func remove(x: Int, y: Int) -> Element {
    items.remove(at: (x * nY) + y)
  }

  public func map<T>(
    defaultValue: T,
    _ transform: (Element) throws -> T
  ) rethrows -> OcaArray2D<T> {
    var mapped = OcaArray2D<T>(nX: nX, nY: nY, defaultValue: defaultValue)
    mapped.items = try items.map(transform)
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
      nX = Int(try container.decode(OcaUint16.self))
      nY = Int(try container.decode(OcaUint16.self))

      items = [Element]()
      items.reserveCapacity(Int(nX * nY))
      for index in 0..<count {
        items.insert(try container.decode(Element.self), at: index)
      }
    } else {
      var container = try decoder.unkeyedContainer()
      let items = try container.decode([[Element]].self)
      var columnCount: Int?

      guard items.allSatisfy({ row in
        if let columnCount {
          return row.count == columnCount
        } else {
          columnCount = row.count
          return true
        }
      }) else {
        throw DecodingError
          .dataCorrupted(DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "OcaArray2D must have consistent dimensions"
          ))
      }

      nX = columnCount ?? 0
      nY = items.count
      self.items = items.reduce([], +)
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
      var columnContainer = encoder.unkeyedContainer()
      for x in 0..<nX {
        var rowContainer = columnContainer.nestedUnkeyedContainer()
        try rowContainer.encode(contentsOf: items[(x * nY)..<(x * nY + nY)])
      }
    }
  }
}

extension OcaArray2D: Equatable where Element: Equatable {}

extension OcaArray2D: Hashable where Element: Hashable {}
