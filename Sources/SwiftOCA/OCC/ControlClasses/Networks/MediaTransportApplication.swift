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

  @OcaMethod("3.1", name: "AddPort", parameters: AddPortParameters.self, resultNames: ["ID"])
  public func addPort(name: OcaString, mode: OcaPortMode) async throws -> OcaPortID

  @OcaMethod("3.2", name: "DeletePort", parameterNames: ["ID"])
  public func deletePort(id: OcaPortID) async throws

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.3"),
    ocp2GetName: "OcaPorts"
  )
  public var ports: OcaListProperty<OcaPort>.PropertyValue

  @OcaMethod("3.4", name: "GetPortName", parameterNames: ["PortID"], resultNames: ["Name"])
  public func getPortName(portID: OcaPortID) async throws -> OcaString

  @OcaMethod("3.5", name: "SetPortName", parameters: OcaSetPortNameParameters.self)
  public func setPortName(portID: OcaPortID, name: OcaString) async throws

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

  @OcaMethod(
    "3.8",
    name: "SetPortClockMapEntry",
    parameters: SetPortClockMapEntryParameters.self,
    parameterNames: ["ID", "Entry"]
  )
  public func setPortClockMapEntry(id: OcaPortID, entry: OcaPortClockMapEntry) async throws

  @OcaMethod("3.9", name: "DeletePortClockMapEntry", parameterNames: ["ID"])
  public func deletePortClockMapEntry(id: OcaPortID) async throws

  @OcaMethod("3.10", name: "GetPortClockMapEntry", parameterNames: ["ID"], resultNames: ["Entry"])
  public func getPortClockMapEntry(id: OcaPortID) async throws -> OcaPortClockMapEntry

  // MARK: - Limits

  @OcaProperty(
    propertyID: OcaPropertyID("3.3")
  )
  public var maxInputEndpoints: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.4")
  )
  public var maxOutputEndpoints: OcaProperty<OcaUint16>.PropertyValue

  @OcaMethod("3.11", name: "GetMaxEndpointCounts")
  public func getMaxEndpointCounts() async throws -> MaxEndpointCounts

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

  @OcaMethod(
    "3.17",
    name: "GetMediaStreamModeCapability",
    parameterNames: ["CapabilityID"],
    resultNames: ["Capability"]
  )
  public func getMediaStreamModeCapability(
    capabilityID: OcaID16
  ) async throws -> OcaMediaStreamModeCapability

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

  @OcaMethod("3.22", name: "GetEndpoint", parameterNames: ["ID"], resultNames: ["Endpoint"])
  public func getEndpoint(id: OcaMediaStreamEndpointID) async throws -> OcaMediaStreamEndpoint

  @OcaProperty(
    propertyID: OcaPropertyID("3.11"),
    getMethodID: OcaMethodID("3.23"),
    ocp2GetName: "Statuses"
  )
  public var endpointStatuses: OcaMapProperty<
    OcaMediaStreamEndpointID,
    OcaMediaStreamEndpointStatus
  >.PropertyValue

  @OcaMethod("3.24", name: "GetEndpointStatus", parameterNames: ["ID"], resultNames: ["Status"])
  public func getEndpointStatus(
    id: OcaMediaStreamEndpointID
  ) async throws -> OcaMediaStreamEndpointStatus

  /// Returns the given descriptor with its IDInternal set to the ID the device allocated.
  @OcaMethod(
    "3.25",
    name: "AddEndpoint",
    parameters: AddEndpointParameters.self,
    resultNames: ["Endpoint"]
  )
  @discardableResult
  public func addEndpoint(
    endpoint: OcaMediaStreamEndpoint,
    initialStatus: OcaMediaStreamEndpointState
  ) async throws -> OcaMediaStreamEndpoint

  @OcaMethod("3.26", name: "DeleteEndpoint", parameterNames: ["ID"])
  public func deleteEndpoint(id: OcaMediaStreamEndpointID) async throws

  @OcaMethod("3.27", name: "ApplyEndpointCommand", parameters: ApplyEndpointCommandParameters.self)
  public func applyEndpointCommand(
    endpointID: OcaMediaStreamEndpointID,
    command: OcaMediaStreamEndpointCommand
  ) async throws

  @OcaMethod("3.28", name: "SetEndpointUserLabel", parameters: SetEndpointUserLabelParameters.self)
  public func setEndpointUserLabel(
    endpointID: OcaMediaStreamEndpointID,
    label: OcaString
  ) async throws

  @OcaMethod(
    "3.29",
    name: "SetEndpointMediaStreamMode",
    parameters: SetEndpointMediaStreamModeParameters.self
  )
  public func setEndpointMediaStreamMode(
    endpointID: OcaMediaStreamEndpointID,
    streamMode: OcaMediaStreamMode
  ) async throws

  @OcaMethod(
    "3.30",
    name: "SetEndpointChannelMap",
    parameters: SetEndpointChannelMapParameters.self
  )
  public func setEndpointChannelMap(
    endpointID: OcaMediaStreamEndpointID,
    channelMap: OcaMultiMap<OcaUint16, OcaPortID>
  ) async throws

  @OcaMethod(
    "3.31",
    name: "SetEndpointAlignmentLevel",
    parameters: SetEndpointAlignmentLevelParameters.self
  )
  public func setEndpointAlignmentLevel(
    endpointID: OcaMediaStreamEndpointID,
    level: OcaDBFS
  ) async throws

  @OcaMethod("3.32", name: "GetEndpointTimeSource", parameterNames: ["ID"])
  public func getEndpointTimeSource(
    id: OcaMediaStreamEndpointID
  ) async throws -> EndpointTimeSource

  @OcaMethod(
    "3.33",
    name: "SetEndpointAdaptationData",
    parameters: SetEndpointAdaptationDataParameters.self
  )
  public func setEndpointAdaptationData(
    endpointID: OcaMediaStreamEndpointID,
    data: OcaAdaptationData
  ) async throws

  // MARK: - Endpoint counters

  @OcaProperty(
    propertyID: OcaPropertyID("3.12"),
    getMethodID: OcaMethodID("3.34"),
    ocp2GetName: "Sets"
  )
  public var endpointCounterSets: OcaMapProperty<OcaID16, OcaCounterSet>.PropertyValue

  @OcaMethod(
    "3.35",
    name: "GetEndpointCounterSet",
    parameterNames: ["EndpointID"],
    resultNames: ["CounterSet"]
  )
  public func getEndpointCounterSet(
    endpointID: OcaMediaStreamEndpointID
  ) async throws -> OcaCounterSet

  @OcaMethod(
    "3.36",
    name: "GetEndpointCounter",
    parameters: EndpointCounterParameters.self,
    resultNames: ["Counter"]
  )
  public func getEndpointCounter(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16
  ) async throws -> OcaCounter

  @OcaMethod(
    "3.37",
    name: "AttachEndpointCounterNotifier",
    parameters: EndpointCounterNotifierParameters.self
  )
  public func attachEndpointCounterNotifier(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16,
    notifierONo: OcaONo
  ) async throws

  @OcaMethod(
    "3.38",
    name: "DetachEndpointCounterNotifier",
    parameters: EndpointCounterNotifierParameters.self
  )
  public func detachEndpointCounterNotifier(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16,
    notifierONo: OcaONo
  ) async throws

  /// Resets one counter, or the whole counterset when `counterID` is zero.
  @OcaMethod("3.39", name: "ResetEndpointCounterSet", parameters: EndpointCounterParameters.self)
  public func resetEndpointCounterSet(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16 = 0
  ) async throws

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
