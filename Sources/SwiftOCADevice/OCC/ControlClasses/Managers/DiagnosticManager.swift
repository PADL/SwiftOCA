//
// Copyright (c) 2023 PADL Software Pty Ltd
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

open class OcaDiagnosticManager: OcaManager {
  override open class var classID: OcaClassID { OcaClassID("1.3.13") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  public convenience init(deviceDelegate: OcaDevice? = nil) async throws {
    try await self.init(
      objectNumber: OcaDiagnosticManagerONo,
      role: "Diagnostic Manager",
      deviceDelegate: deviceDelegate,
      addToRootBlock: true
    )
  }

  override public func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.1"):
      let oNo: OcaONo = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      guard let object = await deviceDelegate?.resolve(objectNumber: oNo) else {
        throw Ocp1Error.status(.badONo)
      }
      return try encodeResponse(String(describing: object.lockState))
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
