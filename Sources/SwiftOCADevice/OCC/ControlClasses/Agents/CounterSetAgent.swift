//
// Copyright (c) 2024 PADL Software Pty Ltd
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

import Foundation
@_spi(SwiftOCAPrivate)
import SwiftOCA

open class OcaCounterSetAgent: OcaAgent {
  override open class var classID: OcaClassID { OcaClassID("1.2.19") }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    setMethodID: OcaMethodID("3.2")
  )
  public var counterSet: OcaCounterSet?

  open func get(counter id: OcaID16) async throws -> OcaCounter {
    throw Ocp1Error.status(.notImplemented)
  }

  open func attach(counter id: OcaID16, to oNo: OcaONo) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func detach(counter id: OcaID16, from oNo: OcaONo) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func reset() async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func reset(counter id: OcaID16) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.3"):
      let id: OcaID16 = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      return try await encodeResponse(get(counter: id))
    case OcaMethodID("3.4"):
      let parameters: SwiftOCA.OcaCounterSetAgent
        .CounterNotifierParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await attach(counter: parameters.id, to: parameters.oNo)
      return Ocp1Response()
    case OcaMethodID("3.5"):
      let parameters: SwiftOCA.OcaCounterSetAgent
        .CounterNotifierParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await detach(counter: parameters.id, from: parameters.oNo)
      return Ocp1Response()
    case OcaMethodID("3.6"):
      try decodeNullCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await reset()
      return Ocp1Response()
    case OcaMethodID("3.7"):
      let id: OcaID16 = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await reset(counter: id)
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
