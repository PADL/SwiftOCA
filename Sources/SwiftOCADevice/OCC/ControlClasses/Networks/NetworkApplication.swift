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

@OcaDeviceMethods
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

  open func resetCounters() async throws {
    resetCounterSet()
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkApplication.getPath, access: .read)
  func getPath(from controller: any OcaController) async -> OcaGetPathParameters {
    await path
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkApplication.getCounter, access: .read)
  func getCounter(_ id: OcaID16, from controller: any OcaController) throws -> OcaCounter {
    try counter(id: id)
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkApplication.attachCounterNotifier, access: .write)
  func attachCounterNotifier(_ parameters: OcaCounterNotifierParameters, from controller: any OcaController) async throws {
    try await attach(counter: parameters.id, to: parameters.oNo)
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkApplication.detachCounterNotifier, access: .write)
  func detachCounterNotifier(_ parameters: OcaCounterNotifierParameters, from controller: any OcaController) async throws {
    try await detach(counter: parameters.id, from: parameters.oNo)
  }

  @OcaDeviceMethod(SwiftOCA.OcaNetworkApplication.resetCounters, access: .write)
  func resetCounters(from controller: any OcaController) async throws {
    try await resetCounters()
  }
}
