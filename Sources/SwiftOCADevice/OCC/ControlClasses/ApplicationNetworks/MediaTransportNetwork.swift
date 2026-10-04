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

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getSourceConnectors)
  open func getSourceConnectors(from controller: any OcaController) async throws -> [OcaMediaSourceConnector] {
    []
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getSourceConnector)
  open func getSourceConnector(_ id: OcaMediaConnectorID, from controller: any OcaController) async throws
    -> OcaMediaSourceConnector
  {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getSinkConnectors)
  open func getSinkConnectors(from controller: any OcaController) async throws -> [OcaMediaSinkConnector] {
    []
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getSinkConnector)
  open func getSinkConnector(_ id: OcaMediaConnectorID, from controller: any OcaController) async throws
    -> OcaMediaSinkConnector
  {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getConnectorsStatuses)
  open func getConnectorsStatuses(from controller: any OcaController) async throws -> [OcaMediaConnectorStatus] {
    []
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getConnectorStatus)
  open func getConnectorStatus(_ id: OcaMediaConnectorID, from controller: any OcaController) async throws
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

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.controlConnector, access: .write)
  open func controlConnector(
    _ connectorID: OcaMediaConnectorID,
    command: OcaMediaConnectorCommand,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setSourceConnectorPinMap)
  open func setSourceConnector(
    _ connectorID: OcaMediaConnectorID,
    pinMap channelPinMap: [OcaUint16: OcaPortID],
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setSinkConnectorPinMap)
  open func setSinkConnector(
    _ connectorID: OcaMediaConnectorID,
    pinMap channelPinMap: [OcaUint16: [OcaPortID]],
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setConnectorConnection)
  open func setConnector(
    _ connectorID: OcaMediaConnectorID,
    connection: OcaMediaConnection,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setConnectorCoding)
  open func setConnector(
    _ connectorID: OcaMediaConnectorID,
    coding: OcaMediaCoding,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setConnectorAlignmentLevel)
  open func setConnector(
    _ connectorID: OcaMediaConnectorID,
    alignmentLevel level: OcaDBFS,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setConnectorAlignmentGain)
  open func setConnector(
    _ connectorID: OcaMediaConnectorID,
    alignmentGain gain: OcaDB,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.deleteConnector)
  open func deleteConnector(_ id: OcaMediaConnectorID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.getPortName)
  func getPortName(_ parameters: OcaGetPortNameParameters, from controller: any OcaController) throws -> OcaString {
    try portName(of: parameters.portID)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.setPortName)
  func setPortName(_ portID: OcaPortID, _ name: OcaString, from controller: any OcaController) throws {
    try setName(name, ofPort: portID)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.addSourceConnector)
  func addSourceConnector(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.AddSourceConnectorParameters,
    from controller: any OcaController
  ) async throws -> OcaMediaSourceConnector {
    var connector = parameters.connector
    try await addSource(connector: &connector, initialStatus: parameters.initialStatus)
    return connector
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaTransportNetwork.addSinkConnector)
  func addSinkConnector(
    _ parameters: SwiftOCA.OcaMediaTransportNetwork.AddSinkConnectorParameters,
    from controller: any OcaController
  ) async throws -> OcaMediaSinkConnector {
    var connector = parameters.connector
    try await addSink(initialStatus: parameters.initialStatus, connector: &connector)
    return connector
  }
}
