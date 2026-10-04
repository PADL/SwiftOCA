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

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.getSourceConnectors)
  open func getSourceConnectors(from controller: any OcaController) async throws -> [OcaMediaSourceConnector] {
    []
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.getSourceConnector)
  open func getSourceConnector(id: OcaMediaConnectorID, from controller: any OcaController) async throws
    -> OcaMediaSourceConnector
  {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.getSinkConnectors)
  open func getSinkConnectors(from controller: any OcaController) async throws -> [OcaMediaSinkConnector] {
    []
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.getSinkConnector)
  open func getSinkConnector(id: OcaMediaConnectorID, from controller: any OcaController) async throws
    -> OcaMediaSinkConnector
  {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.getConnectorsStatuses)
  open func getConnectorsStatuses(from controller: any OcaController) async throws -> [OcaMediaConnectorStatus] {
    []
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.getConnectorStatus)
  open func getConnectorStatus(connectorID: OcaMediaConnectorID, from controller: any OcaController) async throws
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

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.controlConnector, access: .write)
  open func controlConnector(
    connectorID: OcaMediaConnectorID,
    command: OcaMediaConnectorCommand,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.setSourceConnectorPinMap)
  open func setSourceConnectorPinMap(
    connectorID: OcaMediaConnectorID,
    channelPinMap: [OcaUint16: OcaPortID],
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.setSinkConnectorPinMap)
  open func setSinkConnectorPinMap(
    connectorID: OcaMediaConnectorID,
    channelPinMap: [OcaUint16: [OcaPortID]],
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.setConnectorConnection)
  open func setConnectorConnection(
    connectorID: OcaMediaConnectorID,
    connection: OcaMediaConnection,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.setConnectorCoding)
  open func setConnectorCoding(
    connectorID: OcaMediaConnectorID,
    coding: OcaMediaCoding,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.setConnectorAlignmentLevel)
  open func setConnectorAlignmentLevel(
    connectorID: OcaMediaConnectorID,
    level: OcaDBFS,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.setConnectorAlignmentGain)
  open func setConnectorAlignmentGain(
    connectorID: OcaMediaConnectorID,
    gain: OcaDB,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.deleteConnector)
  open func deleteConnector(id: OcaMediaConnectorID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.getPortName)
  func getPortName(portID: OcaPortID, from controller: any OcaController) throws -> OcaString {
    try portName(of: portID)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.setPortName)
  func setPortName(portID: OcaPortID, name: OcaString, from controller: any OcaController) throws {
    try setName(name, ofPort: portID)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.addSourceConnector)
  func addSourceConnector(
    connector: OcaMediaSourceConnector,
    initialStatus: OcaMediaConnectorState,
    from controller: any OcaController
  ) async throws -> OcaMediaSourceConnector {
    var connector = connector
    try await addSource(connector: &connector, initialStatus: initialStatus)
    return connector
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.Methods.addSinkConnector)
  func addSinkConnector(
    initialStatus: OcaMediaConnectorState,
    connector: OcaMediaSinkConnector,
    from controller: any OcaController
  ) async throws -> OcaMediaSinkConnector {
    var connector = connector
    try await addSink(initialStatus: initialStatus, connector: &connector)
    return connector
  }
}
