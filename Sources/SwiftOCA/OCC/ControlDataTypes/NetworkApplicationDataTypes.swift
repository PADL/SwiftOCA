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

public enum OcaIP4AutoconfigMode: OcaUint8, Codable, Sendable {
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

public enum OcaIP6AutoconfigMode: OcaUint8, Codable, Sendable {
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
