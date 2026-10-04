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

open class OcaMediaTransportNetwork: OcaApplicationNetwork, @unchecked Sendable {
  override open class var classID: OcaClassID {
    OcaClassID("1.4.2")
  }

  override open class var classVersion: OcaClassVersionNumber {
    1
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var `protocol`: OcaProperty<OcaNetworkMediaProtocol>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.2"),
    ocp2GetName: "OcaPorts"
  )
  public var ports: OcaListProperty<OcaPort>.PropertyValue

  public static let getPortName = OcaMethodDescriptor<OcaGetPortNameParameters, OcaString>(
    "3.3",
    name: "GetPortName",
    resultNames: ["Name"]
  )

  public func get(portID: OcaPortID) async throws -> OcaString {
    try await invoke(Self.getPortName, .init(portID: portID))
  }

  public static let setPortName =
    OcaMethodDescriptor<OcaSetPortNameParameters, Void>("3.4", name: "SetPortName")

  public func set(portID: OcaPortID, name: OcaString) async throws {
    try await invoke(Self.setPortName, .init(portID: portID, name: name))
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.5")
  )
  public var maxSourceConnectors: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.4"),
    getMethodID: OcaMethodID("3.6")
  )
  public var maxSinkConnectors: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.5"),
    getMethodID: OcaMethodID("3.7"),
    ocp2GetName: "MaxPins"
  )
  public var maxPinsPerConnector: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.6"),
    getMethodID: OcaMethodID("3.8"),
    ocp2GetName: "MaxPins"
  )
  public var maxPortsPerPin: OcaProperty<OcaUint16>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("3.7"),
    getMethodID: OcaMethodID("3.25")
  )
  public var alignmentLevel: OcaBoundedProperty<OcaDBFS>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("3.8"),
    getMethodID: OcaMethodID("3.26")
  )
  public var alignmentGain: OcaBoundedProperty<OcaDB>.PropertyValue

  public static let getSourceConnectors = OcaMethodDescriptor<Void, [OcaMediaSourceConnector]>(
    "3.9",
    name: "GetSourceConnectors",
    resultNames: ["Connectors"]
  )

  public func getSourceConnectors() async throws -> [OcaMediaSourceConnector] {
    try await invoke(Self.getSourceConnectors)
  }

  public static let getSourceConnector =
    OcaMethodDescriptor<OcaMediaConnectorID, OcaMediaSourceConnector>(
      "3.10",
      name: "GetSourceConnector",
      parameterNames: ["ID"],
      resultNames: ["Connector"]
    )

  public func getSourceConnector(_ id: OcaMediaConnectorID) async throws
    -> OcaMediaSourceConnector
  {
    try await invoke(Self.getSourceConnector, id)
  }

  public static let getSinkConnectors = OcaMethodDescriptor<Void, [OcaMediaSinkConnector]>(
    "3.11",
    name: "GetSinkConnectors",
    resultNames: ["Connectors"]
  )

  public func getSinkConnectors() async throws -> [OcaMediaSinkConnector] {
    try await invoke(Self.getSinkConnectors)
  }

  public static let getSinkConnector =
    OcaMethodDescriptor<OcaMediaConnectorID, OcaMediaSinkConnector>(
      "3.12",
      name: "GetSinkConnector",
      parameterNames: ["ID"],
      resultNames: ["Connector"]
    )

  public func getSinkConnector(_ id: OcaMediaConnectorID) async throws -> OcaMediaSinkConnector {
    try await invoke(Self.getSinkConnector, id)
  }

  public static let getConnectorsStatuses = OcaMethodDescriptor<Void, [OcaMediaConnectorStatus]>(
    "3.13",
    name: "GetConnectorsStatuses",
    resultNames: ["Statuses"]
  )

  public func getConnectorsStatuses() async throws -> [OcaMediaConnectorStatus] {
    try await invoke(Self.getConnectorsStatuses)
  }

  public static let getConnectorStatus =
    OcaMethodDescriptor<OcaMediaConnectorID, OcaMediaConnectorStatus>(
      "3.14",
      name: "GetConnectorStatus",
      parameterNames: ["ConnectorID"],
      resultNames: ["Status"]
    )

  public func getConnectorStatus(_ id: OcaMediaConnectorID) async throws
    -> OcaMediaConnectorStatus
  {
    try await invoke(Self.getConnectorStatus, id)
  }

  public struct AddSourceConnectorParameters: OcaParametersReflectable {
    public var connector: OcaMediaSourceConnector
    public let initialStatus: OcaMediaConnectorState
  }

  public static let addSourceConnector =
    OcaMethodDescriptor<AddSourceConnectorParameters, OcaMediaSourceConnector>(
      "3.15",
      name: "AddSourceConnector",
      resultNames: ["Connector"]
    )

  public func addSource(
    connector: inout OcaMediaSourceConnector,
    initialStatus: OcaMediaConnectorState
  ) async throws {
    connector = try await invoke(
      Self.addSourceConnector,
      .init(connector: connector, initialStatus: initialStatus)
    )
  }

  public struct AddSinkConnectorParameters: OcaParametersReflectable {
    public let initialStatus: OcaMediaConnectorState
    public var connector: OcaMediaSinkConnector
  }

  public static let addSinkConnector =
    OcaMethodDescriptor<AddSinkConnectorParameters, OcaMediaSinkConnector>(
      "3.16",
      name: "AddSinkConnector",
      resultNames: ["Connector"]
    )

  public func addSink(
    initialStatus: OcaMediaConnectorState,
    connector: inout OcaMediaSinkConnector
  ) async throws {
    connector = try await invoke(
      Self.addSinkConnector,
      .init(initialStatus: initialStatus, connector: connector)
    )
  }

  public struct ControlConnectorParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let command: OcaMediaConnectorCommand
  }

  public static let controlConnector =
    OcaMethodDescriptor<ControlConnectorParameters, Void>("3.17", name: "ControlConnector")

  public func controlConnector(
    _ id: OcaMediaConnectorID,
    command: OcaMediaConnectorCommand
  ) async throws {
    try await invoke(Self.controlConnector, .init(connectorID: id, command: command))
  }

  public struct SetSourceConnectorPinMapParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let channelPinMap: [OcaUint16: OcaPortID]
  }

  public static let setSourceConnectorPinMap =
    OcaMethodDescriptor<SetSourceConnectorPinMapParameters, Void>(
      "3.18",
      name: "SetSourceConnectorPinMap"
    )

  public func setSourceConnector(
    _ id: OcaMediaConnectorID,
    pinMap: [OcaUint16: OcaPortID]
  ) async throws {
    try await invoke(Self.setSourceConnectorPinMap, .init(connectorID: id, channelPinMap: pinMap))
  }

  public struct SetSinkConnectorPinMapParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let channelPinMap: [OcaUint16: [OcaPortID]]
  }

  public static let setSinkConnectorPinMap =
    OcaMethodDescriptor<SetSinkConnectorPinMapParameters, Void>(
      "3.19",
      name: "SetSinkConnectorPinMap"
    )

  public func setSinkConnector(
    _ id: OcaMediaConnectorID,
    pinMap: [OcaUint16: [OcaPortID]]
  ) async throws {
    try await invoke(Self.setSinkConnectorPinMap, .init(connectorID: id, channelPinMap: pinMap))
  }

  public struct SetConnectorConnectionParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let connection: OcaMediaConnection
  }

  public static let setConnectorConnection =
    OcaMethodDescriptor<SetConnectorConnectionParameters, Void>(
      "3.20",
      name: "SetConnectorConnection"
    )

  public func setConnector(
    _ id: OcaMediaConnectorID,
    connection: OcaMediaConnection
  ) async throws {
    try await invoke(Self.setConnectorConnection, .init(connectorID: id, connection: connection))
  }

  public struct SetConnectorCodingParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let coding: OcaMediaCoding
  }

  public static let setConnectorCoding =
    OcaMethodDescriptor<SetConnectorCodingParameters, Void>("3.21", name: "SetConnectorCoding")

  public func setConnector(_ id: OcaMediaConnectorID, coding: OcaMediaCoding) async throws {
    try await invoke(Self.setConnectorCoding, .init(connectorID: id, coding: coding))
  }

  public struct SetConnectorAlignmentLevelParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let level: OcaDBFS
  }

  public static let setConnectorAlignmentLevel =
    OcaMethodDescriptor<SetConnectorAlignmentLevelParameters, Void>(
      "3.22",
      name: "SetConnectorAlignmentLevel"
    )

  public func setConnector(_ id: OcaMediaConnectorID, alignmentLevel: OcaDBFS) async throws {
    try await invoke(Self.setConnectorAlignmentLevel, .init(connectorID: id, level: alignmentLevel))
  }

  public struct SetConnectorAlignmentGainParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let gain: OcaDB
  }

  public static let setConnectorAlignmentGain =
    OcaMethodDescriptor<SetConnectorAlignmentGainParameters, Void>(
      "3.23",
      name: "SetConnectorAlignmentGain"
    )

  public func setConnector(_ id: OcaMediaConnectorID, alignmentGain: OcaDB) async throws {
    try await invoke(Self.setConnectorAlignmentGain, .init(connectorID: id, gain: alignmentGain))
  }

  public static let deleteConnector = OcaMethodDescriptor<OcaMediaConnectorID, Void>(
    "3.24",
    name: "DeleteConnector",
    parameterNames: ["ID"]
  )

  public func deleteConnector(_ id: OcaMediaConnectorID) async throws {
    try await invoke(Self.deleteConnector, id)
  }
}
