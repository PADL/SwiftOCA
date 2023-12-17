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

public enum OcaNetworkLinkType: OcaUint8, Codable, Sendable {
    case none = 0
    case ethernetWired = 1
    case ethernetWireless = 2
    case usb = 3
    case serialP2P = 4
}

public enum OcaNetworkMediaProtocol: OcaUint8, Codable, Sendable {
    case none = 0
    case av3 = 1
    case avbtp = 2
    case dante = 3
    case cobranet = 4
    case aes67 = 5
    case smpteAudio = 6
    case liveWire = 7
    case extensionPoint = 65
}

public enum OcaNetworkControlProtocol: OcaUint8, Codable, Sendable {
    case none = 0
    case ocp01 = 1 // TCP/IP
    case ocp02 = 2 // USB
    case ocp03 = 3 // JSON
}

public enum Ocp1IPParametersType: OcaUint8, Codable, Sendable {
    case unknown = 0
    case linkLocal = 1
    case dhcp = 2
    case `static` = 3
}

public struct Ocp1SystemInterfaceParameters: Codable, Sendable {
    public typealias EUI48 = (OcaUint8, OcaUint8, OcaUint8, OcaUint8, OcaUint8, OcaUint8)

    public let version: OcaUint16 // 1
    public let hostname: OcaString
    public let interfaceIndex: OcaUint32
    public let subnetMaskLength: OcaUint8
    public let defaultGateway: OcaString
    public let dnsServers: OcaString // comma-separated
    public let linkUp: OcaBoolean
    public let adapterSpeed: OcaUint64
    public let parametersType: Ocp1IPParametersType
    public let macAddress: EUI48
    public let linkType: OcaNetworkLinkType

    public init(
        version: OcaUint16,
        hostname: OcaString,
        interfaceIndex: OcaUint32,
        subnetMaskLength: OcaUint8,
        defaultGateway: OcaString,
        dnsServers: OcaString,
        linkUp: OcaBoolean,
        adapterSpeed: OcaUint64,
        parametersType: Ocp1IPParametersType,
        macAddress: (OcaUint8, OcaUint8, OcaUint8, OcaUint8, OcaUint8, OcaUint8),
        linkType: OcaNetworkLinkType
    ) {
        self.version = version
        self.hostname = hostname
        self.interfaceIndex = interfaceIndex
        self.subnetMaskLength = subnetMaskLength
        self.defaultGateway = defaultGateway
        self.dnsServers = dnsServers
        self.linkUp = linkUp
        self.adapterSpeed = adapterSpeed
        self.parametersType = parametersType
        self.macAddress = macAddress
        self.linkType = linkType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(OcaUint16.self, forKey: .version)
        hostname = try container.decode(OcaString.self, forKey: .hostname)
        interfaceIndex = try container.decode(OcaUint32.self, forKey: .interfaceIndex)
        subnetMaskLength = try container.decode(OcaUint8.self, forKey: .subnetMaskLength)
        defaultGateway = try container.decode(OcaString.self, forKey: .defaultGateway)
        dnsServers = try container.decode(OcaString.self, forKey: .dnsServers)
        linkUp = try container.decode(OcaBoolean.self, forKey: .linkUp)
        adapterSpeed = try container.decode(OcaUint64.self, forKey: .adapterSpeed)
        parametersType = try container.decode(Ocp1IPParametersType.self, forKey: .parametersType)
        var macAddressContainer = try container.nestedUnkeyedContainer(forKey: .macAddress)
        var macAddress: EUI48 = (0, 0, 0, 0, 0, 0)
        macAddress.0 = try macAddressContainer.decode(OcaUint8.self)
        macAddress.1 = try macAddressContainer.decode(OcaUint8.self)
        macAddress.2 = try macAddressContainer.decode(OcaUint8.self)
        macAddress.3 = try macAddressContainer.decode(OcaUint8.self)
        macAddress.4 = try macAddressContainer.decode(OcaUint8.self)
        macAddress.5 = try macAddressContainer.decode(OcaUint8.self)
        self.macAddress = macAddress
        linkType = try container.decode(OcaNetworkLinkType.self, forKey: .linkType)
    }

    public enum CodingKeys: CodingKey {
        case version
        case hostname
        case interfaceIndex
        case subnetMaskLength
        case defaultGateway
        case dnsServers
        case linkUp
        case adapterSpeed
        case parametersType
        case macAddress
        case linkType
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(hostname, forKey: .hostname)
        try container.encode(interfaceIndex, forKey: .interfaceIndex)
        try container.encode(subnetMaskLength, forKey: .subnetMaskLength)
        try container.encode(defaultGateway, forKey: .defaultGateway)
        try container.encode(dnsServers, forKey: .dnsServers)
        try container.encode(linkUp, forKey: .linkUp)
        try container.encode(adapterSpeed, forKey: .adapterSpeed)
        try container.encode(parametersType, forKey: .parametersType)
        var macAddressContainer = container.nestedUnkeyedContainer(forKey: .macAddress)
        try macAddressContainer.encode(macAddress.0)
        try macAddressContainer.encode(macAddress.1)
        try macAddressContainer.encode(macAddress.2)
        try macAddressContainer.encode(macAddress.3)
        try macAddressContainer.encode(macAddress.4)
        try macAddressContainer.encode(macAddress.5)
        try container.encode(linkType, forKey: .linkType)
    }
}

public struct OcaNetworkSystemInterfaceDescriptor: Codable, Sendable {
    public let systemInterfaceParameters: OcaBlob
    public let myNetworkAddress: OcaNetworkAddress
}

public typealias OcaAdaptationIdentifier = OcaString
