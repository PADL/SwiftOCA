//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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

import BinaryParsing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Synchronization

// MARK: - Codable coder

protocol Ocp1ListRepresentable: Collection, Codable where Element: Codable {}

extension Array: Ocp1ListRepresentable where Element: Codable {
  typealias Element = Element
}

protocol Ocp1MapRepresentable<Key, Value>: Collection, Codable {
  associatedtype Key: Codable & Hashable
  associatedtype Value: Codable

  #if NonEmbeddedBuild
  /// OCP.2 marshals a map as an array of `[key, value]` pairs.
  init(ocp2State: Ocp2DecodingState, json: Any, codingPath: [any CodingKey]) throws
  #endif
  func withMapItems(_ block: (Key, Value) throws -> ()) rethrows
}

extension Dictionary: Ocp1MapRepresentable where Key: Codable & Hashable, Value: Codable {
  #if NonEmbeddedBuild
  init(ocp2State state: Ocp2DecodingState, json: Any, codingPath: [any CodingKey]) throws {
    guard let items = json as? [Any] else {
      throw Ocp1Error.status(.badFormat)
    }
    var dictionary = [Key: Value]()
    dictionary.reserveCapacity(items.count)
    for item in items {
      guard let pair = item as? [Any], pair.count == 2 else {
        throw Ocp1Error.status(.badFormat)
      }
      let key = try state.decode(Key.self, from: pair[0], codingPath: codingPath)
      let value = try state.decode(Value.self, from: pair[1], codingPath: codingPath)
      dictionary[key] = value
    }
    self = dictionary
  }
  #endif

  func withMapItems(_ block: (Key, Value) throws -> ()) rethrows {
    for (key, value) in self {
      try block(key, value)
    }
  }
}

/// A length-tagged blob: a count followed by that many raw bytes.
///
/// Handled in the coder dispatch alongside `Data`, maps and lists, so the bytes
/// move in bulk instead of one container call each.
protocol Ocp1BlobRepresentable: _Ocp1CoderSpecial {
  /// width in bytes of the length tag preceding the payload
  static var lengthTagWidth: Int { get }

  var blobData: Data { get }

  init(blobData: Data)
}

protocol Ocp1Array2DRepresentable<Element> {
  associatedtype Element: Codable
}

extension OcaArray2D: Ocp1Array2DRepresentable where Element: Codable {
  typealias Element = Element
}

// private API for SwiftOCADevice

package extension Encoder {
  var _isOcp1Encoder: Bool {
    self is Ocp1EncoderImpl
  }
}

package extension Decoder {
  var _isOcp1Decoder: Bool {
    self is Ocp1DecoderImpl
  }
}

public protocol Ocp1LongList {}
public protocol OcaParametersReflectable: Codable {}

private let _parameterCountCache = Mutex<[ObjectIdentifier: OcaUint8]>([:])

package func _ocp1ParameterCount(type: (some Any).Type) -> OcaUint8 {
  let key = ObjectIdentifier(type)
  if let cached = _parameterCountCache.withLock({ $0[key] }) {
    return cached
  }

  let result: OcaUint8
  if type is OcaParametersReflectable.Type {
    var count: OcaUint8 = 0
    _forEachField(of: type) { _, _, _, _ in
      count += 1
      return true
    }
    result = count
  } else if type is OcaRoot.Placeholder.Type {
    result = 0
  } else {
    result = 1
  }

  _parameterCountCache.withLock { $0[key] = result }
  return result
}

func _ocp1ParameterCount(value: some Any) -> OcaUint8 {
  _ocp1ParameterCount(type: type(of: value))
}

// MARK: - builtin encoder

/// A type that decodes itself directly from the wire, bypassing `Codable`.
///
/// Conformers consume bytes from a `ParserSpan`, which bounds every read to the
/// enclosing PDU and reports overruns by throwing rather than trapping. Only the
/// top-level OCP.1 framing uses this path; message *parameters* are still
/// decoded with `Ocp1Decoder`.
protocol _Ocp1Decodable {
  init(parsing input: inout ParserSpan) throws
}

extension _Ocp1Decodable {
  /// Decodes from a standalone buffer, for call sites that hold a whole PDU
  /// rather than a position within one.
  init(bytes: borrowing Data) throws {
    try self.init(decodingOcp1Bytes: bytes)
  }

  /// Shared body behind every `init(bytes:)`: this internal default plus the
  /// `package`/`@_spi public` redeclarations that exist only to widen its
  /// visibility. The span-bootstrapping and error-mapping contract lives here.
  init(decodingOcp1Bytes bytes: borrowing Data) throws {
    self = try Ocp1Error.mapping { [bytes = copy bytes] in
      try bytes.withParserSpan { try Self(parsing: &$0) }
    }
  }
}

protocol _Ocp1Encodable {
  /// The exact number of bytes `encode(into:)` writes, known without encoding, so
  /// that a PDU can be allocated once and written in a single pass.
  var encodedSize: Int { get }

  func encode(into output: inout OutputRawSpan)
}

protocol _Ocp1Codable: _Ocp1Decodable & _Ocp1Encodable {}

extension _Ocp1Encodable {
  /// Encodes to a standalone buffer, for call sites outside a PDU.
  var encodedData: Data {
    Data(ocp1ByteCount: encodedSize) { encode(into: &$0) }
  }
}

/// Only big-endian integers and bytes are written by hand-rolled encoders; the
/// span bounds-checks every append against the size the encoder declared.
extension OutputRawSpan {
  @inlinable
  mutating func append<T: FixedWidthInteger & BitwiseCopyable>(bigEndian value: T) {
    append(value.bigEndian, as: T.self)
  }

  @inlinable
  mutating func append(contentsOf data: Data) {
    withUnsafeMutableBytes { buffer, initializedCount in
      data.withUnsafeBytes { source in
        precondition(source.count <= buffer.count - initializedCount)
        UnsafeMutableRawBufferPointer(
          rebasing: buffer[initializedCount..<(initializedCount + source.count)]
        ).copyMemory(from: source)
        initializedCount += source.count
      }
    }
  }
}

extension Data {
  /// `byteCount` bytes, all written in place by `body`.
  @inlinable
  package init(
    ocp1ByteCount byteCount: Int,
    _ body: (inout OutputRawSpan) throws -> ()
  ) rethrows {
    self.init(count: byteCount)
    try withOcp1Output(at: 0, byteCount: byteCount, body)
  }

  /// Grows by `byteCount` bytes, all written in place by `body`.
  @inlinable
  package mutating func appendOcp1(
    byteCount: Int,
    _ body: (inout OutputRawSpan) throws -> ()
  ) rethrows {
    let offset = count
    count += byteCount
    try withOcp1Output(at: offset, byteCount: byteCount, body)
  }

  /// Has `body` overwrite exactly the `byteCount` bytes at `offset`; writing fewer
  /// or more is a size calculation that disagrees with its encoder, and traps.
  @inlinable
  package mutating func withOcp1Output(
    at offset: Int,
    byteCount: Int,
    _ body: (inout OutputRawSpan) throws -> ()
  ) rethrows {
    try withUnsafeMutableBytes { bytes in
      let region = bytes[offset..<(offset + byteCount)]
      var output = OutputRawSpan(buffer: region, initializedCount: 0)
      try body(&output)
      let written = output.finalize(for: region)
      precondition(written == byteCount, "encoded \(written) bytes, expected \(byteCount)")
    }
  }
}
