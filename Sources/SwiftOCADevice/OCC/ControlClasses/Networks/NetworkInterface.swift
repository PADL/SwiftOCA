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

@OcaDeviceClass
open class OcaNetworkInterface: OcaRoot, OcaOwnable, OcaLabelRepresentable,
  OcaCounterSetRepresentable
{
  override open class var classID: OcaClassID { OcaClassID("1.6") }

  override open class var classVersion: OcaClassVersionNumber { 3 }

  override open class var transientPropertyIDs: Set<OcaPropertyID> { ["2.8", "2.10", "2.11", "2.12"] }

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

  @_spi(SwiftOCAPrivate)
  public nonisolated static var labelPropertyID: OcaPropertyID { OcaPropertyID("2.1") }
  @_spi(SwiftOCAPrivate)
  public nonisolated static var ownerPropertyID: OcaPropertyID { OcaPropertyID("2.2") }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.3"),
    getMethodID: OcaMethodID("2.5"),
    setMethodID: OcaMethodID("2.6")
  )
  public var enabled = true

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.4"),
    getMethodID: OcaMethodID("2.7"),
    setMethodID: OcaMethodID("2.8"),
    ocp2GetName: "Name",
    ocp2SetName: "Identifier"
  )
  public var systemIOInterfaceName = ""

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.5"),
    getMethodID: OcaMethodID("2.9"),
    setMethodID: OcaMethodID("2.10"),
    ocp2GetName: "Id",
    ocp2SetName: "Id"
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
    ocp2GetName: "Identifier"
  )
  public var adaptationIdentifier: OcaAdaptationIdentifier = ""

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.8"),
    getMethodID: OcaMethodID("2.14"),
    ocp2GetName: "Settings"
  )
  public var activeNetworkSettings: OcaAdaptationData = OcaBlob()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.9"),
    getMethodID: OcaMethodID("2.15"),
    setMethodID: OcaMethodID("2.16"),
    ocp2GetName: "Settings",
    ocp2SetName: "Settings"
  )
  public var targetNetworkSettings: OcaAdaptationData = OcaBlob()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.10"),
    getMethodID: OcaMethodID("2.17"),
    ocp2GetName: "Pending"
  )
  public var networkSettingsPending = false

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

  @_spi(SwiftOCAPrivate)
  public static var counterSetPropertyID: OcaPropertyID { OcaPropertyID("2.13") }

  /// A private property (AES70-2:2024 §6.8): it raises no PropertyChanged, and a controller
  /// reads it with GetCounterSet.
  public var counterSet = OcaCounterSet() {
    didSet { counterSetsDidChange(formerly: [oldValue]) }
  }

  @_spi(SwiftOCAPrivate)
  public let counterSetChanges = OcaCounterSetChanges()

  open var allCounterSets: [OcaCounterSet] { [counterSet] }

  open func didRegister() async {
    counterSetOwnerDidRegister()
  }

  open func didDeregister() async {
    counterSetOwnerDidDeregister()
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkInterface.Methods.getCounterSet)
  func getCounterSet(from controller: any OcaController) -> OcaCounterSet {
    counterSet
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkInterface.Methods.attachCounterNotifier)
  open func attachCounterNotifier(
    counterID: OcaID16,
    oNo: OcaONo,
    from controller: any OcaController
  ) async throws {
    try await ensureCounterNotifier(oNo)
    try counterSet.attach(notifier: oNo, to: counterID)
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkInterface.Methods.detachCounterNotifier)
  open func detachCounterNotifier(
    counterID: OcaID16,
    oNo: OcaONo,
    from controller: any OcaController
  ) async throws {
    try counterSet.detach(notifier: oNo, from: counterID)
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkInterface.Methods.resetCounters)
  open func resetCounters(from controller: any OcaController) async throws {
    try reset(&counterSet)
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkInterface.Methods.applyCommand)
  open func applyCommand(command: OcaNetworkInterfaceCommand, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkInterface.Methods.getPath)
  func getPath(from controller: any OcaController) async -> OcaGetPathParameters {
    await path
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkInterface.Methods.getCounter)
  func getCounter(counterID: OcaID16, from controller: any OcaController) throws -> OcaCounter {
    try counterSet.existingCounter(id: counterID)
  }
}
