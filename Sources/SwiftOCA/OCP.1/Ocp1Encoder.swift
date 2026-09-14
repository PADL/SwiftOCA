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

/// Encodes values to the OCP.1 binary representation (AES70-3).
///
/// Values are written big-endian and untagged, in the order they are encoded: keys
/// are ignored, and `nil` cannot be represented. A string is prefixed by its length
/// in Unicode scalars, a list or map by its count, and a blob by its byte length;
/// `Data` is written raw.
public struct Ocp1Encoder {
  public var userInfo: [CodingUserInfoKey: Any] = [:]

  public init() {}

  /// Encodes a value to its OCP.1 representation.
  public func encode(_ value: some Encodable) throws -> Data {
    let encoder = Ocp1EncoderImpl(userInfo: userInfo)
    try encoder.encode(value)
    return encoder.takeData()
  }

  /// Encodes a value to its OCP.1 representation.
  public func encode(_ value: some Encodable) throws -> [UInt8] {
    let encoder = Ocp1EncoderImpl(userInfo: userInfo)
    try encoder.encode(value)
    return encoder.bytes
  }
}

/// The encoder handed to `encode(to:)`. It is its own single-value container;
/// keyed and unkeyed containers forward to it.
///
/// The output is written into a buffer this encoder owns, so that `Data`, which is
/// what most callers ask for, can take the buffer over instead of copying it.
final class Ocp1EncoderImpl: Encoder, SingleValueEncodingContainer {
  private var storage: UnsafeMutableRawPointer
  private var capacity: Int
  private var count = 0
  /// set once `takeData()` has given the buffer to a `Data`, which frees it
  private var isHandedOff = false

  let userInfo: [CodingUserInfoKey: Any]

  /// Always empty: the representation is untagged, so there is no path to report.
  var codingPath: [any CodingKey] { [] }

  init(userInfo: [CodingUserInfoKey: Any]) {
    self.userInfo = userInfo
    capacity = 64
    storage = .allocate(byteCount: capacity, alignment: 1)
  }

  deinit {
    if !isHandedOff {
      storage.deallocate()
    }
  }

  /// A copy of what has been written.
  var bytes: [UInt8] {
    [UInt8](UnsafeRawBufferPointer(start: storage, count: count))
  }

