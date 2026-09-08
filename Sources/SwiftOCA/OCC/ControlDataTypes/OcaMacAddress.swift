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

/// `OcaBlobFixedLength<6>`: an EUI-48 encoded as six raw bytes with no length prefix.
public struct OcaMacAddress: Codable, Sendable, Hashable, CustomStringConvertible {
  /// The six octets, most significant first.
  public typealias EUI48 = (OcaUint8, OcaUint8, OcaUint8, OcaUint8, OcaUint8, OcaUint8)

  public static let byteCount = 6
  public static let zero = OcaMacAddress()

  /// The storage is a tuple rather than an `InlineArray` because the latter needs the Swift 6.2
  /// standard library, which on Apple platforms first shipped in macOS 26, above this package's
  /// deployment target. The `InlineArray` accessors below are availability-gated instead.
  public var eui48: EUI48

  public init() {
    eui48 = (0, 0, 0, 0, 0, 0)
  }

  public init(_ eui48: EUI48) {
    self.eui48 = eui48
  }

  public init(_ bytes: [OcaUint8]) throws {
    guard bytes.count == Self.byteCount else { throw Ocp1Error.status(.parameterOutOfRange) }
    eui48 = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5])
  }

  public init?(string: String) {
    let fields = string.split(whereSeparator: { $0 == ":" || $0 == "-" })
    guard fields.count == Self.byteCount else { return nil }
    var octets = [OcaUint8]()
    for field in fields {
      guard field.count <= 2, let octet = UInt8(field, radix: 16) else { return nil }
      octets.append(octet)
    }
    eui48 = (octets[0], octets[1], octets[2], octets[3], octets[4], octets[5])
  }

  public subscript(index: Int) -> OcaUint8 {
    get {
      switch index {
      case 0: eui48.0
      case 1: eui48.1
      case 2: eui48.2
      case 3: eui48.3
      case 4: eui48.4
      case 5: eui48.5
      default: fatalError("MAC address octet index \(index) is out of range")
      }
    }
    set {
      switch index {
      case 0: eui48.0 = newValue
      case 1: eui48.1 = newValue
      case 2: eui48.2 = newValue
      case 3: eui48.3 = newValue
      case 4: eui48.4 = newValue
      case 5: eui48.5 = newValue
      default: fatalError("MAC address octet index \(index) is out of range")
      }
    }
  }

  public var bytes: [OcaUint8] {
    [eui48.0, eui48.1, eui48.2, eui48.3, eui48.4, eui48.5]
  }

  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    self.init()
    for index in 0..<Self.byteCount {
      self[index] = try container.decode(OcaUint8.self)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    for index in 0..<Self.byteCount {
      try container.encode(self[index])
    }
  }

  // the compiler cannot synthesize this: tuples are not `Equatable`
  // swiftformat:disable:next redundantEquatable
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.eui48 == rhs.eui48
  }

  public func hash(into hasher: inout Hasher) {
    for index in 0..<Self.byteCount {
      hasher.combine(self[index])
    }
  }

  public var description: String {
    bytes.map { byte in
      let hex = String(byte, radix: 16)
      return hex.count == 1 ? "0" + hex : hex
    }.joined(separator: ":")
  }
}

#if compiler(>=6.2)
@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
public extension OcaMacAddress {
  init(_ bytes: InlineArray<6, OcaUint8>) {
    self.init((bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5]))
  }

  var inlineBytes: InlineArray<6, OcaUint8> {
    get {
      var bytes = InlineArray<6, OcaUint8>(repeating: 0)
      for index in 0..<Self.byteCount {
        bytes[index] = self[index]
      }
      return bytes
    }
    set {
      for index in 0..<Self.byteCount {
        self[index] = newValue[index]
      }
    }
  }
}
#endif

@available(*, deprecated, renamed: "OcaMacAddress")
public typealias OcaMACAddress = OcaMacAddress

/// - Note: `InlineArray` (Swift 6.2) makes a generic `OcaBlobFixedLength<N>` expressible, once the
///   Apple deployment target permits it.
public typealias OcaBlobFixedLength6 = OcaMacAddress
