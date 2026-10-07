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
open class OcaWorker: OcaRoot, OcaOwnablePrivate, @unchecked
Sendable {
  override open class var classID: OcaClassID {
    OcaClassID("1.1")
  }

  override open class var classVersion: OcaClassVersionNumber {
    3
  }

  @OcaProperty(
    propertyID: OcaPropertyID("2.1"),
    getMethodID: OcaMethodID("2.1"),
    setMethodID: OcaMethodID("2.2")
  )
  public var enabled: OcaProperty<OcaBoolean>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.2"),
    getMethodID: OcaMethodID("2.5"),
    ocp2GetName: "OcaPorts"
  )
  public var ports: OcaListProperty<OcaPort>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.3"),
    getMethodID: OcaMethodID("2.8"),
    setMethodID: OcaMethodID("2.9")
  )
  public var label: OcaProperty<OcaString>.PropertyValue

  /// 2.4
  @OcaProperty(
    propertyID: OcaPropertyID("2.4"),
    getMethodID: OcaMethodID("2.10")
  )
  public var owner: OcaProperty<OcaONo>.PropertyValue

  // TODO: this is optional, need to check if this works
  @OcaProperty(
    propertyID: OcaPropertyID("2.5"),
    getMethodID: OcaMethodID("2.11"),
    setMethodID: OcaMethodID("2.12")
  )
  public var latency: OcaProperty<OcaTimeInterval?>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.6"),
    getMethodID: OcaMethodID("2.14"),
    setMethodID: OcaMethodID("2.15"),
    ocp2GetName: "Map",
    ocp2SetName: "Map"
  )
  public var portClockMap: OcaMapProperty<OcaPortID, OcaPortClockMapEntry>.PropertyValue

  public struct AddPortParameters: OcaParametersReflectable {
    public let name: OcaString
    public let mode: OcaPortMode

    public init(name: OcaString, mode: OcaPortMode) {
      self.name = name
      self.mode = mode
    }
  }

  @OcaMethod("2.3", name: "AddPort", parameters: AddPortParameters.self, resultNames: ["ID"])
  public func addPort(name: OcaString, mode: OcaPortMode) async throws -> OcaPortID

  @OcaMethod("2.4", name: "DeletePort", parameterNames: ["ID"])
  public func deletePort(id: OcaPortID) async throws

  @OcaMethod("2.6", name: "GetPortName", parameterNames: ["PortID"], resultNames: ["Name"])
  public func getPortName(portID: OcaPortID) async throws -> OcaString

  /// OcaWorker.SetPortName names its port `ID`, where the other port-bearing
  /// classes say `PortID` (`OcaSetPortNameParameters`).
  public struct SetPortNameParameters: OcaParametersReflectable {
    public let id: OcaPortID
    public let name: OcaString

    public init(id: OcaPortID, name: OcaString) {
      self.id = id
      self.name = name
    }
  }

  @OcaMethod(
    "2.7",
    name: "SetPortName",
    parameters: SetPortNameParameters.self,
    parameterNames: ["ID", "Name"]
  )
  public func setPortName(id: OcaPortID, name: OcaString) async throws

  @OcaMethod("2.13", name: "GetPath")
  public func getPath() async throws -> OcaGetPathParameters

  @OcaMethod("2.16", name: "GetPortClockMapEntry", parameterNames: ["ID"], resultNames: ["Entry"])
  public func getPortClockMapEntry(id: OcaPortID) async throws -> OcaPortClockMapEntry

  @OcaMethod(
    "2.17",
    name: "SetPortClockMapEntry",
    parameters: OcaSetPortClockMapEntryParameters.self
  )
  public func setPortClockMapEntry(portID: OcaPortID, entry: OcaPortClockMapEntry) async throws

  @OcaMethod("2.18", name: "DeletePortClockMapEntry", parameterNames: ["ID"])
  public func deletePortClockMapEntry(id: OcaPortID) async throws
}

extension OcaWorker {
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
