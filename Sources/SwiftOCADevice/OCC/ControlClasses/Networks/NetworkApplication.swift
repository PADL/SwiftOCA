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
open class OcaNetworkApplication: OcaRoot, OcaOwnable, OcaLabelRepresentable,
  OcaCounterSetRepresentable
{
  override open class var classID: OcaClassID { OcaClassID("1.7") }

  override open class var classVersion: OcaClassVersionNumber { 3 }

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

  @_spi(SwiftOCAPrivate)
  public static var counterSetPropertyID: OcaPropertyID { OcaPropertyID("2.6") }

  /// A private property (AES70-2:2024 §6.8): it raises no PropertyChanged, and a controller
  /// reads it with GetCounterSet.
  public var counterSet = OcaCounterSet() {
    didSet { counterSetsDidChange(formerly: [oldValue]) }
  }

  @_spi(SwiftOCAPrivate)
  public let counterSetChanges = OcaCounterSetChanges()

  @OcaDeviceMethod(SwiftOCA.OcaNetworkApplication.Methods.getCounterSet)
  func getCounterSet(from controller: any OcaController) -> OcaCounterSet {
    counterSet
  }

  open var allCounterSets: [OcaCounterSet] { [counterSet] }

  open func didRegister() async {
    counterSetOwnerDidRegister()
  }

  open func didDeregister() async {
    counterSetOwnerDidDeregister()
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkApplication.Methods.attachCounterNotifier)
  open func attachCounterNotifier(
    counterID: OcaID16,
    oNo: OcaONo,
    from controller: any OcaController
  ) async throws {
    try await ensureCounterNotifier(oNo)
    try counterSet.attach(notifier: oNo, to: counterID)
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkApplication.Methods.detachCounterNotifier)
  open func detachCounterNotifier(
    counterID: OcaID16,
    oNo: OcaONo,
    from controller: any OcaController
  ) async throws {
    try counterSet.detach(notifier: oNo, from: counterID)
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkApplication.Methods.resetCounters)
  open func resetCounters(from controller: any OcaController) async throws {
    try reset(&counterSet)
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkApplication.Methods.getPath)
  func getPath(from controller: any OcaController) async -> OcaGetPathParameters {
    await path
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkApplication.Methods.getCounter)
  func getCounter(counterID: OcaID16, from controller: any OcaController) throws -> OcaCounter {
    try counterSet.existingCounter(id: counterID)
  }
}
