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

/// Contents of `OcaCounterSet.ID` for endpoint countersets; identical in AES70-21
/// (Aes67EndpointCounterSetID) and AES70-22 (MilanEndpointCounterSetID).
public struct OcaMediaStreamEndpointCounterSetID: Ocp1TypedBlobRepresentable, Equatable {
  public static let counterSetsPropertyID = OcaPropertyID("3.12")

  public var ownerONo: OcaONo
  public var counterSetsPropertyID: OcaPropertyID
  public var endpointID: OcaMediaStreamEndpointID

  public init(
    ownerONo: OcaONo,
    counterSetsPropertyID: OcaPropertyID = Self.counterSetsPropertyID,
    endpointID: OcaMediaStreamEndpointID
  ) {
    self.ownerONo = ownerONo
    self.counterSetsPropertyID = counterSetsPropertyID
    self.endpointID = endpointID
  }
}
