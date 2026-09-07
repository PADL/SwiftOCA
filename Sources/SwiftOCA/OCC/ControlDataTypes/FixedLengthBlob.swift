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
public struct OcaMACAddress: Codable, Sendable, Hashable, CustomStringConvertible {
  public static let byteCount = 6
  public static let zero = OcaMACAddress()

  public var bytes: [OcaUint8]

  public init() {
    bytes = [OcaUint8](repeating: 0, count: Self.byteCount)
  }

  public init(_ bytes: [OcaUint8]) throws {
    guard bytes.count == Self.byteCount else { throw Ocp1Error.status(.parameterOutOfRange) }
    self.bytes = bytes
  }

  public init(_ eui48: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)) {
    bytes = [eui48.0, eui48.1, eui48.2, eui48.3, eui48.4, eui48.5]
  }

  public init?(string: String) {
    let octets = string.split(whereSeparator: { $0 == ":" || $0 == "-" })
      .compactMap { UInt8($0, radix: 16) }
    guard octets.count == Self.byteCount else { return nil }
    bytes = octets
  }

  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var bytes = [OcaUint8]()
    for _ in 0..<Self.byteCount {
      bytes.append(try container.decode(OcaUint8.self))
    }
    self.bytes = bytes
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    for byte in bytes {
      try container.encode(byte)
    }
  }

  public var description: String {
    bytes.map { byte in
      let hex = String(byte, radix: 16)
      return hex.count == 1 ? "0" + hex : hex
    }.joined(separator: ":")
  }
}

public typealias OcaBlobFixedLength6 = OcaMACAddress
