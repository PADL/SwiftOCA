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

/// Decodes values from the OCP.1 binary representation (AES70-3): the counterpart
/// of `Ocp1Encoder`.
///
/// Every read is bounds-checked, so truncated input throws `Ocp1Error.pduTooShort`.
/// Bytes left over after the value is decoded are ignored.
public struct Ocp1Decoder {
  public var userInfo: [CodingUserInfoKey: Any] = [:]

  public init() {}

  /// Decodes a value from its OCP.1 representation.
  public func decode<Value: Decodable>(_ type: Value.Type, from data: [UInt8]) throws -> Value {
    try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
      try decode(type, buffer: buffer)
    }
  }

  /// Decodes a value from its OCP.1 representation.
  public func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
      try decode(type, buffer: buffer)
    }
  }

  private func decode<Value: Decodable>(
    _ type: Value.Type,
    buffer: UnsafeRawBufferPointer
  ) throws -> Value {
    let decoder = Ocp1DecoderImpl(buffer: buffer, userInfo: userInfo)
    // the buffer is valid only for this call: should a conformer keep hold of the
    // decoder, it must find no input rather than freed memory
    defer { decoder.invalidate() }
    return try decoder.decode(type)
  }
}

/// The decoder handed to `init(from:)`. It reads from a buffer borrowed for the
/// duration of `Ocp1Decoder.decode`, and is its own single-value container; keyed
/// and unkeyed containers forward to it.
final class Ocp1DecoderImpl: Decoder, SingleValueDecodingContainer {
  private var buffer: UnsafeRawBufferPointer
  private var cursor = 0
  let userInfo: [CodingUserInfoKey: Any]

  /// Always empty: the representation is untagged, so there is no path to report.
  var codingPath: [any CodingKey] { [] }

  init(buffer: UnsafeRawBufferPointer, userInfo: [CodingUserInfoKey: Any]) {
    self.buffer = buffer
    self.userInfo = userInfo
  }

  var isAtEnd: Bool { cursor >= buffer.count }

  var remainingCount: Int { buffer.count - cursor }

  func invalidate() {
    buffer = UnsafeRawBufferPointer(start: nil, count: 0)
    cursor = 0
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    KeyedDecodingContainer(Ocp1KeyedDecodingContainer(decoder: self))
  }

  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    Ocp1UnkeyedDecodingContainer(decoder: self)
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    self
  }

  @inline(__always)
  private func readInteger<T: FixedWidthInteger>(_: T.Type) throws -> T {
    let size = MemoryLayout<T>.size
    // compared against what remains, so a large count cannot overflow the cursor
    guard size <= remainingCount else {
      throw Ocp1Error.pduTooShort
    }
    let value = buffer.loadUnaligned(fromByteOffset: cursor, as: T.self)
    cursor += size
    return T(bigEndian: value)
  }

  /// Copies out the next `count` bytes, which the caller has checked are there.
  private func readBytes(_ count: Int) -> Data {
    guard count > 0, let baseAddress = buffer.baseAddress else {
      return Data()
    }
    defer { cursor += count }
    return Data(bytes: baseAddress + cursor, count: count)
  }

  /// Always `false`: `nil` has no representation, so `decodeIfPresent` always
  /// decodes a value.
  func decodeNil() -> Bool { false }

  func decode(_ type: Bool.Type) throws -> Bool { try readInteger(UInt8.self) != 0 }

  func decode(_ type: String.Type) throws -> String {
    // AES70-3: an OcaString's length counts Unicode scalars, not bytes
    var scalarsLeft = try Int(readInteger(UInt16.self))
    let start = cursor
    var end = start

    // ASCII needs no parsing: one byte, one scalar
    while scalarsLeft > 0, end < buffer.count, buffer[end] < 0x80 {
      end += 1
      scalarsLeft -= 1
    }
    if scalarsLeft > 0 {
      var iterator = UnsafeRawBufferPointer(rebasing: buffer[end...]).makeIterator()
      var parser = Unicode.UTF8.ForwardParser()
      while scalarsLeft > 0 {
        switch parser.parseScalar(from: &iterator) {
        case let .valid(scalar):
          end += scalar.count
          scalarsLeft -= 1
        case .emptyInput:
          throw Ocp1Error.pduTooShort
        case .error:
          throw Ocp1Error.stringNotDecodable([UInt8](buffer[start...]))
        }
      }
    }

    cursor = end
    return String(decoding: UnsafeRawBufferPointer(rebasing: buffer[start..<end]), as: UTF8.self)
  }

  func decode(_ type: Double.Type) throws -> Double {
    try Double(bitPattern: readInteger(UInt64.self))
  }

  func decode(_ type: Float.Type) throws -> Float {
    try Float(bitPattern: readInteger(UInt32.self))
  }

  func decode(_ type: Int.Type) throws -> Int { try readInteger(type) }

  func decode(_ type: Int8.Type) throws -> Int8 { try readInteger(type) }

  func decode(_ type: Int16.Type) throws -> Int16 { try readInteger(type) }

  func decode(_ type: Int32.Type) throws -> Int32 { try readInteger(type) }

  func decode(_ type: Int64.Type) throws -> Int64 { try readInteger(type) }

  func decode(_ type: UInt.Type) throws -> UInt { try readInteger(type) }

  func decode(_ type: UInt8.Type) throws -> UInt8 { try readInteger(type) }

  func decode(_ type: UInt16.Type) throws -> UInt16 { try readInteger(type) }

  func decode(_ type: UInt32.Type) throws -> UInt32 { try readInteger(type) }

  func decode(_ type: UInt64.Type) throws -> UInt64 { try readInteger(type) }

  /// Decodes any other value. Every nested value, and the top-level one, comes
  /// through here, so that the types in `_Ocp1CoderSpecial` are always found.
  func decode<T: Decodable>(_ type: T.Type) throws -> T {
    if let special = _ocp1CoderSpecialType(T.self) {
      return try special._ocp1Decode(unchecked: type, from: self)
    }
    return try T(from: self)
  }

  /// The rest of the input, however long.
  func decodeRemainingBytes() -> Data {
    readBytes(remainingCount)
  }

  /// Reads the count of a list or map: an `Int32` for an `Ocp1LongList`, otherwise a
  /// `UInt16`.
  func decodeCount(of type: Any.Type) throws -> Int {
    // FIXME: can't support 2^32 length because on 32-bit platforms count is Int32
    let count = if _ocp1IsLongList(type) {
      try Int(readInteger(Int32.self))
    } else {
      try Int(readInteger(UInt16.self))
    }
    // no input holds a negative number of elements
    guard count >= 0 else {
      throw Ocp1Error.pduTooShort
    }
    return count
  }

  /// Reads a blob's length tag, then that many bytes.
  func decodeBlob(lengthTagWidth: Int) throws -> Data {
    let declared: UInt32 = if lengthTagWidth == 2 {
      try UInt32(readInteger(UInt16.self))
    } else {
      try readInteger(UInt32.self)
    }
    // Int(exactly:) rather than Int(): on a 32-bit target a declared length
    // above Int32.max would trap here, before the bounds check could reject it
    guard let count = Int(exactly: declared), count <= remainingCount else {
      throw Ocp1Error.pduTooShort
    }
    return readBytes(count)
  }
}

