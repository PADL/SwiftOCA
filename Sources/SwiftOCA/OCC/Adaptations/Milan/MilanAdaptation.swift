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

/// Constants for the AES70-22 Milan adaptation of CM4.
public enum MilanAdaptation {
  public static let identifier: OcaAdaptationIdentifier = "OcaMilan"
  public static let sessionType: OcaString = "OcaMilan"
  public static let packetTime: OcaTimeInterval = 125e-6
  public static let aafEncodingType: OcaMimeType = "audio/L32"

  /// Output endpoints use the STREAM_OUTPUT index plus this offset (AES70-22 Table 15).
  public static let outputEndpointIDOffset: OcaMediaStreamEndpointID = 1000

  /// AES70-22 §5.2: MilanOcaMediaTransportSessionAgent is 1.2.20.A.2200 with A = AES.
  public static let sessionAgentClassID = OcaClassID(
    parent: OcaClassID("1.2.20"),
    authority: OcaClassID.AESCompanyID,
    0x2200
  )

  public static func inputEndpointID(streamIndex: OcaUint16) -> OcaMediaStreamEndpointID {
    OcaMediaStreamEndpointID(streamIndex) + 1
  }

  public static func outputEndpointID(streamIndex: OcaUint16) -> OcaMediaStreamEndpointID {
    OcaMediaStreamEndpointID(streamIndex) + 1 + outputEndpointIDOffset
  }
}
