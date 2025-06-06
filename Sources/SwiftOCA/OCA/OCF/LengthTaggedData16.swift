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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public typealias LengthTaggedData = LengthTaggedData16

public struct LengthTaggedData16: MutableDataProtocol, ContiguousBytes, Equatable, Hashable,
  Sendable
{
  public var startIndex: Data.Index { wrappedValue.startIndex }
  public var endIndex: Data.Index { wrappedValue.endIndex }
  public var regions: CollectionOfOne<LengthTaggedData16> { CollectionOfOne(self) }

  public var wrappedValue: Data

  public init() {
    wrappedValue = Data()
  }

  public subscript(position: Data.Index) -> UInt8 {
    get {
      wrappedValue[position]
    }
    set(newValue) {
      wrappedValue[position] = newValue
    }
  }

  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    try wrappedValue.withUnsafeBytes(body)
  }

  public mutating func withUnsafeMutableBytes<R>(
    _ body: (UnsafeMutableRawBufferPointer) throws
      -> R
  ) rethrows -> R {
    try wrappedValue.withUnsafeMutableBytes(body)
  }

  public mutating func replaceSubrange(
    _ subrange: Range<Data.Index>,
    with newElements: __owned some Collection<Element>
  ) {
    wrappedValue.replaceSubrange(subrange, with: newElements)
  }
}

extension LengthTaggedData16: Encodable {
  public func encode(to encoder: Encoder) throws {
    if wrappedValue.count > UInt16.max {
      throw Ocp1Error.invalidMessageSize
    }
    var container = encoder.unkeyedContainer()
    try container.encode(UInt16(wrappedValue.count))
    try withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
      try container.encode(contentsOf: buffer)
    }
  }
}

extension LengthTaggedData16: Decodable {
  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()

    let count = try Int(container.decode(UInt16.self))
    wrappedValue = Data(count: count)
    for i in 0..<count {
      let byte = try container.decode(UInt8.self)
      wrappedValue[i] = byte
    }
  }
}

extension LengthTaggedData16: _Ocp1Codable {
  init(bytes: borrowing[UInt8]) throws {
    guard bytes.count >= 2 else {
      throw Ocp1Error.pduTooShort
    }

    let count = Int(bytes.withUnsafeBytes {
      UInt16(bigEndian: $0.loadUnaligned(as: UInt16.self))
    })

    guard bytes.count >= 2 + count else {
      throw Ocp1Error.pduTooShort
    }
    wrappedValue = Data(bytes[2..<(2 + count)])
  }

  func encode(into bytes: inout [UInt8]) {
    bytes += Swift.withUnsafeBytes(of: UInt16(wrappedValue.count).bigEndian) { Array($0) }
    bytes += Array(wrappedValue)
  }
}
