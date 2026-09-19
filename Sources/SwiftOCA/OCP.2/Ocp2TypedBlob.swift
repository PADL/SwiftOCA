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

#if NonEmbeddedBuild
import Foundation

/// A typed blob's OCP.2 forms: the base64 of its OCP.1 bytes that AES70-4 clause 8 gives
/// every blob, or its content as a JSON value.
protocol Ocp2TypedBlobRepresentable: Ocp1BlobRepresentable {
  func ocp2EncodeContent(
    state: Ocp2EncodingState,
    codingPath: [any CodingKey]
  ) throws -> Ocp2EncodingNode

  static func ocp2DecodeContent(
    state: Ocp2DecodingState,
    json: Any,
    codingPath: [any CodingKey]
  ) throws -> Self
}

extension OcaTypedBlob: Ocp2TypedBlobRepresentable {
  func ocp2EncodeContent(
    state: Ocp2EncodingState,
    codingPath: [any CodingKey]
  ) throws -> Ocp2EncodingNode {
    try state.encode(content, codingPath: codingPath)
  }

  static func ocp2DecodeContent(
    state: Ocp2DecodingState,
    json: Any,
    codingPath: [any CodingKey]
  ) throws -> Self {
    try Self(state.decode(Content.self, from: json, codingPath: codingPath))
  }
}
#endif
