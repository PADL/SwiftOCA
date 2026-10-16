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

/// Constants for the AES70-21 AES67 / ST 2110-30 adaptation of CM4. AES70-21 is still a
/// draft; method IDs marked "draft" are provisional.
public enum Aes67Adaptation {
  public static let identifier: OcaAdaptationIdentifier = "OcaAes67"

  /// Class ID fields are written in decimal, so these suffixes are 2100 to 2103.
  public static let mediaTransportApplicationClassID = OcaClassID(
    parent: OcaClassID("1.7.1"),
    authority: OcaClassID.AESCompanyID,
    2100
  )

  public static let mediaTransportSessionAgentClassID = OcaClassID(
    parent: OcaClassID("1.2.20"),
    authority: OcaClassID.AESCompanyID,
    2101
  )

  public static let streamEndpointRegistryClassID = OcaClassID(
    parent: OcaClassID("1.2"),
    authority: OcaClassID.AESCompanyID,
    2102
  )

  public static let sdpAgentClassID = OcaClassID(
    parent: OcaClassID("1.2"),
    authority: OcaClassID.AESCompanyID,
    2103
  )
}

public extension Aes67Adaptation {
  /// Selects the stream a ConfigureEndpointFromSDP call names, following AES70-21 §10.2.4
  /// Table 18 (single-stream SDP) and Table 19 (multistream SDP).
  ///
  /// - Parameters:
  ///   - streamID: the call's StreamID parameter, an SDP Stream Source ID (`<ssrc-id>`).
  ///   - ssrcIDs: the `<ssrc-id>` of each media description of the SDP string, in order,
  ///     or zero for a media description without one.
  /// - Returns: the index into `ssrcIDs` of the selected media description. Its
  ///   `<ssrc-id>` is the value the endpoint's AdaptationData.StreamID takes.
  /// - Throws: `Ocp1Error.status(.badFormat)` for an SDP string with no media
  ///   descriptions, or a multistream one in which a media description has no `<ssrc-id>`;
  ///   `Ocp1Error.status(.parameterError)` when `streamID` does not select a stream.
  static func selectStream(streamID: OcaUint32, ssrcIDs: [OcaUint32]) throws -> Int {
    switch ssrcIDs.count {
    case 0:
      throw Ocp1Error.status(.badFormat)
    case 1:
      // Table 18: only two nonzero values that differ fail
      let ssrcID = ssrcIDs[0]
      guard streamID == 0 || ssrcID == 0 || streamID == ssrcID else {
        throw Ocp1Error.status(.parameterError)
      }
      return 0
    default:
      // Table 19: every stream needs an <ssrc-id>, and StreamID must name one of them
      guard !ssrcIDs.contains(0) else { throw Ocp1Error.status(.badFormat) }
      guard streamID != 0, let index = ssrcIDs.firstIndex(of: streamID) else {
        throw Ocp1Error.status(.parameterError)
      }
      return index
    }
  }
}
