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

import SwiftOCA

@OcaDeviceMethods
open class OcaMediaTransportNetwork: OcaApplicationNetwork, OcaPortsRepresentable {
  override open class var classID: OcaClassID {
    OcaClassID("1.4.2")
  }

  override open class var classVersion: OcaClassVersionNumber {
    1
  }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var `protocol`: OcaNetworkMediaProtocol = .none

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.2"),
    ocp2GetName: "OcaPorts"
  )
  public var ports = [OcaPort]()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.5")
  )
  public var maxSourceConnectors: OcaUint16 = 0

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.4"),
    getMethodID: OcaMethodID("3.6")
  )
  public var maxSinkConnectors: OcaUint16 = 0

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.5"),
    getMethodID: OcaMethodID("3.7"),
    ocp2GetName: "MaxPins"
  )
  public var maxPinsPerConnector: OcaUint16 = 0

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.6"),
    getMethodID: OcaMethodID("3.8"),
    ocp2GetName: "MaxPins"
  )
  public var maxPortsPerPin: OcaUint16 = 0

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("3.7"),
    getMethodID: OcaMethodID("3.25")
  )
  public var alignmentLevel = OcaBoundedPropertyValue<OcaDBFS>(value: -20.0, in: -20.0 ... -20.0)

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("3.8"),
    getMethodID: OcaMethodID("3.26")
  )
  public var alignmentGain = OcaBoundedPropertyValue<OcaDB>(value: 0.0, in: -0.0...0.0)

  open func getSourceConnectors() async throws -> [OcaMediaSourceConnector] {
    []
  }

  open func getSourceConnector(_ id: OcaMediaConnectorID) async throws
    -> OcaMediaSourceConnector
  {
    throw Ocp1Error.status(.notImplemented)
  }

  open func getSinkConnectors() async throws -> [OcaMediaSinkConnector] {
    []
  }

  open func getSinkConnector(_ id: OcaMediaConnectorID) async throws -> OcaMediaSinkConnector {
    throw Ocp1Error.status(.notImplemented)
  }

  open func getConnectorsStatuses() async throws -> [OcaMediaConnectorStatus] {
    []
  }

  open func getConnectorStatus(_ id: OcaMediaConnectorID) async throws
    -> OcaMediaConnectorStatus
  {
    throw Ocp1Error.status(.notImplemented)
  }

  open func addSource(
    connector: inout OcaMediaSourceConnector,
    initialStatus: OcaMediaConnectorState
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func addSink(
    initialStatus: OcaMediaConnectorState,
    connector: inout OcaMediaSinkConnector
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func controlConnector(
    _ id: OcaMediaConnectorID,
    command: OcaMediaConnectorCommand
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func setSourceConnector(
    _ id: OcaMediaConnectorID,
    pinMap: [OcaUint16: OcaPortID]
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func setSinkConnector(
    _ id: OcaMediaConnectorID,
    pinMap: [OcaUint16: [OcaPortID]]
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func setConnector(_ id: OcaMediaConnectorID, connection: OcaMediaConnection) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func setConnector(_ id: OcaMediaConnectorID, coding: OcaMediaCoding) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func setConnector(_ id: OcaMediaConnectorID, alignmentLevel: OcaDBFS) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func setConnector(_ id: OcaMediaConnectorID, alignmentGain: OcaDB) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func deleteConnector(_ id: OcaMediaConnectorID) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod("3.3", name: "GetPortName", access: .read, resultNames: ["Name"])
  func getPortName(_ parameters: OcaGetPortNameParameters, from controller: any OcaController) throws -> OcaString {
    try portName(of: parameters.portID)
  }

  @OcaDeviceMethod("3.4", name: "SetPortName", access: .write)
  func setPortName(_ parameters: OcaSetPortNameParameters, from controller: any OcaController) throws {
    try setName(parameters.name, ofPort: parameters.portID)
  }

  @OcaDeviceMethod("3.9", name: "GetSourceConnectors", access: .read, resultNames: ["Connectors"])
  func getSourceConnectors(from controller: any OcaController) async throws -> [OcaMediaSourceConnector] {
    try await getSourceConnectors()
  }

  @OcaDeviceMethod("3.10", name: "GetSourceConnector", access: .read, parameterNames: ["ID"], resultNames: ["Connector"])
  func getSourceConnector(_ id: OcaMediaConnectorID, from controller: any OcaController) async throws
    -> OcaMediaSourceConnector
  {
    try await getSourceConnector(id)
  }

  @OcaDeviceMethod("3.11", name: "GetSinkConnectors", access: .read, resultNames: ["Connectors"])
  func getSinkConnectors(from controller: any OcaController) async throws -> [OcaMediaSinkConnector] {
    try await getSinkConnectors()
  }

  @OcaDeviceMethod("3.12", name: "GetSinkConnector", access: .read, parameterNames: ["ID"], resultNames: ["Connector"])
  func getSinkConnector(_ id: OcaMediaConnectorID, from controller: any OcaController) async throws
    -> OcaMediaSinkConnector
  {
    try await getSinkConnector(id)
  }

  @OcaDeviceMethod("3.13", name: "GetConnectorsStatuses", access: .read, resultNames: ["Statuses"])
  func getConnectorsStatuses(from controller: any OcaController) async throws -> [OcaMediaConnectorStatus] {
    try await getConnectorsStatuses()
  }

  @OcaDeviceMethod("3.14", name: "GetConnectorStatus", access: .read, parameterNames: ["ConnectorID"], resultNames: ["Status"])
  func getConnectorStatus(_ id: OcaMediaConnectorID, from controller: any OcaController) async throws
    -> OcaMediaConnectorStatus
  {
    try await getConnectorStatus(id)
  }

  @OcaDeviceMethod("3.15", name: "AddSourceConnector", access: .write, resultNames: ["Connector"])
  func addSourceConnector(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.AddSourceConnectorParameters,
    from controller: any OcaController
  ) async throws -> OcaMediaSourceConnector {
    var connector = parameters.connector
    try await addSource(connector: &connector, initialStatus: parameters.initialStatus)
    return connector
  }

  @OcaDeviceMethod("3.16", name: "AddSinkConnector", access: .write, resultNames: ["Connector"])
  func addSinkConnector(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.AddSinkConnectorParameters,
    from controller: any OcaController
  ) async throws -> OcaMediaSinkConnector {
    var connector = parameters.connector
    try await addSink(initialStatus: parameters.initialStatus, connector: &connector)
    return connector
  }

  @OcaDeviceMethod("3.17", name: "ControlConnector", access: .write)
  func controlConnector(_ parameters: SwiftOCA.OcaMediaTransportNetwork.ControlConnectorParameters, from controller: any OcaController) async throws {
    try await controlConnector(parameters.connectorID, command: parameters.command)
  }

  @OcaDeviceMethod("3.18", name: "SetSourceConnectorPinMap", access: .write)
  func setSourceConnectorPinMap(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.SetSourceConnectorPinMapParameters,
    from controller: any OcaController
  ) async throws {
    try await setSourceConnector(parameters.connectorID, pinMap: parameters.channelPinMap)
  }

  @OcaDeviceMethod("3.19", name: "SetSinkConnectorPinMap", access: .write)
  func setSinkConnectorPinMap(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.SetSinkConnectorPinMapParameters,
    from controller: any OcaController
  ) async throws {
    try await setSinkConnector(parameters.connectorID, pinMap: parameters.channelPinMap)
  }

  @OcaDeviceMethod("3.20", name: "SetConnectorConnection", access: .write)
  func setConnectorConnection(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.SetConnectorConnectionParameters,
    from controller: any OcaController
  ) async throws {
    try await setConnector(parameters.connectorID, connection: parameters.connection)
  }

  @OcaDeviceMethod("3.21", name: "SetConnectorCoding", access: .write)
  func setConnectorCoding(_ parameters: SwiftOCA.OcaMediaTransportNetwork.SetConnectorCodingParameters, from controller: any OcaController) async throws {
    try await setConnector(parameters.connectorID, coding: parameters.coding)
  }

  @OcaDeviceMethod("3.22", name: "SetConnectorAlignmentLevel", access: .write)
  func setConnectorAlignmentLevel(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.SetConnectorAlignmentLevelParameters,
    from controller: any OcaController
  ) async throws {
    try await setConnector(parameters.connectorID, alignmentLevel: parameters.level)
  }

  @OcaDeviceMethod("3.23", name: "SetConnectorAlignmentGain", access: .write)
  func setConnectorAlignmentGain(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.SetConnectorAlignmentGainParameters,
    from controller: any OcaController
  ) async throws {
    try await setConnector(parameters.connectorID, alignmentGain: parameters.gain)
  }

  @OcaDeviceMethod("3.24", name: "DeleteConnector", access: .write, parameterNames: ["ID"])
  func deleteConnector(_ id: OcaMediaConnectorID, from controller: any OcaController) async throws {
    try await deleteConnector(id)
  }
}
