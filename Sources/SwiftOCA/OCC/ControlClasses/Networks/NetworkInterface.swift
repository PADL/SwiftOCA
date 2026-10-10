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
open class OcaNetworkInterface: OcaRoot, OcaOwnablePrivate, @unchecked
Sendable {
  override open class var classID: OcaClassID {
    OcaClassID("1.6")
  }

  override open class var classVersion: OcaClassVersionNumber {
    3
  }

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
    setMethodID: OcaMethodID("2.6")
  )
  public var enabled: OcaProperty<OcaBoolean>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.4"),
    getMethodID: OcaMethodID("2.7"),
    setMethodID: OcaMethodID("2.8"),
    ocp2GetName: "Name",
    ocp2SetName: "Identifier"
  )
  public var systemIOInterfaceName: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.5"),
    getMethodID: OcaMethodID("2.9"),
    setMethodID: OcaMethodID("2.10"),
    ocp2GetName: "Id",
    ocp2SetName: "Id"
  )
  public var groupID: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.6"),
    getMethodID: OcaMethodID("2.11"),
    setMethodID: OcaMethodID("2.12")
  )
  public var precedence: OcaProperty<OcaUint16>.PropertyValue

  /// "OcaIP4" or "OcaIP6"
  @OcaProperty(
    propertyID: OcaPropertyID("2.7"),
    getMethodID: OcaMethodID("2.13"),
    ocp2GetName: "Identifier"
  )
  public var adaptationIdentifier: OcaProperty<OcaAdaptationIdentifier>.PropertyValue

  /// adaptation-specific, e.g. encoded OcaIP4NetworkSettings or MilanNetworkInterfaceAdaptationData
  @OcaProperty(
    propertyID: OcaPropertyID("2.8"),
    getMethodID: OcaMethodID("2.14"),
    ocp2GetName: "Settings"
  )
  public var activeNetworkSettings: OcaProperty<OcaBlob>.PropertyValue

  /// adaptation-specific, e.g. encoded OcaIP4NetworkSettings or MilanNetworkInterfaceAdaptationData
  @OcaProperty(
    propertyID: OcaPropertyID("2.9"),
    getMethodID: OcaMethodID("2.15"),
    setMethodID: OcaMethodID("2.16"),
    ocp2GetName: "Settings",
    ocp2SetName: "Settings"
  )
  public var targetNetworkSettings: OcaProperty<OcaBlob>.PropertyValue

  /// adaptation-specific, e.g. encoded OcaIP4NetworkSettings or MilanNetworkInterfaceAdaptationData
  @OcaProperty(
    propertyID: OcaPropertyID("2.10"),
    getMethodID: OcaMethodID("2.17"),
    ocp2GetName: "Pending"
  )
  public var networkSettingsPending: OcaProperty<OcaBoolean>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.11"),
    getMethodID: OcaMethodID("2.18")
  )
  public var status: OcaProperty<OcaNetworkInterfaceStatus>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.12"),
    getMethodID: OcaMethodID("2.19")
  )
  public var errorCode: OcaProperty<OcaUint16>.PropertyValue

  /// The counter set, a private property (AES70-2:2024 §6.8) read only through this method.
  @OcaMethod("2.20", name: "GetCounterSet", resultNames: ["CounterSet"])
  public func getCounterSet() async throws -> OcaCounterSet

  @OcaMethod("2.21", name: "GetCounter", parameterNames: ["CounterID"], resultNames: ["Counter"])
  public func getCounter(counterID: OcaID16) async throws -> OcaCounter

  @OcaMethod(
    "2.22",
    name: "AttachCounterNotifier",
    parameters: OcaCounterIDNotifierParameters.self,
    parameterNames: ["CounterID", "ONo"]
  )
  public func attachCounterNotifier(counterID: OcaID16, oNo: OcaONo) async throws

  @OcaMethod(
    "2.23",
    name: "DetachCounterNotifier",
    parameters: OcaCounterIDNotifierParameters.self,
    parameterNames: ["CounterID", "ONo"]
  )
  public func detachCounterNotifier(counterID: OcaID16, oNo: OcaONo) async throws

  /// Resets every counter in the counterset.
  @OcaMethod("2.24", name: "ResetCounters")
  public func resetCounters() async throws

  @OcaMethod("2.25", name: "ApplyCommand", parameterNames: ["Command"])
  public func applyCommand(command: OcaNetworkInterfaceCommand) async throws
}

extension OcaNetworkInterface {
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
