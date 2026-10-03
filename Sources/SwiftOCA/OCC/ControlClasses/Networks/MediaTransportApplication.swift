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
  public struct AddPortParameters: OcaParametersReflectable {
    public let name: OcaString
    public let mode: OcaPortMode

    public init(name: OcaString, mode: OcaPortMode) {
      self.name = name
      self.mode = mode
    }
  }

  /// GetMaxEndpointCounts returns the output count first, in the model's order.
  public struct MaxEndpointCounts: OcaParametersReflectable, Equatable {
    public let maxOutputCount: OcaUint16
    public let maxInputCount: OcaUint16

    public init(maxOutputCount: OcaUint16, maxInputCount: OcaUint16) {
      self.maxOutputCount = maxOutputCount
      self.maxInputCount = maxInputCount
    }
  }

  // The field names are the model's parameter names: OCP.2 derives the wire names from them.

  public struct ApplyEndpointCommandParameters: OcaParametersReflectable {
    public let endpointID: OcaMediaStreamEndpointID
    public let command: OcaMediaStreamEndpointCommand

    public init(endpointID: OcaMediaStreamEndpointID, command: OcaMediaStreamEndpointCommand) {
      self.endpointID = endpointID
      self.command = command
    }
  }

  public struct SetEndpointUserLabelParameters: OcaParametersReflectable {
    public let endpointID: OcaMediaStreamEndpointID
    public let label: OcaString

    public init(endpointID: OcaMediaStreamEndpointID, label: OcaString) {
      self.endpointID = endpointID
      self.label = label
    }
  }

  public struct SetEndpointMediaStreamModeParameters: OcaParametersReflectable {
    public let endpointID: OcaMediaStreamEndpointID
    public let streamMode: OcaMediaStreamMode

    public init(endpointID: OcaMediaStreamEndpointID, streamMode: OcaMediaStreamMode) {
      self.endpointID = endpointID
      self.streamMode = streamMode
    }
  }

  public struct SetEndpointChannelMapParameters: OcaParametersReflectable {
    public let endpointID: OcaMediaStreamEndpointID
    public let channelMap: OcaMultiMap<OcaUint16, OcaPortID>

    public init(
      endpointID: OcaMediaStreamEndpointID,
      channelMap: OcaMultiMap<OcaUint16, OcaPortID>
    ) {
      self.endpointID = endpointID
      self.channelMap = channelMap
    }
  }

  public struct SetEndpointAlignmentLevelParameters: OcaParametersReflectable {
    public let endpointID: OcaMediaStreamEndpointID
    public let level: OcaDBFS

    public init(endpointID: OcaMediaStreamEndpointID, level: OcaDBFS) {
      self.endpointID = endpointID
      self.level = level
    }
  }

  public struct SetEndpointAdaptationDataParameters: OcaParametersReflectable {
    public let endpointID: OcaMediaStreamEndpointID
    public let data: OcaAdaptationData

    public init(endpointID: OcaMediaStreamEndpointID, data: OcaAdaptationData) {
      self.endpointID = endpointID
      self.data = data
    }
  }

  public struct EndpointTimeSource: OcaParametersReflectable, Equatable {
    public let referenceType: OcaTimeReferenceType
    public let referenceID: OcaString

    public init(referenceType: OcaTimeReferenceType, referenceID: OcaString) {
      self.referenceType = referenceType
      self.referenceID = referenceID
    }
  }

  public struct EndpointCounterParameters: OcaParametersReflectable {
    public let endpointID: OcaMediaStreamEndpointID
    public let counterID: OcaID16

    public init(endpointID: OcaMediaStreamEndpointID, counterID: OcaID16) {
      self.endpointID = endpointID
      self.counterID = counterID
    }
  }

  public struct EndpointCounterNotifierParameters: OcaParametersReflectable {
    public let endpointID: OcaMediaStreamEndpointID
    public let counterID: OcaID16
    public let notifierONo: OcaONo

    public init(endpointID: OcaMediaStreamEndpointID, counterID: OcaID16, notifierONo: OcaONo) {
      self.endpointID = endpointID
      self.counterID = counterID
      self.notifierONo = notifierONo
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
    ocp2GetName: "OcaPorts"
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
    ocp2GetName: "Map",
    ocp2SetName: "Map"
  )
  public var portClockMap: OcaMapProperty<OcaPortID, OcaPortClockMapEntry>.PropertyValue

  /// OcaMediaTransportApplication.SetPortClockMapEntry names its port `ID`, where
  /// OcaWorker says `PortID` (`OcaSetPortClockMapEntryParameters`).
  public struct SetPortClockMapEntryParameters: OcaParametersReflectable {
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
    ocp2GetName: "Value"
  )
  public var maxPortsPerChannel: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.6"),
    getMethodID: OcaMethodID("3.13"),
    ocp2GetName: "Value"
  )
  public var maxChannelsPerEndpoint: OcaProperty<OcaUint16>.PropertyValue

  // MARK: - Stream modes and timing

  @OcaProperty(
    propertyID: OcaPropertyID("3.7"),
    getMethodID: OcaMethodID("3.15"),
    setMethodID: OcaMethodID("3.16"),
    ocp2GetName: "Capabilities",
    ocp2SetName: "Capabilities"
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
    ocp2GetName: "Parameters",
    ocp2SetName: "Parameters"
  )
  public var transportTimingParameters: OcaProperty<OcaMediaTransportTimingParameters>
    .PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.9"),
    getMethodID: OcaMethodID("3.20"),
    setMethodID: OcaMethodID("3.14"),
    ocp2GetName: "Limits",
    ocp2SetName: "Limits"
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
    ocp2GetName: "Statuses"
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
      parameters: ApplyEndpointCommandParameters(endpointID: id, command: command)
    )
  }

  public func setEndpoint(_ id: OcaMediaStreamEndpointID, userLabel: OcaString) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.28"),
      parameters: SetEndpointUserLabelParameters(endpointID: id, label: userLabel)
    )
  }

  public func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    mediaStreamMode: OcaMediaStreamMode
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.29"),
      parameters: SetEndpointMediaStreamModeParameters(endpointID: id, streamMode: mediaStreamMode)
    )
  }

  public func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    channelMap: OcaMultiMap<OcaUint16, OcaPortID>
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.30"),
      parameters: SetEndpointChannelMapParameters(endpointID: id, channelMap: channelMap)
    )
  }

  public func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    alignmentLevel: OcaDBFS
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.31"),
      parameters: SetEndpointAlignmentLevelParameters(endpointID: id, level: alignmentLevel)
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
      parameters: SetEndpointAdaptationDataParameters(endpointID: id, data: adaptationData)
    )
  }

  // MARK: - Endpoint counters

  @OcaProperty(
    propertyID: OcaPropertyID("3.12"),
    getMethodID: OcaMethodID("3.34"),
    ocp2GetName: "Sets"
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
        notifierONo: oNo
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
        notifierONo: oNo
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
    ocp2GetName: "ONos",
    ocp2SetName: "ONos"
  )
  public var transportSessionControlAgentONos: OcaListProperty<OcaONo>.PropertyValue
}
