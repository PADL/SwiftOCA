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

open class OcaMediaTransportNetwork: OcaApplicationNetwork {
    override public class var classID: OcaClassID { OcaClassID("1.4.2") }
    override public class var classVersion: OcaClassVersionNumber { 1 }

    @OcaProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.1")
    )
    public var `protocol`: OcaProperty<OcaNetworkMediaProtocol>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.2"),
        getMethodID: OcaMethodID("3.2")
    )
    public var ports: OcaProperty<[OcaPort]>.PropertyValue

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
}