/// Fields are read in the order they are decoded; keys are ignored, so every key is
/// present.
struct Ocp1KeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let decoder: Ocp1DecoderImpl

  var codingPath: [any CodingKey] { [] }

  var allKeys: [Key] { [] }

  func contains(_ key: Key) -> Bool { true }

  func decodeNil(forKey key: Key) -> Bool { decoder.decodeNil() }

  func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try decoder.decode(type) }

  func decode(_ type: String.Type, forKey key: Key) throws -> String { try decoder.decode(type) }

  func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try decoder.decode(type) }

  func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try decoder.decode(type) }

  func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try decoder.decode(type) }

  func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try decoder.decode(type) }

  func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try decoder.decode(type) }

  func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try decoder.decode(type) }

  func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try decoder.decode(type) }

  func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try decoder.decode(type) }

  func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try decoder.decode(type) }

  func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try decoder.decode(type) }

  func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try decoder.decode(type) }

  func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try decoder.decode(type) }

  func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
    try decoder.decode(type)
  }

  func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type,
    forKey key: Key
  ) throws -> KeyedDecodingContainer<NestedKey> {
    try decoder.container(keyedBy: type)
  }

  func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
    try decoder.unkeyedContainer()
  }

  func superDecoder() throws -> any Decoder { decoder }

  func superDecoder(forKey key: Key) throws -> any Decoder { decoder }
}

/// Elements are read one after another until the input runs out: a count-prefixed
/// list is an `Array`, which `_Ocp1CoderSpecial` handles, so no count is known here.
struct Ocp1UnkeyedDecodingContainer: UnkeyedDecodingContainer {
  let decoder: Ocp1DecoderImpl
  private(set) var currentIndex = 0

  var codingPath: [any CodingKey] { [] }

  var count: Int? { nil }

  var isAtEnd: Bool { decoder.isAtEnd }

  private mutating func next<T>(_ value: T) -> T {
    currentIndex += 1
    return value
  }

  mutating func decodeNil() -> Bool { decoder.decodeNil() }

  mutating func decode(_ type: Bool.Type) throws -> Bool { try next(decoder.decode(type)) }

  mutating func decode(_ type: String.Type) throws -> String { try next(decoder.decode(type)) }

  mutating func decode(_ type: Double.Type) throws -> Double { try next(decoder.decode(type)) }

  mutating func decode(_ type: Float.Type) throws -> Float { try next(decoder.decode(type)) }

  mutating func decode(_ type: Int.Type) throws -> Int { try next(decoder.decode(type)) }

  mutating func decode(_ type: Int8.Type) throws -> Int8 { try next(decoder.decode(type)) }

  mutating func decode(_ type: Int16.Type) throws -> Int16 { try next(decoder.decode(type)) }

  mutating func decode(_ type: Int32.Type) throws -> Int32 { try next(decoder.decode(type)) }

  mutating func decode(_ type: Int64.Type) throws -> Int64 { try next(decoder.decode(type)) }

  mutating func decode(_ type: UInt.Type) throws -> UInt { try next(decoder.decode(type)) }

  mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try next(decoder.decode(type)) }

  mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try next(decoder.decode(type)) }

  mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try next(decoder.decode(type)) }

  mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try next(decoder.decode(type)) }

  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
    try next(decoder.decode(type))
  }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type
  ) throws -> KeyedDecodingContainer<NestedKey> {
    try decoder.container(keyedBy: type)
  }

  mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
    try decoder.unkeyedContainer()
  }

  mutating func superDecoder() throws -> any Decoder { decoder }
}
