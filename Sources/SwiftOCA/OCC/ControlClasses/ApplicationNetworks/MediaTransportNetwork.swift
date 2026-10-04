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

@OcaMethods
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

  @OcaMethod("3.3", name: "GetPortName", parameterNames: ["PortID"], resultNames: ["Name"])
  public func getPortName(portID: OcaPortID) async throws -> OcaString

  @OcaMethod("3.4", name: "SetPortName", parameters: OcaSetPortNameParameters.self)
  public func setPortName(portID: OcaPortID, name: OcaString) async throws

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

  @OcaMethod("3.9", name: "GetSourceConnectors", resultNames: ["Connectors"])
  public func getSourceConnectors() async throws -> [OcaMediaSourceConnector]

  @OcaMethod("3.10", name: "GetSourceConnector", parameterNames: ["ID"], resultNames: ["Connector"])
  public func getSourceConnector(id: OcaMediaConnectorID) async throws
    -> OcaMediaSourceConnector


  @OcaMethod("3.11", name: "GetSinkConnectors", resultNames: ["Connectors"])
  public func getSinkConnectors() async throws -> [OcaMediaSinkConnector]

  @OcaMethod("3.12", name: "GetSinkConnector", parameterNames: ["ID"], resultNames: ["Connector"])
  public func getSinkConnector(id: OcaMediaConnectorID) async throws -> OcaMediaSinkConnector

  @OcaMethod("3.13", name: "GetConnectorsStatuses", resultNames: ["Statuses"])
  public func getConnectorsStatuses() async throws -> [OcaMediaConnectorStatus]

  @OcaMethod(
    "3.14",
    name: "GetConnectorStatus",
    parameterNames: ["ConnectorID"],
    resultNames: ["Status"]
  )
  public func getConnectorStatus(connectorID: OcaMediaConnectorID) async throws
    -> OcaMediaConnectorStatus


  public struct AddSourceConnectorParameters: OcaParametersReflectable {
    public var connector: OcaMediaSourceConnector
    public let initialStatus: OcaMediaConnectorState
  }

  @OcaMethod(
    "3.15",
    name: "AddSourceConnector",
    parameters: AddSourceConnectorParameters.self,
    resultNames: ["Connector"]
  )
  public func addSourceConnector(
    connector: OcaMediaSourceConnector,
    initialStatus: OcaMediaConnectorState
  ) async throws -> OcaMediaSourceConnector

  public struct AddSinkConnectorParameters: OcaParametersReflectable {
    public let initialStatus: OcaMediaConnectorState
    public var connector: OcaMediaSinkConnector
  }

  @OcaMethod(
    "3.16",
    name: "AddSinkConnector",
    parameters: AddSinkConnectorParameters.self,
    resultNames: ["Connector"]
  )
  public func addSinkConnector(
    initialStatus: OcaMediaConnectorState,
    connector: OcaMediaSinkConnector
  ) async throws -> OcaMediaSinkConnector

  public struct ControlConnectorParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let command: OcaMediaConnectorCommand
  }

  @OcaMethod("3.17", name: "ControlConnector", parameters: ControlConnectorParameters.self)
  public func controlConnector(
    connectorID: OcaMediaConnectorID,
    command: OcaMediaConnectorCommand
  ) async throws

  public struct SetSourceConnectorPinMapParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let channelPinMap: [OcaUint16: OcaPortID]
  }

  @OcaMethod(
    "3.18",
    name: "SetSourceConnectorPinMap",
    parameters: SetSourceConnectorPinMapParameters.self
  )
  public func setSourceConnectorPinMap(
    connectorID: OcaMediaConnectorID,
    channelPinMap: [OcaUint16: OcaPortID]
  ) async throws

  public struct SetSinkConnectorPinMapParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let channelPinMap: [OcaUint16: [OcaPortID]]
  }

  @OcaMethod(
    "3.19",
    name: "SetSinkConnectorPinMap",
    parameters: SetSinkConnectorPinMapParameters.self
  )
  public func setSinkConnectorPinMap(
    connectorID: OcaMediaConnectorID,
    channelPinMap: [OcaUint16: [OcaPortID]]
  ) async throws

  public struct SetConnectorConnectionParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let connection: OcaMediaConnection
  }

  @OcaMethod(
    "3.20",
    name: "SetConnectorConnection",
    parameters: SetConnectorConnectionParameters.self
  )
  public func setConnectorConnection(
    connectorID: OcaMediaConnectorID,
    connection: OcaMediaConnection
  ) async throws

  public struct SetConnectorCodingParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let coding: OcaMediaCoding
  }

  @OcaMethod("3.21", name: "SetConnectorCoding", parameters: SetConnectorCodingParameters.self)
  public func setConnectorCoding(
    connectorID: OcaMediaConnectorID,
    coding: OcaMediaCoding
  ) async throws

  public struct SetConnectorAlignmentLevelParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let level: OcaDBFS
  }

  @OcaMethod(
    "3.22",
    name: "SetConnectorAlignmentLevel",
    parameters: SetConnectorAlignmentLevelParameters.self
  )
  public func setConnectorAlignmentLevel(
    connectorID: OcaMediaConnectorID,
    level: OcaDBFS
  ) async throws

  public struct SetConnectorAlignmentGainParameters: OcaParametersReflectable {
    public let connectorID: OcaMediaConnectorID
    public let gain: OcaDB
  }

  @OcaMethod(
    "3.23",
    name: "SetConnectorAlignmentGain",
    parameters: SetConnectorAlignmentGainParameters.self
  )
  public func setConnectorAlignmentGain(
    connectorID: OcaMediaConnectorID,
    gain: OcaDB
  ) async throws

  @OcaMethod("3.24", name: "DeleteConnector", parameterNames: ["ID"])
  public func deleteConnector(id: OcaMediaConnectorID) async throws
}
