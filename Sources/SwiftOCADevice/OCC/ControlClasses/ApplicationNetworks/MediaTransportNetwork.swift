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

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getPortName, access: .read)
  func getPortName(_ parameters: OcaGetPortNameParameters, from controller: any OcaController) throws -> OcaString {
    try portName(of: parameters.portID)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setPortName, access: .write)
  func setPortName(_ parameters: OcaSetPortNameParameters, from controller: any OcaController) throws {
    try setName(parameters.name, ofPort: parameters.portID)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getSourceConnectors, access: .read)
  func getSourceConnectors(from controller: any OcaController) async throws -> [OcaMediaSourceConnector] {
    try await getSourceConnectors()
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getSourceConnector, access: .read)
  func getSourceConnector(_ id: OcaMediaConnectorID, from controller: any OcaController) async throws
    -> OcaMediaSourceConnector
  {
    try await getSourceConnector(id)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getSinkConnectors, access: .read)
  func getSinkConnectors(from controller: any OcaController) async throws -> [OcaMediaSinkConnector] {
    try await getSinkConnectors()
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getSinkConnector, access: .read)
  func getSinkConnector(_ id: OcaMediaConnectorID, from controller: any OcaController) async throws
    -> OcaMediaSinkConnector
  {
    try await getSinkConnector(id)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getConnectorsStatuses, access: .read)
  func getConnectorsStatuses(from controller: any OcaController) async throws -> [OcaMediaConnectorStatus] {
    try await getConnectorsStatuses()
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getConnectorStatus, access: .read)
  func getConnectorStatus(_ id: OcaMediaConnectorID, from controller: any OcaController) async throws
    -> OcaMediaConnectorStatus
  {
    try await getConnectorStatus(id)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.addSourceConnector, access: .write)
  func addSourceConnector(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.AddSourceConnectorParameters,
    from controller: any OcaController
  ) async throws -> OcaMediaSourceConnector {
    var connector = parameters.connector
    try await addSource(connector: &connector, initialStatus: parameters.initialStatus)
    return connector
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.addSinkConnector, access: .write)
  func addSinkConnector(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.AddSinkConnectorParameters,
    from controller: any OcaController
  ) async throws -> OcaMediaSinkConnector {
    var connector = parameters.connector
    try await addSink(initialStatus: parameters.initialStatus, connector: &connector)
    return connector
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.controlConnector, access: .write)
  func controlConnector(_ parameters: SwiftOCA.OcaMediaTransportNetwork.ControlConnectorParameters, from controller: any OcaController) async throws {
    try await controlConnector(parameters.connectorID, command: parameters.command)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setSourceConnectorPinMap, access: .write)
  func setSourceConnectorPinMap(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.SetSourceConnectorPinMapParameters,
    from controller: any OcaController
  ) async throws {
    try await setSourceConnector(parameters.connectorID, pinMap: parameters.channelPinMap)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setSinkConnectorPinMap, access: .write)
  func setSinkConnectorPinMap(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.SetSinkConnectorPinMapParameters,
    from controller: any OcaController
  ) async throws {
    try await setSinkConnector(parameters.connectorID, pinMap: parameters.channelPinMap)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setConnectorConnection, access: .write)
  func setConnectorConnection(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.SetConnectorConnectionParameters,
    from controller: any OcaController
  ) async throws {
    try await setConnector(parameters.connectorID, connection: parameters.connection)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setConnectorCoding, access: .write)
  func setConnectorCoding(_ parameters: SwiftOCA.OcaMediaTransportNetwork.SetConnectorCodingParameters, from controller: any OcaController) async throws {
    try await setConnector(parameters.connectorID, coding: parameters.coding)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setConnectorAlignmentLevel, access: .write)
  func setConnectorAlignmentLevel(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.SetConnectorAlignmentLevelParameters,
    from controller: any OcaController
  ) async throws {
    try await setConnector(parameters.connectorID, alignmentLevel: parameters.level)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setConnectorAlignmentGain, access: .write)
  func setConnectorAlignmentGain(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.SetConnectorAlignmentGainParameters,
    from controller: any OcaController
  ) async throws {
    try await setConnector(parameters.connectorID, alignmentGain: parameters.gain)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.deleteConnector, access: .write)
  func deleteConnector(_ id: OcaMediaConnectorID, from controller: any OcaController) async throws {
    try await deleteConnector(id)
  }
}
