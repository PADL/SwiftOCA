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
    (OcaMediaTransportSessionAgent.self, [
      ("getSession", OcaMediaTransportSessionAgent.getSession.erased),
      ("addSession", OcaMediaTransportSessionAgent.addSession.erased),
      ("deleteSession", OcaMediaTransportSessionAgent.deleteSession.erased),
    ]),
    (OcaWorker.self, [
      ("setPortName", OcaWorker.setPortName.erased),
      ("getPath", OcaWorker.getPath.erased),
      ("getPortClockMapEntry", OcaWorker.getPortClockMapEntry.erased),
      ("setPortClockMapEntry", OcaWorker.setPortClockMapEntry.erased),
      ("deletePortClockMapEntry", OcaWorker.deletePortClockMapEntry.erased),
    ]),
  ]
}
