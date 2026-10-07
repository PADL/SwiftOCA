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

@OcaClass
open class OcaNetworkApplication: OcaRoot, OcaOwnablePrivate, @unchecked
Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.7") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaProperty(
    propertyID: OcaPropertyID("2.1"),
    getMethodID: OcaMethodID("2.1"),
    setMethodID: OcaMethodID("2.2")
  )
  public var label: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.2"),
    getMethodID: OcaMethodID("2.3")
  )
  public var owner: OcaProperty<OcaONo>.PropertyValue

  @OcaMethod("2.4", name: "GetPath")
  public func getPath() async throws -> OcaGetPathParameters

  @OcaProperty(
    propertyID: OcaPropertyID("2.3"),
    getMethodID: OcaMethodID("2.5"),
    setMethodID: OcaMethodID("2.6"),
    ocp2GetName: "Assignments",
    ocp2SetName: "Assignments"
  )
  public var networkInterfaceAssignments: OcaListProperty<OcaNetworkInterfaceAssignment>
    .PropertyValue

  // "OcaOcp1" for OCP.1
  @OcaProperty(
    propertyID: OcaPropertyID("2.4"),
    getMethodID: OcaMethodID("2.7"),
    ocp2GetName: "Identifier"
  )
  public var adaptationIdentifier: OcaProperty<OcaAdaptationIdentifier>.PropertyValue

  // (null) for OCP.1
  @OcaProperty(
    propertyID: OcaPropertyID("2.5"),
    getMethodID: OcaMethodID("2.8"),
    setMethodID: OcaMethodID("2.9"),
    ocp2GetName: "Data",
    ocp2SetName: "Data"
  )
  public var adaptationData: OcaProperty<OcaAdaptationData>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.6"),
    getMethodID: OcaMethodID("2.10")
  )
  public var counterSet: OcaProperty<OcaCounterSet>.PropertyValue

  @OcaMethod("2.11", name: "GetCounter", parameterNames: ["CounterID"], resultNames: ["Counter"])
  public func getCounter(counterID: OcaID16) async throws -> OcaCounter

  @OcaMethod(
    "2.12",
    name: "AttachCounterNotifier",
    parameters: OcaCounterIDNotifierParameters.self,
    parameterNames: ["CounterID", "ONo"]
  )
  public func attachCounterNotifier(counterID: OcaID16, oNo: OcaONo) async throws

  @OcaMethod(
    "2.13",
    name: "DetachCounterNotifier",
    parameters: OcaCounterIDNotifierParameters.self,
    parameterNames: ["CounterID", "ONo"]
  )
  public func detachCounterNotifier(counterID: OcaID16, oNo: OcaONo) async throws

  /// Resets every counter in the counterset.
  @OcaMethod("2.14", name: "ResetCounters")
  public func resetCounters() async throws
}

extension OcaNetworkApplication {
  @_spi(SwiftOCAPrivate)
  public func _getOwner(flags: OcaPropertyResolutionFlags = .defaultFlags) async throws
    -> OcaONo
  {
    guard objectNumber != OcaRootBlockONo else { throw Ocp1Error.status(.invalidRequest) }
    return try await $owner._getValue(self, flags: flags)
  }

  func _set(owner: OcaONo) {
    self.$owner.subject.send(.success(owner))
  }
}
