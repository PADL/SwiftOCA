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

/// A value that is marshaled into an `OcaBlob` using OCP.1 rules, as AES70 adaptations
/// do for `OcaAdaptationData`, `IDExternal` and `OcaCounterSet.ID` fields.
public protocol Ocp1TypedBlobRepresentable: Codable {}

public extension Ocp1TypedBlobRepresentable {
  init(blob: OcaBlob) throws {
    self = try Ocp1Decoder().decode(Self.self, from: [UInt8](blob))
  }

  var blob: OcaBlob {
    get throws {
      try OcaBlob(Ocp1Encoder().encode(self) as [UInt8])
    }
  }

  var typedBlob: OcaTypedBlob<Self> {
    get throws {
      try OcaTypedBlob(self)
    }
  }
}

extension Array: Ocp1TypedBlobRepresentable where Element: Codable {}

public extension LengthTaggedData16 {
  init(typed value: some Ocp1TypedBlobRepresentable) throws {
    self = try value.blob
  }

  func decode<T: Ocp1TypedBlobRepresentable>(_: T.Type) throws -> T {
    try T(blob: self)
  }
}

/// An `OcaBlob` whose content the declaring specification fixes as a `Content`, the
/// `OcaTypedBlob<T>` notation proposed for AES70-2X.
///
/// The bytes are kept and `content` decoded on demand, so a value that does not decode
/// still round-trips. On OCP.1 it marshals exactly as the `OcaBlob` it replaces; on OCP.2
/// it is base64 like any blob unless the encoder is asked to emit `structuredTypedBlobs`,
/// and either form decodes.
///
/// Use it where the field's declaration fixes the content type. A hole whose content
/// depends on the adaptation (`OcaMediaStreamEndpoint.AdaptationData`) stays an `OcaBlob`
/// and is decoded where the adaptation is known: `blob.decode(T.self)`.
public struct OcaTypedBlob<Content: Ocp1TypedBlobRepresentable>: Sendable, Equatable,
  Hashable
{
  public var blob: OcaBlob

  public init(_ blob: OcaBlob = OcaBlob()) {
    self.blob = blob
  }

  public init(_ content: Content) throws {
    blob = try content.blob
  }

  public var content: Content {
    get throws {
      try blob.decode(Content.self)
    }
  }

  public var isEmpty: Bool {
    blob.isEmpty
  }
}

extension OcaTypedBlob: Codable {
  public init(from decoder: Decoder) throws {
    blob = try OcaBlob(from: decoder)
  }

  public func encode(to encoder: Encoder) throws {
    try blob.encode(to: encoder)
  }
}

extension OcaTypedBlob: Ocp1BlobRepresentable {
  static var lengthTagWidth: Int {
    OcaBlob.lengthTagWidth
  }

  var blobData: Data {
    blob.wrappedValue
  }

  init(blobData: Data) {
    blob = OcaBlob(blobData)
  }
}

extension OcaTypedBlob: CustomStringConvertible {
  public var description: String {
    if let content = try? content {
      return String(describing: content)
    }
    return blob.map { byte in
      let hex = String(byte, radix: 16)
      return byte < 0x10 ? "0" + hex : hex
    }.joined()
  }
}
