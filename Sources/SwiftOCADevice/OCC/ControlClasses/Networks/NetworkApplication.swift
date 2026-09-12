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

open class OcaNetworkApplication: OcaRoot, OcaOwnable, OcaLabelRepresentable,
  OcaCounterSetRepresentable
{
  override open class var classID: OcaClassID { OcaClassID("1.7") }

  override open class var classVersion: OcaClassVersionNumber { 3 }

  override open class var transientPropertyIDs: Set<OcaPropertyID> { ["2.6"] }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.1"),
    getMethodID: OcaMethodID("2.1"),
    setMethodID: OcaMethodID("2.2")
  )
  public var label = ""

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.2"),
    getMethodID: OcaMethodID("2.3")
  )
  public var owner = OcaInvalidONo

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.3"),
    getMethodID: OcaMethodID("2.5"),
    setMethodID: OcaMethodID("2.6"),
    ocp2GetName: "Assignments",
    ocp2SetName: "Assignments"
  )
  public var networkInterfaceAssignments = [OcaNetworkInterfaceAssignment]()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.4"),
    getMethodID: OcaMethodID("2.7"),
    ocp2GetName: "Identifier"
  )
  public var adaptationIdentifier: OcaAdaptationIdentifier = ""

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.5"),
    getMethodID: OcaMethodID("2.8"),
    setMethodID: OcaMethodID("2.9"),
    ocp2GetName: "Data",
    ocp2SetName: "Data"
  )
  public var adaptationData: OcaAdaptationData = OcaBlob()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.6"),
    getMethodID: OcaMethodID("2.10")
  )
  public var counterSet = OcaCounterSet()

  open func attach(counter id: OcaID16, to oNo: OcaONo) async throws {
    try attach(counterNotifier: oNo, to: id)
  }

  open func detach(counter id: OcaID16, from oNo: OcaONo) async throws {
    try detach(counterNotifier: oNo, from: id)
  }

  open func resetCounters(_ id: OcaID16) async throws {
    resetCounters(id: id)
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("2.4"):
      try decodeNullCommand(command)
      return try await controller.encodeResponse(path)
    case OcaMethodID("2.11"):
      let id: OcaID16 = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try controller.encodeResponse(counter(id: id), name: "Counter")
    case OcaMethodID("2.12"):
      let parameters: OcaCounterNotifierParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await attach(counter: parameters.id, to: parameters.oNo)
      return Ocp1Response()
    case OcaMethodID("2.13"):
      let parameters: OcaCounterNotifierParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await detach(counter: parameters.id, from: parameters.oNo)
      return Ocp1Response()
    case OcaMethodID("2.14"):
      let id: OcaID16 = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await resetCounters(id)
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
