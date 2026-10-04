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

  /// AddEndpoint carries the descriptor, returned with its ID filled in, and the state the
  /// new endpoint starts in.
  public struct AddEndpointParameters: OcaParametersReflectable {
    public var endpoint: OcaMediaStreamEndpoint
    public let initialStatus: OcaMediaStreamEndpointState

    public init(endpoint: OcaMediaStreamEndpoint, initialStatus: OcaMediaStreamEndpointState) {
      self.endpoint = endpoint
      self.initialStatus = initialStatus
    }
  }

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

  public static let addPort =
    OcaMethodDescriptor<AddPortParameters, OcaPortID>("3.1", name: "AddPort", resultNames: ["ID"])

  public func add(port label: OcaString, mode: OcaPortMode) async throws -> OcaPortID {
    try await invoke(Self.addPort, .init(name: label, mode: mode))
  }

  public static let deletePort =
    OcaMethodDescriptor<OcaPortID, Void>("3.2", name: "DeletePort", parameterNames: ["ID"])

  public func delete(port id: OcaPortID) async throws {
    try await invoke(Self.deletePort, id)
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.3"),
    ocp2GetName: "OcaPorts"
  )
  public var ports: OcaListProperty<OcaPort>.PropertyValue

  public static let getPortName = OcaMethodDescriptor<OcaGetPortNameParameters, OcaString>(
    "3.4",
    name: "GetPortName",
    resultNames: ["Name"]
  )

  public func getPortName(_ portID: OcaPortID) async throws -> OcaString {
    try await invoke(Self.getPortName, .init(portID: portID))
  }

  public static let setPortName =
    OcaMethodDescriptor<OcaSetPortNameParameters, Void>("3.5", name: "SetPortName")

  public func setPortName(_ portID: OcaPortID, name: OcaString) async throws {
    try await invoke(Self.setPortName, .init(portID: portID, name: name))
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

  // the device takes OcaWorker's record for this one, so the descriptor names its port
  public static let setPortClockMapEntry =
    OcaMethodDescriptor<OcaSetPortClockMapEntryParameters, Void>(
      "3.8",
      name: "SetPortClockMapEntry",
      parameterNames: ["ID", "Entry"]
    )

  public func set(portID: OcaPortID, portClockMapEntry: OcaPortClockMapEntry) async throws {
    try await invoke(Self.setPortClockMapEntry, .init(portID: portID, entry: portClockMapEntry))
  }

  public static let deletePortClockMapEntry = OcaMethodDescriptor<OcaPortID, Void>(
    "3.9",
    name: "DeletePortClockMapEntry",
    parameterNames: ["ID"]
  )

  public func deletePortClockMapEntry(portID: OcaPortID) async throws {
    try await invoke(Self.deletePortClockMapEntry, portID)
  }

  public static let getPortClockMapEntry = OcaMethodDescriptor<OcaPortID, OcaPortClockMapEntry>(
    "3.10",
    name: "GetPortClockMapEntry",
    parameterNames: ["ID"],
    resultNames: ["Entry"]
  )

  public func get(portID: OcaPortID) async throws -> OcaPortClockMapEntry {
    try await invoke(Self.getPortClockMapEntry, portID)
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

  public static let getMaxEndpointCounts =
    OcaMethodDescriptor<Void, MaxEndpointCounts>("3.11", name: "GetMaxEndpointCounts")

  public func getMaxEndpointCounts() async throws -> MaxEndpointCounts {
    try await invoke(Self.getMaxEndpointCounts)
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

  public static let getMediaStreamModeCapability =
    OcaMethodDescriptor<OcaID16, OcaMediaStreamModeCapability>(
      "3.17",
      name: "GetMediaStreamModeCapability",
      parameterNames: ["CapabilityID"],
      resultNames: ["Capability"]
    )

  public func getMediaStreamModeCapability(
    id: OcaID16
  ) async throws -> OcaMediaStreamModeCapability {
    try await invoke(Self.getMediaStreamModeCapability, id)
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

  public static let getEndpoint =
    OcaMethodDescriptor<OcaMediaStreamEndpointID, OcaMediaStreamEndpoint>(
      "3.22",
      name: "GetEndpoint",
      parameterNames: ["ID"],
      resultNames: ["Endpoint"]
    )

  public func getEndpoint(_ id: OcaMediaStreamEndpointID) async throws -> OcaMediaStreamEndpoint {
    try await invoke(Self.getEndpoint, id)
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

  public static let getEndpointStatus =
    OcaMethodDescriptor<OcaMediaStreamEndpointID, OcaMediaStreamEndpointStatus>(
      "3.24",
      name: "GetEndpointStatus",
      parameterNames: ["ID"],
      resultNames: ["Status"]
    )

  public func getEndpointStatus(
    _ id: OcaMediaStreamEndpointID
  ) async throws -> OcaMediaStreamEndpointStatus {
    try await invoke(Self.getEndpointStatus, id)
  }

  public static let addEndpoint =
    OcaMethodDescriptor<AddEndpointParameters, OcaMediaStreamEndpoint>(
      "3.25",
      name: "AddEndpoint",
      resultNames: ["Endpoint"]
    )

  /// Returns the given descriptor with its IDInternal set to the ID the device allocated.
  @discardableResult
  public func add(
    endpoint: OcaMediaStreamEndpoint,
    initialStatus: OcaMediaStreamEndpointState
  ) async throws -> OcaMediaStreamEndpoint {
    try await invoke(Self.addEndpoint, .init(endpoint: endpoint, initialStatus: initialStatus))
  }

  public static let deleteEndpoint = OcaMethodDescriptor<OcaMediaStreamEndpointID, Void>(
    "3.26",
    name: "DeleteEndpoint",
    parameterNames: ["ID"]
  )

  public func delete(endpoint id: OcaMediaStreamEndpointID) async throws {
    try await invoke(Self.deleteEndpoint, id)
  }

  public static let applyEndpointCommand =
    OcaMethodDescriptor<ApplyEndpointCommandParameters, Void>("3.27", name: "ApplyEndpointCommand")

  public func applyEndpointCommand(
    _ id: OcaMediaStreamEndpointID,
    command: OcaMediaStreamEndpointCommand
  ) async throws {
    try await invoke(Self.applyEndpointCommand, .init(endpointID: id, command: command))
  }

  public static let setEndpointUserLabel =
    OcaMethodDescriptor<SetEndpointUserLabelParameters, Void>("3.28", name: "SetEndpointUserLabel")

  public func setEndpoint(_ id: OcaMediaStreamEndpointID, userLabel: OcaString) async throws {
    try await invoke(Self.setEndpointUserLabel, .init(endpointID: id, label: userLabel))
  }

  public static let setEndpointMediaStreamMode =
    OcaMethodDescriptor<SetEndpointMediaStreamModeParameters, Void>(
      "3.29",
      name: "SetEndpointMediaStreamMode"
    )

  public func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    mediaStreamMode: OcaMediaStreamMode
  ) async throws {
    try await invoke(
      Self.setEndpointMediaStreamMode,
      .init(endpointID: id, streamMode: mediaStreamMode)
    )
  }

  public static let setEndpointChannelMap =
    OcaMethodDescriptor<SetEndpointChannelMapParameters, Void>(
      "3.30",
      name: "SetEndpointChannelMap"
    )

  public func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    channelMap: OcaMultiMap<OcaUint16, OcaPortID>
  ) async throws {
    try await invoke(Self.setEndpointChannelMap, .init(endpointID: id, channelMap: channelMap))
  }

  public static let setEndpointAlignmentLevel =
    OcaMethodDescriptor<SetEndpointAlignmentLevelParameters, Void>(
      "3.31",
      name: "SetEndpointAlignmentLevel"
    )

  public func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    alignmentLevel: OcaDBFS
  ) async throws {
    try await invoke(Self.setEndpointAlignmentLevel, .init(endpointID: id, level: alignmentLevel))
  }

  public static let getEndpointTimeSource =
    OcaMethodDescriptor<OcaMediaStreamEndpointID, EndpointTimeSource>(
      "3.32",
      name: "GetEndpointTimeSource",
      parameterNames: ["ID"]
    )

  public func getEndpointTimeSource(
    _ id: OcaMediaStreamEndpointID
  ) async throws -> EndpointTimeSource {
    try await invoke(Self.getEndpointTimeSource, id)
  }

  public static let setEndpointAdaptationData =
    OcaMethodDescriptor<SetEndpointAdaptationDataParameters, Void>(
      "3.33",
      name: "SetEndpointAdaptationData"
    )

  public func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    adaptationData: OcaAdaptationData
  ) async throws {
    try await invoke(Self.setEndpointAdaptationData, .init(endpointID: id, data: adaptationData))
  }

  // MARK: - Endpoint counters

  @OcaProperty(
    propertyID: OcaPropertyID("3.12"),
    getMethodID: OcaMethodID("3.34"),
    ocp2GetName: "Sets"
  )
  public var endpointCounterSets: OcaMapProperty<OcaID16, OcaCounterSet>.PropertyValue

  public static let getEndpointCounterSet =
    OcaMethodDescriptor<OcaMediaStreamEndpointID, OcaCounterSet>(
      "3.35",
      name: "GetEndpointCounterSet",
      parameterNames: ["EndpointID"],
      resultNames: ["CounterSet"]
    )

  public func getEndpointCounterSet(_ id: OcaMediaStreamEndpointID) async throws -> OcaCounterSet {
    try await invoke(Self.getEndpointCounterSet, id)
  }

  public static let getEndpointCounter =
    OcaMethodDescriptor<EndpointCounterParameters, OcaCounter>(
      "3.36",
      name: "GetEndpointCounter",
      resultNames: ["Counter"]
    )

  public func getEndpointCounter(
    _ id: OcaMediaStreamEndpointID,
    counterID: OcaID16
  ) async throws -> OcaCounter {
    try await invoke(Self.getEndpointCounter, .init(endpointID: id, counterID: counterID))
  }

  public static let attachEndpointCounterNotifier =
    OcaMethodDescriptor<EndpointCounterNotifierParameters, Void>(
      "3.37",
      name: "AttachEndpointCounterNotifier"
    )

  public func attachEndpointCounterNotifier(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16,
    oNo: OcaONo
  ) async throws {
    try await invoke(
      Self.attachEndpointCounterNotifier,
      .init(endpointID: endpointID, counterID: counterID, notifierONo: oNo)
    )
  }

  public static let detachEndpointCounterNotifier =
    OcaMethodDescriptor<EndpointCounterNotifierParameters, Void>(
      "3.38",
      name: "DetachEndpointCounterNotifier"
    )

  public func detachEndpointCounterNotifier(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16,
    oNo: OcaONo
  ) async throws {
    try await invoke(
      Self.detachEndpointCounterNotifier,
      .init(endpointID: endpointID, counterID: counterID, notifierONo: oNo)
    )
  }

  public static let resetEndpointCounterSet =
    OcaMethodDescriptor<EndpointCounterParameters, Void>("3.39", name: "ResetEndpointCounterSet")

  /// Resets one counter, or the whole counterset when `counterID` is zero.
  public func resetEndpointCounterSet(
    _ id: OcaMediaStreamEndpointID,
    counterID: OcaID16 = 0
  ) async throws {
    try await invoke(Self.resetEndpointCounterSet, .init(endpointID: id, counterID: counterID))
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
