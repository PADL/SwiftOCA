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

/// Constants for the AES70-23 Dante adaptation of CM4. AES70-23 is still a draft; its
/// channel-endpoint methods carry provisional IDs.
public enum DanteAdaptation {
  public static let identifier: OcaAdaptationIdentifier = "OcaDante"

  /// The draft prints 1.2.20.A.2300, but the class subclasses OcaMediaTransportApplication.
  public static let mediaTransportApplicationClassID = OcaClassID(
    parent: OcaClassID("1.7.1"),
    authority: OcaClassID.AESCompanyID,
    0x2300
  )
}
