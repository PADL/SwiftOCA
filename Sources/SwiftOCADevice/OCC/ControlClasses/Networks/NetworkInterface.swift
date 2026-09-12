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

open class OcaNetworkInterface: OcaRoot, OcaOwnable, OcaLabelRepresentable,
  OcaCounterSetRepresentable
{
  override open class var classID: OcaClassID { OcaClassID("1.6") }

  override open class var classVersion: OcaClassVersionNumber { 3 }

  override open class var transientPropertyIDs: Set<OcaPropertyID> { ["2.8", "2.10", "2.11", "2.12", "2.13"] }

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
    setMethodID: OcaMethodID("2.6")
  )
  public var enabled = true

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.4"),
    getMethodID: OcaMethodID("2.7"),
    setMethodID: OcaMethodID("2.8")
  )
  public var systemIOInterfaceName = ""

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.5"),
    getMethodID: OcaMethodID("2.9"),
    setMethodID: OcaMethodID("2.10"),
    ocp2Name: "Id"
  )
  public var groupID: OcaUint16 = 0

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.6"),
    getMethodID: OcaMethodID("2.11"),
    setMethodID: OcaMethodID("2.12")
  )
  public var precedence: OcaUint16 = 1

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.7"),
    getMethodID: OcaMethodID("2.13"),
    ocp2Name: "Identifier"
  )
  public var adaptationIdentifier: OcaAdaptationIdentifier = ""

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.8"),
    getMethodID: OcaMethodID("2.14"),
    ocp2Name: "Settings"
  )
  public var currentAdaptationData: OcaAdaptationData = OcaBlob()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.9"),
    getMethodID: OcaMethodID("2.15"),
    setMethodID: OcaMethodID("2.16"),
    ocp2Name: "Settings"
  )
  public var requestedAdaptationData: OcaAdaptationData = OcaBlob()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.10"),
    getMethodID: OcaMethodID("2.17"),
    ocp2Name: "Pending"
  )
  public var networkSettingPending = false

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.11"),
    getMethodID: OcaMethodID("2.18")
  )
  public var status = OcaNetworkInterfaceStatus(state: .notReady, adaptationData: OcaBlob())

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.12"),
    getMethodID: OcaMethodID("2.19")
  )
  public var errorCode: OcaUint16 = 0

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.13"),
    getMethodID: OcaMethodID("2.20")
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

  open func apply(command: OcaNetworkInterfaceCommand) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("2.4"):
      try decodeNullCommand(command)
      return try await controller.encodeResponse(path)
    case OcaMethodID("2.21"):
      let id: OcaID16 = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try controller.encodeResponse(counter(id: id), name: "Counter")
    case OcaMethodID("2.22"):
      let parameters: OcaCounterNotifierParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await attach(counter: parameters.id, to: parameters.oNo)
      return Ocp1Response()
    case OcaMethodID("2.23"):
      let parameters: OcaCounterNotifierParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await detach(counter: parameters.id, from: parameters.oNo)
      return Ocp1Response()
    case OcaMethodID("2.24"):
      let id: OcaID16 = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await resetCounters(id)
      return Ocp1Response()
    case OcaMethodID("2.25"):
      let networkInterfaceCommand: OcaNetworkInterfaceCommand = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await apply(command: networkInterfaceCommand)
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
