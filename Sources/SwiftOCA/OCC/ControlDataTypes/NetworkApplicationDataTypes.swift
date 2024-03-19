//
// Copyright (c) 2024 PADL Software Pty Ltd
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

public struct OcaPortClockMapEntry: Codable, Sendable {
    public let clockONo: OcaONo
    public let srcType: OcaSamplingRateConverterType
}

public struct OcaSetPortClockMapEntryParameters: Ocp1ParametersReflectable {
    public let portID: OcaPortID
    public let portClockMapEntry: OcaPortClockMapEntry

    public init(portID: OcaPortID, portClockMapEntry: OcaPortClockMapEntry) {
        self.portID = portID
        self.portClockMapEntry = portClockMapEntry
    }
}

public enum OcaNetworkAdvertisingService: OcaUint8, Codable, Sendable, CaseIterable {
    case dnsSD = 0
    case mDNS_DNSSD = 1
    case nmos = 2
    case expansionBase = 128
}

public struct OcaNetworkAdvertisingMechanism: Codable, Sendable {
    public let service: OcaNetworkAdvertisingService
    /// JSON-encoded parameters, e.g.
    /// ServerAddresses: [`1.2.3.4`]
    /// RegistrationDomain: `.local`
    /// ServiceType: `_oca._tcp`
    /// ServiceName: `hostname`
    public let parameters: OcaParameterRecord

    public init(
        service: OcaNetworkAdvertisingService,
        parameters: OcaParameterRecord,
        networkInterfaceAssignment: OcaNetworkInterfaceAssignment
    ) {
        self.service = service
        self.parameters = parameters
    }
}

public struct OcaNetworkInterfaceAssignment: Codable, Sendable {
    // internal ID
    public let id: OcaID16
    // ONo of network interface
    public let networkInterfaceONo: OcaONo
    // assignment-specific, e.g. IP port as encoded UInt16
    public let networkBindingParameters: OcaBlob
    // zero or more PSK identifies that apply to the IP port
    public let securityKeyIdentities: [OcaString]
    // list of advertising mechanisms
    public let advertisingMechanisms: [OcaNetworkAdvertisingMechanism]

    public init(
        id: OcaID16,
        networkInterfaceONo: OcaONo,
        networkBindingParameters: OcaBlob,
        securityKeyIdentities: [OcaString],
        advertisingMechanisms: [OcaNetworkAdvertisingMechanism]
    ) {
        self.id = id
        self.networkInterfaceONo = networkInterfaceONo
        self.networkBindingParameters = networkBindingParameters
        self.securityKeyIdentities = securityKeyIdentities
        self.advertisingMechanisms = advertisingMechanisms
    }
}

public enum OcaNetworkInterfaceCommand: OcaUint8, Codable, Sendable, CaseIterable {
    case start = 0
    case stop = 1
    case restart = 2
}

public enum OcaNetworkInterfaceState: OcaUint8, Codable, Sendable, CaseIterable {
    case notReady = 0
    case ready = 1
    case fault = 2
}

public struct OcaNetworkInterfaceStatus: Codable, Sendable {
    public let state: OcaNetworkInterfaceState
    public let adaptationData: OcaAdaptationData

    public init(state: OcaNetworkInterfaceState, adaptationData: OcaAdaptationData) {
        self.state = state
        self.adaptationData = adaptationData
    }
}

public typealias OcaIP4Address = OcaString
public typealias OcaIP4AddressAndPrefix = OcaString

public struct OcaIP4Gateway: Codable, Sendable {
    public let destinationPrefix: OcaIP4AddressAndPrefix
    public let gatewayAddress: OcaIP4Address
    public let metric: OcaUint16

    public init(
        destinationPrefix: OcaIP4AddressAndPrefix,
        gatewayAddress: OcaIP4Address,
        metric: OcaUint16
    ) {
        self.destinationPrefix = destinationPrefix
        self.gatewayAddress = gatewayAddress
        self.metric = metric
    }
}

public enum OcaIP4AutoconfigMode: OcaUint8, Codable, Sendable, CaseIterable {
    case none = 0
    case dhcp = 1
    case dhcpLinkLocal = 2
    case linkLocal = 3
}

public struct OcaIP4NetworkSettings: Codable, Sendable {
    public let addressAndPrefix: OcaIP4AddressAndPrefix
    public let autoconfigMode: OcaIP4AutoconfigMode
    public let dhcpServerAddress: OcaIP4Address
    public let defaultGatewayAddress: OcaIP4Address
    public let additionalGateways: [OcaIP4Gateway]
    public let dnsServerAddresses: [OcaIP4Address]
    public let additionalParameters: OcaParameterRecord

    public init(
        addressAndPrefix: OcaIP4AddressAndPrefix,
        autoconfigMode: OcaIP4AutoconfigMode,
        dhcpServerAddress: OcaIP4Address,
        defaultGatewayAddress: OcaIP4Address,
        additionalGateways: [OcaIP4Gateway],
        dnsServerAddresses: [OcaIP4Address],
        additionalParameters: OcaParameterRecord
    ) {
        self.addressAndPrefix = addressAndPrefix
        self.autoconfigMode = autoconfigMode
        self.dhcpServerAddress = dhcpServerAddress
        self.defaultGatewayAddress = defaultGatewayAddress
        self.additionalGateways = additionalGateways
        self.dnsServerAddresses = dnsServerAddresses
        self.additionalParameters = additionalParameters
    }
}

public typealias OcaIP6Address = OcaString
public typealias OcaIP6AddressAndPrefix = OcaString

public struct OcaIP6Gateway: Codable, Sendable {
    public let destinationPrefix: OcaIP6AddressAndPrefix
    public let gatewayAddress: OcaIP6Address
    public let metric: OcaUint16

    public init(
        destinationPrefix: OcaIP4AddressAndPrefix,
        gatewayAddress: OcaIP4Address,
        metric: OcaUint16
    ) {
        self.destinationPrefix = destinationPrefix
        self.gatewayAddress = gatewayAddress
        self.metric = metric
    }
}

public enum OcaIP6AutoconfigMode: OcaUint8, Codable, Sendable, CaseIterable {
    case none = 0
    case slaac = 1
    case dhcpStateless = 2
    case dhcpStateful = 3
}

public struct OcaIP6NetworkSettings: Codable, Sendable {
    public let addressAndPrefix: OcaIP6AddressAndPrefix
    public let autoconfigMode: OcaIP6AutoconfigMode
    public let linkLocalAddress: OcaIP6Address
    public let dhcpServerAddress: OcaIP6Address
    public let defaultGatewayAddress: OcaIP6Address
    public let additionalGateways: [OcaIP6Gateway]
    public let dnsServerAddresses: [OcaIP6Address]
    public let additionalParameters: OcaParameterRecord

    public init(
        addressAndPrefix: OcaIP6AddressAndPrefix,
        autoconfigMode: OcaIP6AutoconfigMode,
        linkLocalAddress: OcaIP6Address,
        dhcpServerAddress: OcaIP6Address,
        defaultGatewayAddress: OcaIP6Address,
        additionalGateways: [OcaIP6Gateway],
        dnsServerAddresses: [OcaIP6Address],
        additionalParameters: OcaParameterRecord
    ) {
        self.addressAndPrefix = addressAndPrefix
        self.autoconfigMode = autoconfigMode
        self.linkLocalAddress = linkLocalAddress
        self.dhcpServerAddress = dhcpServerAddress
        self.defaultGatewayAddress = defaultGatewayAddress
        self.additionalGateways = additionalGateways
        self.dnsServerAddresses = dnsServerAddresses
        self.additionalParameters = additionalParameters
    }
}
