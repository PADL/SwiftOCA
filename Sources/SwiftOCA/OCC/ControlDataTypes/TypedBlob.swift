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
