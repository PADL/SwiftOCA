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

open class OcaMediaTransportNetwork: OcaApplicationNetwork, OcaPortsRepresentable {
    override public class var classID: OcaClassID { OcaClassID("1.4.2") }
    override public class var classVersion: OcaClassVersionNumber { 1 }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.1")
    )
    public var `protocol`: OcaNetworkMediaProtocol = .none

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.2"),
        getMethodID: OcaMethodID("3.2")
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
        getMethodID: OcaMethodID("3.7")
    )
    public var maxPinsPerConnector: OcaUint16 = 0

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.6"),
        getMethodID: OcaMethodID("3.8")
    )
    public var maxPortsPerPin: OcaUint16 = 0

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.7"),
        getMethodID: OcaMethodID("3.25")
    )
    public var alignmentLevel = OcaBoundedPropertyValue<OcaDBFS>(value: -20.0, in: -20.0 ... -20.0)

    @OcaDeviceProperty(
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
        throw Ocp1Error.notImplemented
    }

    open func getSinkConnectors() async throws -> [OcaMediaSinkConnector] {
        []
    }

    open func getSinkConnector(_ id: OcaMediaConnectorID) async throws -> OcaMediaSinkConnector {
        throw Ocp1Error.notImplemented
    }

    open func getConnectorsStatuses() async throws -> [OcaMediaConnectorStatus] {
        []
    }

    open func getConnectorStatus(_ id: OcaMediaConnectorID) async throws
        -> OcaMediaConnectorStatus
    {
        throw Ocp1Error.notImplemented
    }

    open func addSource(
        connector: inout OcaMediaSourceConnector,
        initialStatus: OcaMediaConnectorState
    ) async throws {
        throw Ocp1Error.notImplemented
    }

    open func addSink(
        initialStatus: OcaMediaConnectorState,
        connector: inout OcaMediaSinkConnector
    ) async throws {
        throw Ocp1Error.notImplemented
    }

    open func controlConnector(
        _ id: OcaMediaConnectorID,
        command: OcaMediaConnectorCommand
    ) async throws {
        throw Ocp1Error.notImplemented
    }

    open func setSourceConnector(
        _ id: OcaMediaConnectorID,
        pinMap: [OcaUint16: OcaPortID]
    ) async throws {
        throw Ocp1Error.notImplemented
    }

    open func setSinkConnector(
        _ id: OcaMediaConnectorID,
        pinMap: [OcaUint16: [OcaPortID]]
    ) async throws {
        throw Ocp1Error.notImplemented
    }

    open func setConnector(_ id: OcaMediaConnectorID, connection: OcaMediaConnection) async throws {
        throw Ocp1Error.notImplemented
    }

    open func setConnector(_ id: OcaMediaConnectorID, coding: OcaMediaCoding) async throws {
        throw Ocp1Error.notImplemented
    }

    open func setConnector(_ id: OcaMediaConnectorID, alignmentLevel: OcaDBFS) async throws {
        throw Ocp1Error.notImplemented
    }

    open func setConnector(_ id: OcaMediaConnectorID, alignmentGain: OcaDB) async throws {
        throw Ocp1Error.notImplemented
    }

    open func deleteConnector(_ id: OcaMediaConnectorID) async throws {
        throw Ocp1Error.notImplemented
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: OcaController
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("3.3"):
            return try await encodeResponse(handleGetPortName(command, from: controller))
        case OcaMethodID("3.4"):
            try await handleSetPortName(command, from: controller)
            return Ocp1Response()
        case OcaMethodID("3.9"):
            try decodeNullCommand(command)
            try await ensureReadable(by: controller, command: command)
            let sourceConnectors = try await getSourceConnectors()
            return try encodeResponse(sourceConnectors)
        case OcaMethodID("3.10"):
            let id: OcaMediaConnectorID = try decodeCommand(command)
            try await ensureReadable(by: controller, command: command)
            let sourceConnector = try await getSourceConnector(id)
            return try encodeResponse(sourceConnector)
        case OcaMethodID("3.11"):
            try decodeNullCommand(command)
            try await ensureReadable(by: controller, command: command)
            let sinkConnectors = try await getSinkConnectors()
            return try encodeResponse(sinkConnectors)
        case OcaMethodID("3.12"):
            let id: OcaMediaConnectorID = try decodeCommand(command)
            try await ensureReadable(by: controller, command: command)
            let sinkConnector = try await getSinkConnector(id)
            return try encodeResponse(sinkConnector)
        case OcaMethodID("3.13"):
            try decodeNullCommand(command)
            try await ensureReadable(by: controller, command: command)
            let connectorStatuses = try await getConnectorsStatuses()
            return try encodeResponse(connectorStatuses)
        case OcaMethodID("3.14"):
            let id: OcaMediaConnectorID = try decodeCommand(command)
            try await ensureReadable(by: controller, command: command)
            let connectorStatus = try await getConnectorStatus(id)
            return try encodeResponse(connectorStatus)
        case OcaMethodID("3.15"):
            var params: SwiftOCA.OcaMediaTransportNetwork
                .AddSourceConnectorParameters = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await addSource(connector: &params.connector, initialStatus: params.initialStatus)
            return try encodeResponse(params.connector)
        case OcaMethodID("3.16"):
            var params: SwiftOCA.OcaMediaTransportNetwork
                .AddSinkConnectorParameters = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await addSink(initialStatus: params.initialStatus, connector: &params.connector)
            return try encodeResponse(params.connector)
        case OcaMethodID("3.17"):
            let params: SwiftOCA.OcaMediaTransportNetwork
                .ControlConnectorParameters = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await controlConnector(params.id, command: params.command)
            return Ocp1Response()
        case OcaMethodID("3.18"):
            let params: SwiftOCA.OcaMediaTransportNetwork
                .SetSourceConnectorPinMapParameters = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await setSourceConnector(params.id, pinMap: params.pinMap)
            return Ocp1Response()
        case OcaMethodID("3.19"):
            let params: SwiftOCA.OcaMediaTransportNetwork
                .SetSinkConnectorPinMapParameters = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await setSinkConnector(params.id, pinMap: params.pinMap)
            return Ocp1Response()
        case OcaMethodID("3.20"):
            let params: SwiftOCA.OcaMediaTransportNetwork
                .SetConnectorConnectionParameters = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await setConnector(params.id, connection: params.connection)
            return Ocp1Response()

        case OcaMethodID("3.21"):
            let params: SwiftOCA.OcaMediaTransportNetwork
                .SetConnectorCodingParameters = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await setConnector(params.id, coding: params.coding)
            return Ocp1Response()
        case OcaMethodID("3.22"):
            let params: SwiftOCA.OcaMediaTransportNetwork
                .SetConnectorAlignmentLevelParameters = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await setConnector(params.id, alignmentLevel: params.alignmentLevel)
            return Ocp1Response()
        case OcaMethodID("3.23"):
            let params: SwiftOCA.OcaMediaTransportNetwork
                .SetConnectorAlignmentGainParameters = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await setConnector(params.id, alignmentGain: params.alignmentGain)
            return Ocp1Response()
        case OcaMethodID("3.24"):
            let id: OcaMediaConnectorID = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await deleteConnector(id)
            return Ocp1Response()
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }
}