  /// What has been written, as a `Data` that owns the buffer. The encoder must not
  /// be used afterwards.
  func takeData() -> Data {
    // at or below Data's inline capacity a copy costs no allocation, and frees
    // the buffer rather than keeping all of it alive for a few bytes
    if count <= MemoryLayout<Int>.size * 2 - 2 {
      return Data(bytes: storage, count: count)
    }
    isHandedOff = true
    return Data(bytesNoCopy: storage, count: count, deallocator: .custom { pointer, _ in
      pointer.deallocate()
    })
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    KeyedEncodingContainer(Ocp1KeyedEncodingContainer(encoder: self))
  }

  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    Ocp1UnkeyedEncodingContainer(encoder: self)
  }

  func singleValueContainer() -> any SingleValueEncodingContainer {
    self
  }

  /// Makes room for `byteCount` more bytes.
  @inline(__always)
  private func reserve(_ byteCount: Int) {
    if byteCount > capacity - count {
      grow(byteCount)
    }
  }

  @inline(never)
  private func grow(_ byteCount: Int) {
    let newCapacity = Swift.max(capacity * 2, count + byteCount)
    let newStorage = UnsafeMutableRawPointer.allocate(byteCount: newCapacity, alignment: 1)
    newStorage.copyMemory(from: storage, byteCount: count)
    storage.deallocate()
    storage = newStorage
    capacity = newCapacity
  }

  @inline(__always)
  private func appendInteger<T: FixedWidthInteger>(_ value: T) {
    let size = MemoryLayout<T>.size
    reserve(size)
    storage.storeBytes(of: value.bigEndian, toByteOffset: count, as: T.self)
    count += size
  }

  func appendBytes(_ buffer: UnsafeRawBufferPointer) {
    guard let baseAddress = buffer.baseAddress, buffer.count > 0 else {
      return
    }
    reserve(buffer.count)
    (storage + count).copyMemory(from: baseAddress, byteCount: buffer.count)
    count += buffer.count
  }

  func encodeNil() throws {
    throw Ocp1Error.nilNotEncodable
  }

  func encode(_ value: Bool) throws { appendInteger(value ? 1 as UInt8 : 0) }

  func encode(_ value: String) throws {
    // AES70-3: an OcaString's length counts Unicode scalars, not bytes. The UTF-8
    // of a String is valid, so that is the number of bytes not continuing a scalar.
    var value = value
    try value.withUTF8 { utf8 in
      var scalarCount = 0
      for byte in utf8 where byte & 0xC0 != 0x80 {
        scalarCount &+= 1
      }
      guard let length = UInt16(exactly: scalarCount) else {
        throw Ocp1Error.arrayOrDataTooBig
      }
      appendInteger(length)
      appendBytes(UnsafeRawBufferPointer(utf8))
    }
  }

  func encode(_ value: Double) throws { appendInteger(value.bitPattern) }

  func encode(_ value: Float) throws { appendInteger(value.bitPattern) }

  func encode(_ value: Int) throws { appendInteger(value) }

  func encode(_ value: Int8) throws { appendInteger(value) }

  func encode(_ value: Int16) throws { appendInteger(value) }

  func encode(_ value: Int32) throws { appendInteger(value) }

  func encode(_ value: Int64) throws { appendInteger(value) }

  func encode(_ value: UInt) throws { appendInteger(value) }

  func encode(_ value: UInt8) throws { appendInteger(value) }

  func encode(_ value: UInt16) throws { appendInteger(value) }

  func encode(_ value: UInt32) throws { appendInteger(value) }

  func encode(_ value: UInt64) throws { appendInteger(value) }

  /// Encodes any other value. Every nested value, and the top-level one, comes
  /// through here, so that the types in `_Ocp1CoderSpecial` are always found.
  func encode<T: Encodable>(_ value: T) throws {
    if let special = _ocp1CoderSpecialType(T.self) {
      try special._ocp1Encode(unchecked: value, into: self)
    } else {
      try value.encode(to: self)
    }
  }

  /// Writes the count of a list or map: an `Int32` for an `Ocp1LongList`, otherwise
  /// a `UInt16`.
  func encodeCount(_ count: Int, of type: Any.Type) throws {
    if _ocp1IsLongList(type) {
      // FIXME: can't support 2^32 length because on 32-bit platforms count is Int32
      guard let count = Int32(exactly: count) else {
        throw Ocp1Error.arrayOrDataTooBig
      }
      appendInteger(count)
    } else {
      guard let count = UInt16(exactly: count) else {
        throw Ocp1Error.arrayOrDataTooBig
      }
      appendInteger(count)
    }
  }

  /// Writes a blob's length tag, then its bytes.
  func encodeBlob(_ data: Data, lengthTagWidth: Int) throws {
    // invalidMessageSize, not arrayOrDataTooBig: the blob types' own Codable
    // conformances throw that, and the two must agree for the same input
    if lengthTagWidth == 2 {
      guard let count = UInt16(exactly: data.count) else {
        throw Ocp1Error.invalidMessageSize
      }
      appendInteger(count)
    } else {
      guard let count = UInt32(exactly: data.count) else {
        throw Ocp1Error.invalidMessageSize
      }
      appendInteger(count)
    }
    data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
      appendBytes(buffer)
    }
  }
}

/// Fields are written in the order they are encoded; keys are ignored.
struct Ocp1KeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
  let encoder: Ocp1EncoderImpl

  var codingPath: [any CodingKey] { [] }

  mutating func encodeNil(forKey key: Key) throws { try encoder.encodeNil() }

  mutating func encode(_ value: Bool, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: String, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: Double, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: Float, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: Int, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: Int8, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: Int16, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: Int32, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: Int64, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: UInt, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: UInt8, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: UInt16, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: UInt32, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: UInt64, forKey key: Key) throws { try encoder.encode(value) }

  mutating func encode(_ value: some Encodable, forKey key: Key) throws {
    try encoder.encode(value)
  }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy keyType: NestedKey.Type,
    forKey key: Key
  ) -> KeyedEncodingContainer<NestedKey> {
    encoder.container(keyedBy: keyType)
  }

  mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
    encoder.unkeyedContainer()
  }

  mutating func superEncoder() -> any Encoder { encoder }

  mutating func superEncoder(forKey key: Key) -> any Encoder { encoder }
}

/// Elements are written one after another, with no count: a count-prefixed list is
/// an `Array`, which `_Ocp1CoderSpecial` handles.
struct Ocp1UnkeyedEncodingContainer: UnkeyedEncodingContainer {
  let encoder: Ocp1EncoderImpl
  private(set) var count = 0

  var codingPath: [any CodingKey] { [] }

  mutating func encodeNil() throws { try encoder.encodeNil() }

  mutating func encode(_ value: Bool) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: String) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: Double) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: Float) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: Int) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: Int8) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: Int16) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: Int32) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: Int64) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: UInt) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: UInt8) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: UInt16) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: UInt32) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: UInt64) throws { try encoder.encode(value); count += 1 }

  mutating func encode(_ value: some Encodable) throws { try encoder.encode(value); count += 1 }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy keyType: NestedKey.Type
  ) -> KeyedEncodingContainer<NestedKey> {
    encoder.container(keyedBy: keyType)
  }

  mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
    encoder.unkeyedContainer()
  }

  mutating func superEncoder() -> any Encoder { encoder }
}
