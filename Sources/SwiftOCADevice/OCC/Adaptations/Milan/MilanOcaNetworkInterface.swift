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

import SwiftOCA

/// AES70-22 §7.2: one OcaNetworkInterface per AVB interface. Shares class ID 1.6 with
/// its superclass, so it is not registered.
open class MilanOcaNetworkInterface: OcaNetworkInterface {
  public required init(
    objectNumber: OcaONo? = nil,
    lockable: OcaBoolean = true,
    role: OcaString? = nil,
    deviceDelegate: OcaDevice? = nil,
    addToRootBlock: Bool = true
  ) async throws {
    try await super.init(
      objectNumber: objectNumber,
      lockable: lockable,
      role: role,
      deviceDelegate: deviceDelegate,
      addToRootBlock: addToRootBlock
    )
    adaptationIdentifier = MilanAdaptation.identifier
    groupID = 0
    counterSet = OcaCounterSet(
      id: try OcaBlob(Ocp1Encoder().encode(self.objectNumber) as [UInt8]),
      counter: Self.makeCounters()
    )
  }

  public required init(from decoder: Decoder) throws {
    throw Ocp1Error.notImplemented
  }

  /// The AES70-22 Table 5 counters, initially zero.
  public static func makeCounters() -> [OcaCounter] {
    [
      (MilanNetworkInterfaceCounterID.linkUp, "LINK_UP"),
      (MilanNetworkInterfaceCounterID.linkDown, "LINK_DOWN"),
      (MilanNetworkInterfaceCounterID.framesTx, "FRAMES_TX"),
      (MilanNetworkInterfaceCounterID.framesRx, "FRAMES_RX"),
      (MilanNetworkInterfaceCounterID.rxCRCError, "RX_CRC_ERROR"),
      (MilanNetworkInterfaceCounterID.gptpGMChanged, "GPTP_GM_CHANGED"),
    ].map { OcaCounter(id: $0.0, value: 0, initialValue: 0, role: $0.1, notifiers: []) }
  }

  /// Status.State follows the LINK_UP and LINK_DOWN counters (AES70-22 §7.2.3).
  public func updateStatus(msrpMappings: [MilanMSRPMapping]) throws {
    let linkUp = counterSet.counter(id: MilanNetworkInterfaceCounterID.linkUp)?.value ?? 0
    let linkDown = counterSet.counter(id: MilanNetworkInterfaceCounterID.linkDown)?.value ?? 0
    let newStatus = OcaNetworkInterfaceStatus(
      state: linkUp > linkDown ? .ready : .notReady,
      adaptationData: try msrpMappings.blob
    )
    if status != newStatus {
      status = newStatus
    }
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("2.10"), // SetGroupID
         OcaMethodID("2.12"), // SetPrecedence
         OcaMethodID("2.15"), // GetRequestedAdaptationData
         OcaMethodID("2.16"), // SetRequestedAdaptationData
         OcaMethodID("2.24"), // ResetCounters
         OcaMethodID("2.25"): // ApplyCommand
      throw Ocp1Error.status(.notImplemented)
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
