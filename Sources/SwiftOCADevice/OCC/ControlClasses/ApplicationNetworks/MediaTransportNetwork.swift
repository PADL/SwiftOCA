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

public class OcaMediaTransportNetwork: OcaApplicationNetwork, OcaPortsRepresentable {
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
    public var alignmentLevel: OcaDBFS = -20.0

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.8"),
        getMethodID: OcaMethodID("3.26")
    )
    public var alignmentGain: OcaDB = 0.0

    // 3.9 getSourceConnecotrs
    // 3.10 getSourceConnector
    // 3.11 getSinkConnectors
    // 3.12 getSinkConnector
    // 3.13 getConnectorsStatuses
    // 3.14 getConnectorStatus
    // 3.15 addSourceConnector
    // 3.16 addSinkConnector
    // 3.17 controlConnector
    // 3.18 setSourceConnectorPinMap
    // 3.19 setSinkConnectorPinMap
    // 3.20 setConnectorConnection
    // 3.21 setConnectorCoding
    // 3.22 setConnectorAlignmentLevel
    // 3.23 setConnectorAlignmentGain
    // 3.24 deleteConnector

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: AES70Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("3.3"):
            return try await encodeResponse(handleGetPortName(command, from: controller))
        case OcaMethodID("3.4"):
            try await handleSetPortName(command, from: controller)
            return Ocp1Response()
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }
}
