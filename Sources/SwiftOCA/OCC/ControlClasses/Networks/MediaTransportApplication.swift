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

open class OcaMediaTransportApplication: OcaNetworkApplication, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.7.1") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  func add(port label: OcaString, mode: OcaIODirection) async throws -> OcaPortID {
    struct AddPortParameters: Ocp1ParametersReflectable {
      let label: OcaString
      let mode: OcaPortMode
    }
    let params = AddPortParameters(label: label, mode: mode)
    return try await sendCommandRrq(
      methodID: OcaMethodID("3.1"),
      parameters: params
    )
  }

  func delete(port id: OcaPortID) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.2"),
      parameters: id
    )
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.3")
  )
  public var ports: OcaProperty<OcaPort>.PropertyValue

  public func getPortName() async throws -> OcaString {
    try await sendCommandRrq(methodID: OcaMethodID("3.4"))
  }

  public func setPortName(_ name: OcaString) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.5"), parameters: name)
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.6"),
    setMethodID: OcaMethodID("3.7")
  )
  public var portClockMap: OcaMapProperty<OcaPortID, OcaPortClockMapEntry>.PropertyValue

  public func get(portID: OcaPortID) async throws -> OcaPortClockMapEntry {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.10"),
      parameters: portID
    )
  }

  public typealias SetPortClockMapEntryParameters = OcaSetPortClockMapEntryParameters

  public func set(portID: OcaPortID, portClockMapEntry: OcaPortClockMapEntry) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.8"),
      parameters: SetPortClockMapEntryParameters(
        portID: portID,
        portClockMapEntry: portClockMapEntry
      )
    )
  }

  public func deletePortClockMapEntry(portID: OcaPortID) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.9"),
      parameters: portID
    )
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.3")
  )
  public var maxInputEndpoints: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.4")
  )
  public var maxOutputEndpoints: OcaProperty<OcaUint16>.PropertyValue

  // 3.11 getMaxEndpointCounts

  @OcaProperty(
    propertyID: OcaPropertyID("3.5"),
    getMethodID: OcaMethodID("3.12")
  )
  public var maxPortsPerChannel: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.6"),
    getMethodID: OcaMethodID("3.13")
  )
  public var maxChannelsPerEndpoint: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.7"),
    getMethodID: OcaMethodID("3.15"),
    setMethodID: OcaMethodID("3.16")
  )
  public var mediaStreamModeCapabilities: OcaListProperty<OcaMediaStreamModeCapability>
    .PropertyValue

  // 3.17 getMediaStreamModeCapability

  @OcaProperty(
    propertyID: OcaPropertyID("3.8"),
    getMethodID: OcaMethodID("3.18"),
    setMethodID: OcaMethodID("3.19")
  )
  public var transportTimingParameters: OcaProperty<OcaMediaTransportTimingParameters>
    .PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.9"),
    getMethodID: OcaMethodID("3.20"),
    setMethodID: OcaMethodID("3.14")
  )
  public var alignmentLevelLimits: OcaProperty<OcaInterval<OcaDBFS>>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.10"),
    getMethodID: OcaMethodID("3.21")
  )
  public var endpoints: OcaListProperty<OcaMediaStreamEndpoint>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.11"),
    getMethodID: OcaMethodID("3.23")
  )
  public var endpointStatuses: OcaProperty<
    [OcaMediaStreamEndpointID: OcaMediaStreamEndpointStatus]
  >
  .PropertyValue

  // 3.24 getEndpointStatus
  // 3.25 addEndpoint
  // 3.26 deleteEndpoint
  // 3.27 applyEndpointCommand
  // 3.28 setEndpointUserLabel
  // 3.29 setEndpointMediaStreamMode
  // 3.30 setEndpointChannelMap
  // 3.31 setEndpointAlignmentLevel
  // 3.32 getEndpointTimeSource

  @OcaProperty(
    propertyID: OcaPropertyID("3.12"),
    getMethodID: OcaMethodID("3.34")
  )
  public var endpointCounterSets: OcaMapProperty<OcaID16, OcaCounterSet>.PropertyValue

  // 3.35 getEndpointCounterSet
  // 3.36 getEndpointCounter
  // 3.37 attachEndpointCounterNotifier
  // 3.38 detachEndpointCounterNotifier
  // 3.39 resetEndpointCounterSet

  @OcaProperty(
    propertyID: OcaPropertyID("3.13"),
    getMethodID: OcaMethodID("3.40"),
    setMethodID: OcaMethodID("3.41")
  )
  public var transportSessionControlAgentONos: OcaListProperty<OcaONo>.PropertyValue
}
