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

/// Every `OcaMethodDescription` a client class declares, by class, for the naming oracle
/// and the device sweep. Written from the sources; `ClientMethodDescriptionTests`
/// checks it against them, so a descriptor missing here fails.
enum ClientMethodDescriptions {
  typealias Entry = (name: String, description: OcaAnyMethodDescription)

  static let all: [(type: OcaRoot.Type, descriptors: [Entry])] = [
    (OcaAgent.self, [
      ("getPath", OcaAgent.getPath.erased),
    ]),
    (OcaApplicationNetwork.self, [
      ("getPath", OcaApplicationNetwork.getPath.erased),
    ]),
    (OcaMediaTransportSessionAgent.self, [
      ("getSession", OcaMediaTransportSessionAgent.getSession.erased),
      ("addSession", OcaMediaTransportSessionAgent.addSession.erased),
      ("deleteSession", OcaMediaTransportSessionAgent.deleteSession.erased),
    ]),
    (OcaNetworkApplication.self, [
      ("getPath", OcaNetworkApplication.getPath.erased),
    ]),
    (OcaNetworkInterface.self, [
      ("getPath", OcaNetworkInterface.getPath.erased),
    ]),
    (OcaRoot.self, [
      ("getLockable", OcaRoot.getLockable.erased),
      ("getRole", OcaRoot.getRole.erased),
      ("getLockState", OcaRoot.getLockState.erased),
      ("getClassIdentification", OcaRoot.getClassIdentification.erased),
      ("setLockNoReadWrite", OcaRoot.setLockNoReadWrite.erased),
      ("unlock", OcaRoot.unlock.erased),
      ("setLockNoWrite", OcaRoot.setLockNoWrite.erased),
    ]),
    (OcaWorker.self, [
      ("addPort", OcaWorker.addPort.erased),
      ("deletePort", OcaWorker.deletePort.erased),
      ("getPortName", OcaWorker.getPortName.erased),
      ("setPortName", OcaWorker.setPortName.erased),
      ("getPath", OcaWorker.getPath.erased),
      ("getPortClockMapEntry", OcaWorker.getPortClockMapEntry.erased),
      ("setPortClockMapEntry", OcaWorker.setPortClockMapEntry.erased),
      ("deletePortClockMapEntry", OcaWorker.deletePortClockMapEntry.erased),
    ]),
  ]
}
