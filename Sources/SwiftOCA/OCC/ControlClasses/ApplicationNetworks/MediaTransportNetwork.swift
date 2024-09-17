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
  override open class var classID: OcaClassID { OcaClassID("1.4.2") }
  override open class var classVersion: OcaClassVersionNumber { 1 }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var `protocol`: OcaProperty<OcaNetworkMediaProtocol>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.2")
  )
  public var ports: OcaListProperty<OcaPort>.PropertyValue

  public func get(portID: OcaPortID) async throws -> OcaString {
    let params = OcaGetPortNameParameters(portID: portID)
    return try await sendCommandRrq(
      methodID: OcaMethodID("3.3"),
      parameters: params
    )
  }

  public func set(portID: OcaPortID, name: OcaString) async throws {
    let params = OcaSetPortNameParameters(portID: portID, name: name)
    try await sendCommandRrq(
      methodID: OcaMethodID("3.4"),
      parameters: params
    )
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
    getMethodID: OcaMethodID("3.7")
  )
  public var maxPinsPerConnector: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.6"),
    getMethodID: OcaMethodID("3.8")
  )
  public var maxPortsPerPin: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.7"),
    getMethodID: OcaMethodID("3.25")
  )
  public var alignmentLevel: OcaProperty<OcaDBFS>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.8"),
    getMethodID: OcaMethodID("3.26")
  )
  public var alignmentGain: OcaProperty<OcaDB>.PropertyValue

  public func getSourceConnectors() async throws -> [OcaMediaSourceConnector] {
    try await sendCommandRrq(methodID: OcaMethodID("3.9"))
  }

  public func getSourceConnector(_ id: OcaMediaConnectorID) async throws
    -> OcaMediaSourceConnector
  {
    try await sendCommandRrq(methodID: OcaMethodID("3.10"), parameters: id)
  }

  public func getSinkConnectors() async throws -> [OcaMediaSinkConnector] {
    try await sendCommandRrq(methodID: OcaMethodID("3.11"))
  }

  public func getSinkConnector(_ id: OcaMediaConnectorID) async throws -> OcaMediaSinkConnector {
    try await sendCommandRrq(methodID: OcaMethodID("3.12"), parameters: id)
  }

  public func getConnectorsStatuses() async throws -> [OcaMediaConnectorStatus] {
    try await sendCommandRrq(methodID: OcaMethodID("3.13"))
  }

  public func getConnectorStatus(_ id: OcaMediaConnectorID) async throws
    -> OcaMediaConnectorStatus
  {
    try await sendCommandRrq(methodID: OcaMethodID("3.14"), parameters: id)
  }

  public struct AddSourceConnectorParameters: Ocp1ParametersReflectable {
    public var connector: OcaMediaSourceConnector
    public let initialStatus: OcaMediaConnectorState
  }

  public func addSource(
    connector: inout OcaMediaSourceConnector,
    initialStatus: OcaMediaConnectorState
  ) async throws {
    let parameters = AddSourceConnectorParameters(
      connector: connector,
      initialStatus: initialStatus
    )
    connector = try await sendCommandRrq(methodID: OcaMethodID("3.15"), parameters: parameters)
  }

  public struct AddSinkConnectorParameters: Ocp1ParametersReflectable {
    public let initialStatus: OcaMediaConnectorState
    public var connector: OcaMediaSinkConnector
  }

  public func addSink(
    initialStatus: OcaMediaConnectorState,
    connector: inout OcaMediaSinkConnector
  ) async throws {
    let parameters = AddSinkConnectorParameters(
      initialStatus: initialStatus,
      connector: connector
    )
    connector = try await sendCommandRrq(methodID: OcaMethodID("3.16"), parameters: parameters)
  }

  public struct ControlConnectorParameters: Ocp1ParametersReflectable {
    public let id: OcaMediaConnectorID
    public let command: OcaMediaConnectorCommand
  }

  public func controlConnector(
    _ id: OcaMediaConnectorID,
    command: OcaMediaConnectorCommand
  ) async throws {
    let parameters = ControlConnectorParameters(id: id, command: command)
    try await sendCommandRrq(methodID: OcaMethodID("3.17"), parameters: parameters)
  }

  public struct SetSourceConnectorPinMapParameters: Ocp1ParametersReflectable {
    public let id: OcaMediaConnectorID
    public let pinMap: [OcaUint16: OcaPortID]
  }

  public func setSourceConnector(
    _ id: OcaMediaConnectorID,
    pinMap: [OcaUint16: OcaPortID]
  ) async throws {
    let parameters = SetSourceConnectorPinMapParameters(id: id, pinMap: pinMap)
    try await sendCommandRrq(methodID: OcaMethodID("3.18"), parameters: parameters)
  }

  public struct SetSinkConnectorPinMapParameters: Ocp1ParametersReflectable {
    public let id: OcaMediaConnectorID
    public let pinMap: [OcaUint16: [OcaPortID]]
  }

  public func setSinkConnector(
    _ id: OcaMediaConnectorID,
    pinMap: [OcaUint16: [OcaPortID]]
  ) async throws {
    let parameters = SetSinkConnectorPinMapParameters(id: id, pinMap: pinMap)
    try await sendCommandRrq(methodID: OcaMethodID("3.19"), parameters: parameters)
  }

  public struct SetConnectorConnectionParameters: Ocp1ParametersReflectable {
    public let id: OcaMediaConnectorID
    public let connection: OcaMediaConnection
  }

  public func setConnector(
    _ id: OcaMediaConnectorID,
    connection: OcaMediaConnection
  ) async throws {
    let parameters = SetConnectorConnectionParameters(id: id, connection: connection)
    try await sendCommandRrq(methodID: OcaMethodID("3.20"), parameters: parameters)
  }

  public struct SetConnectorCodingParameters: Ocp1ParametersReflectable {
    public let id: OcaMediaConnectorID
    public let coding: OcaMediaCoding
  }

  public func setConnector(_ id: OcaMediaConnectorID, coding: OcaMediaCoding) async throws {
    let parameters = SetConnectorCodingParameters(id: id, coding: coding)
    try await sendCommandRrq(methodID: OcaMethodID("3.21"), parameters: parameters)
  }

  public struct SetConnectorAlignmentLevelParameters: Ocp1ParametersReflectable {
    public let id: OcaMediaConnectorID
    public let alignmentLevel: OcaDBFS
  }

  public func setConnector(_ id: OcaMediaConnectorID, alignmentLevel: OcaDBFS) async throws {
    let parameters = SetConnectorAlignmentLevelParameters(
      id: id,
      alignmentLevel: alignmentLevel
    )
    try await sendCommandRrq(methodID: OcaMethodID("3.22"), parameters: parameters)
  }

  public struct SetConnectorAlignmentGainParameters: Ocp1ParametersReflectable {
    public let id: OcaMediaConnectorID
    public let alignmentGain: OcaDB
  }

  public func setConnector(_ id: OcaMediaConnectorID, alignmentGain: OcaDB) async throws {
    let parameters = SetConnectorAlignmentGainParameters(id: id, alignmentGain: alignmentGain)
    try await sendCommandRrq(methodID: OcaMethodID("3.23"), parameters: parameters)
  }

  public func deleteConnector(_ id: OcaMediaConnectorID) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.24"), parameters: id)
  }
}
