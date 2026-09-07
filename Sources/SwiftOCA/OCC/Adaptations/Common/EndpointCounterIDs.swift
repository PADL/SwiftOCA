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

/// Counter identifiers shared by the CM4 adaptations (AES70-21 Tables 4/5, AES70-22
/// Tables 5/19/20). The numbering is aligned across adaptations by design.
public enum OcaNetworkInterfaceCounterID {
  public static let linkUp: OcaID16 = 1
  public static let linkDown: OcaID16 = 2
  public static let framesTx: OcaID16 = 3
  public static let framesRx: OcaID16 = 4
  public static let rxCRCError: OcaID16 = 5
  public static let gptpGMChanged: OcaID16 = 6
}

public enum OcaMediaStreamInputEndpointCounterID {
  public static let mediaLocked: OcaID16 = 1
  public static let mediaUnlocked: OcaID16 = 2
  public static let streamInterrupted: OcaID16 = 3
  public static let seqNumMismatch: OcaID16 = 4
  public static let mediaReset: OcaID16 = 5
  public static let timestampUncertain: OcaID16 = 6
  public static let unsupportedFormat: OcaID16 = 9
  public static let lateTimestamp: OcaID16 = 10
  public static let earlyTimestamp: OcaID16 = 11
  public static let framesRx: OcaID16 = 12
}

public enum OcaMediaStreamOutputEndpointCounterID {
  public static let streamStart: OcaID16 = 1
  public static let streamStop: OcaID16 = 2
  public static let mediaReset: OcaID16 = 3
  public static let timestampUncertain: OcaID16 = 4
  public static let framesTx: OcaID16 = 5
}
