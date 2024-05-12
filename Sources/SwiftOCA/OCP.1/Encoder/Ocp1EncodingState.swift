//
// Copyright (c) 2022 fwcd
// Portions (c) 2023-2024 PADL Software Pty Ltd
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

import Foundation

/// The internal state used by the encoders.
class Ocp1EncodingState {
  private(set) var data: Data = .init()

  /// The current coding path on the type level. Used to detect cycles
  /// (i.e. recursive or mutually recursive types), which are essentially
  /// recursive types.
  private var codingTypePath: [String] = []

  let userInfo: [CodingUserInfoKey: Any]

  init(data: Data = .init(), userInfo: [CodingUserInfoKey: Any]) {
    self.data = data
    self.userInfo = userInfo
  }

  func encodeNil() throws {
    throw Ocp1Error.nilNotEncodable
  }

  func encodeInteger(_ value: some FixedWidthInteger) throws {
    withUnsafeBytes(of: value.bigEndian) {
      data += $0
    }
  }

  func encode(_ value: String) throws {
    guard let encoded = value.data(using: .utf8) else {
      throw Ocp1Error.stringNotEncodable(value)
    }

    // Oca-3-2018: the Len part of the OcaString shall define the string length
    // (i.e. the number of Unicode codepoints), not the byte length.
    let length = UInt16(value.unicodeScalars.count)
    try encodeInteger(length)
    data += encoded
  }

  func encode(_ value: Bool) throws {
    try encodeInteger(value ? 1 as UInt8 : 0)
  }

  func encode(_ value: Double) throws {
    try encodeInteger(value.bitPattern)
  }

  func encode(_ value: Float) throws {
    try encodeInteger(value.bitPattern)
  }

  func encode(_ value: Int) throws {
    try encodeInteger(value)
  }

  func encode(_ value: Int8) throws {
    try encodeInteger(value)
  }

  func encode(_ value: Int16) throws {
    try encodeInteger(value)
  }

  func encode(_ value: Int32) throws {
    try encodeInteger(value)
  }

  func encode(_ value: Int64) throws {
    try encodeInteger(value)
  }

  func encode(_ value: UInt) throws {
    try encodeInteger(value)
  }

  func encode(_ value: UInt8) throws {
    try encodeInteger(value)
  }

  func encode(_ value: UInt16) throws {
    try encodeInteger(value)
  }

  func encode(_ value: UInt32) throws {
    try encodeInteger(value)
  }

  func encode(_ value: UInt64) throws {
    try encodeInteger(value)
  }

  private func encodeCount(_ value: some Collection & Encodable) throws {
    if value is Ocp1LongList {
      // FIXME: can't support 2^32 length because on 32-bit platforms count is Int32
      if value.count > Int(Int32.max) {
        throw Ocp1Error.arrayOrDataTooBig
      }
      try encodeInteger(Int32(value.count))
    } else {
      if value.count > Int(UInt16.max) {
        throw Ocp1Error.arrayOrDataTooBig
      }
      try encodeInteger(UInt16(value.count))
    }
  }

  func encode(_ value: some Encodable, codingPath: [any CodingKey]) throws {
    switch value {
    case let data as Data:
      self.data += data
    case let map as any Ocp1MapRepresentable:
      try encodeCount(map)
      try map.withMapItems {
        try encode($0, codingPath: codingPath)
        try encode($1, codingPath: codingPath)
      }
    case let array as any Ocp1ListRepresentable:
      try encodeCount(array)
      fallthrough
    default:
      try withCodingTypePath(appending: [String(describing: type(of: value))]) {
        try value.encode(to: Ocp1EncoderImpl(state: self, codingPath: codingPath))
      }
    }
  }

  private func withCodingTypePath(appending delta: [String], action: () throws -> ()) throws {
    codingTypePath += delta
    guard Set(codingTypePath).count == codingTypePath.count else {
      throw Ocp1Error.recursiveTypeDisallowed
    }
    try action()
    codingTypePath.removeLast(delta.count)
  }
}
