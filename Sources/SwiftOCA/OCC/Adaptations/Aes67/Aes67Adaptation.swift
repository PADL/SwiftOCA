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
  public static let streamSourceRegistryPurpose: OcaString = "stream-source-registry"

  public static let mediaTransportApplicationClassID = OcaClassID(
    parent: OcaClassID("1.7.1"),
    authority: OcaClassID.AESCompanyID,
    0x2100
  )

  public static let mediaTransportSessionAgentClassID = OcaClassID(
    parent: OcaClassID("1.2.20"),
    authority: OcaClassID.AESCompanyID,
    0x2101
  )

  public static let streamSourceListAgentClassID = OcaClassID(
    parent: OcaClassID("1.2"),
    authority: OcaClassID.AESCompanyID,
    0x2102
  )
}
