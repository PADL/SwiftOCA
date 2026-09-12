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
  override open class var classID: OcaClassID {
    OcaClassID("1.7.1")
  }

  override open class var classVersion: OcaClassVersionNumber {
    3
  }

  // MARK: - Parameter structures shared with SwiftOCADevice

  /// OcaMediaTransportApplication.AddPort names its label `Name`.
  public struct AddPortParameters: Ocp1ParametersReflectable {
    public let name: OcaString
    public let mode: OcaPortMode

    public init(name: OcaString, mode: OcaPortMode) {
      self.name = name
      self.mode = mode
    }
  }

  public struct MaxEndpointCounts: Ocp1ParametersReflectable, Equatable {
    public let maxInputEndpoints: OcaUint16
    public let maxOutputEndpoints: OcaUint16

    public init(maxInputEndpoints: OcaUint16, maxOutputEndpoints: OcaUint16) {
      self.maxInputEndpoints = maxInputEndpoints
      self.maxOutputEndpoints = maxOutputEndpoints
    }
  }

  public struct ApplyEndpointCommandParameters: Ocp1ParametersReflectable {
    public let id: OcaMediaStreamEndpointID
    public let command: OcaMediaStreamEndpointCommand

    public init(id: OcaMediaStreamEndpointID, command: OcaMediaStreamEndpointCommand) {
      self.id = id
      self.command = command
    }
  }

  public struct SetEndpointUserLabelParameters: Ocp1ParametersReflectable {
    public let id: OcaMediaStreamEndpointID
    public let userLabel: OcaString

    public init(id: OcaMediaStreamEndpointID, userLabel: OcaString) {
      self.id = id
      self.userLabel = userLabel
    }
  }

  public struct SetEndpointMediaStreamModeParameters: Ocp1ParametersReflectable {
    public let id: OcaMediaStreamEndpointID
    public let mediaStreamMode: OcaMediaStreamMode

    public init(id: OcaMediaStreamEndpointID, mediaStreamMode: OcaMediaStreamMode) {
      self.id = id
      self.mediaStreamMode = mediaStreamMode
    }
  }

  public struct SetEndpointChannelMapParameters: Ocp1ParametersReflectable {
    public let id: OcaMediaStreamEndpointID
    public let channelMap: OcaMultiMap<OcaUint16, OcaPortID>

    public init(id: OcaMediaStreamEndpointID, channelMap: OcaMultiMap<OcaUint16, OcaPortID>) {
      self.id = id
      self.channelMap = channelMap
    }
  }

  public struct SetEndpointAlignmentLevelParameters: Ocp1ParametersReflectable {
    public let id: OcaMediaStreamEndpointID
    public let alignmentLevel: OcaDBFS

    public init(id: OcaMediaStreamEndpointID, alignmentLevel: OcaDBFS) {
      self.id = id
      self.alignmentLevel = alignmentLevel
    }
  }

  public struct SetEndpointAdaptationDataParameters: Ocp1ParametersReflectable {
    public let id: OcaMediaStreamEndpointID
    public let adaptationData: OcaAdaptationData

    public init(id: OcaMediaStreamEndpointID, adaptationData: OcaAdaptationData) {
      self.id = id
      self.adaptationData = adaptationData
    }
  }

  public struct EndpointTimeSource: Ocp1ParametersReflectable, Equatable {
    public let referenceType: OcaTimeReferenceType
    public let referenceID: OcaString

    public init(referenceType: OcaTimeReferenceType, referenceID: OcaString) {
      self.referenceType = referenceType
      self.referenceID = referenceID
    }
  }

  public struct EndpointCounterParameters: Ocp1ParametersReflectable {
    public let endpointID: OcaMediaStreamEndpointID
    public let counterID: OcaID16

    public init(endpointID: OcaMediaStreamEndpointID, counterID: OcaID16) {
      self.endpointID = endpointID
      self.counterID = counterID
    }
  }

  public struct EndpointCounterNotifierParameters: Ocp1ParametersReflectable {
    public let endpointID: OcaMediaStreamEndpointID
    public let counterID: OcaID16
    public let oNo: OcaONo

    public init(endpointID: OcaMediaStreamEndpointID, counterID: OcaID16, oNo: OcaONo) {
      self.endpointID = endpointID
      self.counterID = counterID
      self.oNo = oNo
    }
  }

  // MARK: - Ports

  public func add(port label: OcaString, mode: OcaPortMode) async throws -> OcaPortID {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.1"),
      parameters: AddPortParameters(name: label, mode: mode)
    )
  }

  public func delete(port id: OcaPortID) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.2"),
      parameters: id,
      parameterNames: ["ID"]
    )
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.3"),
    ocp2Name: "OcaPorts"
  )
  public var ports: OcaListProperty<OcaPort>.PropertyValue

  public func getPortName(_ portID: OcaPortID) async throws -> OcaString {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.4"),
      parameters: OcaGetPortNameParameters(portID: portID)
    )
  }

  public func setPortName(_ portID: OcaPortID, name: OcaString) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.5"),
      parameters: OcaSetPortNameParameters(portID: portID, name: name)
    )
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.6"),
    setMethodID: OcaMethodID("3.7"),
    ocp2Name: "Map"
  )
  public var portClockMap: OcaMapProperty<OcaPortID, OcaPortClockMapEntry>.PropertyValue

  /// OcaMediaTransportApplication.SetPortClockMapEntry names its port `ID`, where
  /// OcaWorker says `PortID` (`OcaSetPortClockMapEntryParameters`).
  public struct SetPortClockMapEntryParameters: Ocp1ParametersReflectable {
    public let id: OcaPortID
    public let entry: OcaPortClockMapEntry

    public init(id: OcaPortID, entry: OcaPortClockMapEntry) {
      self.id = id
      self.entry = entry
    }
  }

  public func set(portID: OcaPortID, portClockMapEntry: OcaPortClockMapEntry) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.8"),
      parameters: SetPortClockMapEntryParameters(id: portID, entry: portClockMapEntry)
    )
  }

  public func deletePortClockMapEntry(portID: OcaPortID) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.9"),
      parameters: portID,
      parameterNames: ["ID"]
    )
  }

  public func get(portID: OcaPortID) async throws -> OcaPortClockMapEntry {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.10"),
      parameters: portID,
      parameterNames: ["ID"]
    )
  }

  // MARK: - Limits

  @OcaProperty(
    propertyID: OcaPropertyID("3.3")
  )
  public var maxInputEndpoints: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.4")
  )
  public var maxOutputEndpoints: OcaProperty<OcaUint16>.PropertyValue

  public func getMaxEndpointCounts() async throws -> MaxEndpointCounts {
    try await sendCommandRrq(methodID: OcaMethodID("3.11"))
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.5"),
    getMethodID: OcaMethodID("3.12"),
    ocp2Name: "Value"
  )
  public var maxPortsPerChannel: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.6"),
    getMethodID: OcaMethodID("3.13"),
    ocp2Name: "Value"
  )
  public var maxChannelsPerEndpoint: OcaProperty<OcaUint16>.PropertyValue

  // MARK: - Stream modes and timing

  @OcaProperty(
    propertyID: OcaPropertyID("3.7"),
    getMethodID: OcaMethodID("3.15"),
    setMethodID: OcaMethodID("3.16"),
    ocp2Name: "Capabilities"
  )
  public var mediaStreamModeCapabilities: OcaListProperty<OcaMediaStreamModeCapability>
    .PropertyValue

  public func getMediaStreamModeCapability(
    id: OcaID16
  ) async throws -> OcaMediaStreamModeCapability {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.17"),
      parameters: id,
      parameterNames: ["CapabilityID"]
    )
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.8"),
    getMethodID: OcaMethodID("3.18"),
    setMethodID: OcaMethodID("3.19"),
    ocp2Name: "Parameters"
  )
  public var transportTimingParameters: OcaProperty<OcaMediaTransportTimingParameters>
    .PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.9"),
    getMethodID: OcaMethodID("3.20"),
    setMethodID: OcaMethodID("3.14"),
    ocp2Name: "Limits"
  )
  public var alignmentLevelLimits: OcaProperty<OcaInterval<OcaDBFS>>.PropertyValue

  // MARK: - Endpoints

  @OcaProperty(
    propertyID: OcaPropertyID("3.10"),
    getMethodID: OcaMethodID("3.21")
  )
  public var endpoints: OcaListProperty<OcaMediaStreamEndpoint>.PropertyValue

  public func getEndpoint(_ id: OcaMediaStreamEndpointID) async throws -> OcaMediaStreamEndpoint {
    try await sendCommandRrq(methodID: OcaMethodID("3.22"), parameters: id, parameterNames: ["ID"])
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.11"),
    getMethodID: OcaMethodID("3.23"),
    ocp2Name: "Statuses"
  )
  public var endpointStatuses: OcaMapProperty<
    OcaMediaStreamEndpointID,
    OcaMediaStreamEndpointStatus
  >.PropertyValue

  public func getEndpointStatus(
    _ id: OcaMediaStreamEndpointID
  ) async throws -> OcaMediaStreamEndpointStatus {
    try await sendCommandRrq(methodID: OcaMethodID("3.24"), parameters: id, parameterNames: ["ID"])
  }

  /// Returns the given descriptor with its IDInternal set to the ID the device allocated.
  @discardableResult
  public func add(endpoint: OcaMediaStreamEndpoint) async throws -> OcaMediaStreamEndpoint {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.25"),
      parameters: endpoint,
      parameterNames: ["Endpoint"]
    )
  }

  public func delete(endpoint id: OcaMediaStreamEndpointID) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.26"), parameters: id, parameterNames: ["ID"])
  }

  public func applyEndpointCommand(
    _ id: OcaMediaStreamEndpointID,
    command: OcaMediaStreamEndpointCommand
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.27"),
      parameters: ApplyEndpointCommandParameters(id: id, command: command)
    )
  }

  public func setEndpoint(_ id: OcaMediaStreamEndpointID, userLabel: OcaString) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.28"),
      parameters: SetEndpointUserLabelParameters(id: id, userLabel: userLabel)
    )
  }

  public func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    mediaStreamMode: OcaMediaStreamMode
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.29"),
      parameters: SetEndpointMediaStreamModeParameters(id: id, mediaStreamMode: mediaStreamMode)
    )
  }

  public func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    channelMap: OcaMultiMap<OcaUint16, OcaPortID>
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.30"),
      parameters: SetEndpointChannelMapParameters(id: id, channelMap: channelMap)
    )
  }

  public func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    alignmentLevel: OcaDBFS
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.31"),
      parameters: SetEndpointAlignmentLevelParameters(id: id, alignmentLevel: alignmentLevel)
    )
  }

  public func getEndpointTimeSource(
    _ id: OcaMediaStreamEndpointID
  ) async throws -> EndpointTimeSource {
    try await sendCommandRrq(methodID: OcaMethodID("3.32"), parameters: id, parameterNames: ["ID"])
  }

  public func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    adaptationData: OcaAdaptationData
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.33"),
      parameters: SetEndpointAdaptationDataParameters(id: id, adaptationData: adaptationData)
    )
  }

  // MARK: - Endpoint counters

  @OcaProperty(
    propertyID: OcaPropertyID("3.12"),
    getMethodID: OcaMethodID("3.34"),
    ocp2Name: "Sets"
  )
  public var endpointCounterSets: OcaMapProperty<OcaID16, OcaCounterSet>.PropertyValue

  public func getEndpointCounterSet(_ id: OcaMediaStreamEndpointID) async throws -> OcaCounterSet {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.35"),
      parameters: id,
      parameterNames: ["EndpointID"]
    )
  }

  public func getEndpointCounter(
    _ id: OcaMediaStreamEndpointID,
    counterID: OcaID16
  ) async throws -> OcaCounter {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.36"),
      parameters: EndpointCounterParameters(endpointID: id, counterID: counterID)
    )
  }

  public func attachEndpointCounterNotifier(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16,
    oNo: OcaONo
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.37"),
      parameters: EndpointCounterNotifierParameters(
        endpointID: endpointID,
        counterID: counterID,
        oNo: oNo
      )
    )
  }

  public func detachEndpointCounterNotifier(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16,
    oNo: OcaONo
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.38"),
      parameters: EndpointCounterNotifierParameters(
        endpointID: endpointID,
        counterID: counterID,
        oNo: oNo
      )
    )
  }

  /// Resets one counter, or the whole counterset when `counterID` is zero.
  public func resetEndpointCounterSet(
    _ id: OcaMediaStreamEndpointID,
    counterID: OcaID16 = 0
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.39"),
      parameters: EndpointCounterParameters(endpointID: id, counterID: counterID)
    )
  }

  // MARK: - Session control agents

  @OcaProperty(
    propertyID: OcaPropertyID("3.13"),
    getMethodID: OcaMethodID("3.40"),
    setMethodID: OcaMethodID("3.41"),
    ocp2Name: "ONos"
  )
  public var transportSessionControlAgentONos: OcaListProperty<OcaONo>.PropertyValue
}
