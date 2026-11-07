//
// Copyright (c) 2026 PADL Software Pty Ltd
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

// Datatypes defined by AES70-21 (draft 2026-10-29): Tables 7, 8, 17 and 18 to 21, and
// Aes67MediaIDType (§10.2.4).

/// Aes67StreamTransmissionCapabilities (OcaBitSet16)
public struct Aes67StreamTransmissionCapabilities: OptionSet, Codable, Sendable, Hashable {
  public let rawValue: OcaBitSet16

  public init(rawValue: OcaBitSet16) {
    self.rawValue = rawValue
  }

  public static let unicastCapable = Aes67StreamTransmissionCapabilities(rawValue: 1 << 0)
  public static let multicastCapable = Aes67StreamTransmissionCapabilities(rawValue: 1 << 1)
  public static let insecureCapable = Aes67StreamTransmissionCapabilities(rawValue: 1 << 2)
  public static let defaultSecurityCapable = Aes67StreamTransmissionCapabilities(rawValue: 1 << 3)
}

/// What kind of identifier Aes67EndpointAdaptationData.MediaID and ConfigureEndpointFromSDP's
/// MediaID are (AES70-21 §10.2.4). The draft gives no width; it is an OcaUint8, as AES70-3
/// marshals its enumerations.
public enum Aes67MediaIDType: OcaUint8, Codable, Sendable, CaseIterable {
  /// No identifier: the SDP has one media description, whatever its identity.
  case none = 0
  /// The media description's position in the SDP, 1-based, in decimal.
  case ordinal = 1
  /// Its `a=label` value (RFC 4574).
  case label = 2
  /// Its `a=mid` value (RFC 5888).
  case mid = 3
  /// Its `m=` UDP port, in decimal.
  case portNo = 4
  /// `<IPv4 address>:<port>` of its connection address and `m=` port.
  case transportAddress4 = 5
  /// `[<IPv6 address>]:<port>`; reserved, AES67 has no IPv6.
  case transportAddress6 = 6
}

/// IP parameters of an endpoint on one network assignment. DSCP and COS of -1 leave the
/// choice to the device.
public struct Aes67EndpointIPParameters: Codable, Sendable, Equatable {
  public var networkAssignmentID: OcaID16
  public var sourceAddress: OcaString
  public var destinationAddress: OcaString
  public var timeToLive: OcaUint8
  public var sourcePort: OcaUint16
  public var destinationPort: OcaUint16
  public var dscp: OcaInt8
  public var cos: OcaInt8

  public init(
    networkAssignmentID: OcaID16,
    sourceAddress: OcaString = "",
    destinationAddress: OcaString = "",
    timeToLive: OcaUint8 = 0,
    sourcePort: OcaUint16 = 0,
    destinationPort: OcaUint16 = 0,
    dscp: OcaInt8 = -1,
    cos: OcaInt8 = -1
  ) {
    self.networkAssignmentID = networkAssignmentID
    self.sourceAddress = sourceAddress
    self.destinationAddress = destinationAddress
    self.timeToLive = timeToLive
    self.sourcePort = sourcePort
    self.destinationPort = destinationPort
    self.dscp = dscp
    self.cos = cos
  }
}

/// OcaMediaStreamEndpoint.AdaptationData for AES67 endpoints.
public struct Aes67EndpointAdaptationData: Ocp1TypedBlobRepresentable, Sendable, Equatable {
  public var ipParameters: [Aes67EndpointIPParameters]
  public var payloadType: OcaUint8
  public var rtpTimestampOffset: OcaUint32
  public var timeSkewMaxTolerated: OcaTimeInterval
  public var remoteEndpointName: OcaBlob
  public var remoteControlType: OcaString
  public var transmissionCapabilities: Aes67StreamTransmissionCapabilities
  public var presentationTimeOffset: OcaTimeInterval
  public var mediaInfo: OcaString
  /// Set by ConfigureEndpointFromSDP.
  public var activeSDP: OcaSDPString
  /// The kind of `mediaID`. Set by ConfigureEndpointFromSDP.
  public var mediaIDType: Aes67MediaIDType
  /// The media description of `activeSDP` in effect, as `mediaIDType` identifies it.
  /// Set by ConfigureEndpointFromSDP.
  public var mediaID: OcaString

  public init(
    ipParameters: [Aes67EndpointIPParameters] = [],
    payloadType: OcaUint8 = 0,
    rtpTimestampOffset: OcaUint32 = 0,
    timeSkewMaxTolerated: OcaTimeInterval = 0,
    remoteEndpointName: OcaBlob = OcaBlob(),
    remoteControlType: OcaString = "",
    transmissionCapabilities: Aes67StreamTransmissionCapabilities = [],
    presentationTimeOffset: OcaTimeInterval = 0,
    mediaInfo: OcaString = "",
    activeSDP: OcaSDPString = "",
    mediaIDType: Aes67MediaIDType = .none,
    mediaID: OcaString = ""
  ) {
    self.ipParameters = ipParameters
    self.payloadType = payloadType
    self.rtpTimestampOffset = rtpTimestampOffset
    self.timeSkewMaxTolerated = timeSkewMaxTolerated
    self.remoteEndpointName = remoteEndpointName
    self.remoteControlType = remoteControlType
    self.transmissionCapabilities = transmissionCapabilities
    self.presentationTimeOffset = presentationTimeOffset
    self.mediaInfo = mediaInfo
    self.activeSDP = activeSDP
    self.mediaIDType = mediaIDType
    self.mediaID = mediaID
  }
}

/// Values of Aes67EndpointAdaptationData.RemoteControlType; "AES" prefixes are reserved.
public enum Aes67RemoteControlType {
  public static let aes70_21: OcaString = "AES70-21"
  public static let aes70: OcaString = "AES70"
  public static let sip: OcaString = "SIP"
  public static let nmos: OcaString = "NMOS"
  public static let none: OcaString = "NONE"
}

/// Element of Aes67StreamEndpointDescriptor.Addresses.
public struct Aes67StreamTransportAddress: Codable, Sendable, Equatable {
  /// OcaVariant<OcaIP4Address, OcaIP6Address>. AES70-3 has no OCP.1 marshalling rule for
  /// OcaVariant; provisionally, an OcaUint8 index of the alternative precedes the value.
  public enum IPAddress: Codable, Sendable, Hashable {
    case ip4(OcaIP4Address)
    case ip6(OcaIP6Address)

    public init(from decoder: Decoder) throws {
      var container = try decoder.unkeyedContainer()
      switch try container.decode(OcaUint8.self) {
      case 0: self = try .ip4(container.decode(OcaIP4Address.self))
      case 1: self = try .ip6(container.decode(OcaIP6Address.self))
      case let index:
        throw DecodingError.dataCorrupted(DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "OcaVariant alternative \(index) is not an IP address"
        ))
      }
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.unkeyedContainer()
      switch self {
      case let .ip4(address):
        try container.encode(0 as OcaUint8)
        try container.encode(address)
      case let .ip6(address):
        try container.encode(1 as OcaUint8)
        try container.encode(address)
      }
    }
  }

  public var ipAddress: IPAddress
  public var port: OcaUint16

  public init(ipAddress: IPAddress, port: OcaUint16) {
    self.ipAddress = ipAddress
    self.port = port
  }
}

/// Element of Aes67StreamEndpointRegistry.Registry.
public struct Aes67StreamEndpointDescriptor: Codable, Sendable, Equatable {
  public var idExternal: OcaBlob
  public var addresses: [Aes67StreamTransportAddress]
  public var direction: OcaIODirection
  public var alignmentLevel: OcaDBFS
  public var streamMode: OcaMediaStreamMode
  public var securityType: OcaSecurityType
  public var streamCastMode: OcaMediaStreamCastMode
  public var adaptationData: OcaTypedBlob<Aes67EndpointAdaptationData>
  public var sdpString: OcaSDPString
  public var sipString: OcaString
  public var infoSource: OcaBlob
  public var timestamp: OcaTime

  public init(
    idExternal: OcaBlob,
    addresses: [Aes67StreamTransportAddress],
    direction: OcaIODirection,
    alignmentLevel: OcaDBFS = .nan,
    streamMode: OcaMediaStreamMode,
    securityType: OcaSecurityType = .none,
    streamCastMode: OcaMediaStreamCastMode,
    adaptationData: OcaTypedBlob<Aes67EndpointAdaptationData> = OcaTypedBlob(),
    sdpString: OcaSDPString = "",
    sipString: OcaString = "",
    infoSource: OcaBlob = OcaBlob(),
    timestamp: OcaTime
  ) {
    self.idExternal = idExternal
    self.addresses = addresses
    self.direction = direction
    self.alignmentLevel = alignmentLevel
    self.streamMode = streamMode
    self.securityType = securityType
    self.streamCastMode = streamCastMode
    self.adaptationData = adaptationData
    self.sdpString = sdpString
    self.sipString = sipString
    self.infoSource = infoSource
    self.timestamp = timestamp
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.idExternal == rhs.idExternal &&
      lhs.addresses == rhs.addresses &&
      lhs.direction == rhs.direction &&
      lhs.alignmentLevel.bitPattern == rhs.alignmentLevel.bitPattern &&
      lhs.streamMode == rhs.streamMode &&
      lhs.securityType == rhs.securityType &&
      lhs.streamCastMode == rhs.streamCastMode &&
      lhs.adaptationData == rhs.adaptationData &&
      lhs.sdpString == rhs.sdpString &&
      lhs.sipString == rhs.sipString &&
      lhs.infoSource == rhs.infoSource &&
      lhs.timestamp == rhs.timestamp
  }
}

/// Parameters of Aes67StreamEndpointRegistry's RegistryChanged event.
public struct Aes67RegistryChangedEventData: Codable, Sendable, Equatable {
  public let changeType: OcaPropertyChangeType
  public let entry: Aes67StreamEndpointDescriptor

  public init(changeType: OcaPropertyChangeType, entry: Aes67StreamEndpointDescriptor) {
    self.changeType = changeType
    self.entry = entry
  }
}

/// Parameters of Aes67StreamEndpointRegistry's RegistryRebuilt event.
public struct Aes67RegistryRebuiltEventData: Codable, Sendable, Equatable {
  public let registry: [Aes67StreamEndpointDescriptor]

  public init(registry: [Aes67StreamEndpointDescriptor]) {
    self.registry = registry
  }
}

/// AES70-21 counter IDs are aligned with the Milan ones.
public typealias Aes67EndpointCounterSetID = OcaMediaStreamEndpointCounterSetID
public typealias Aes67StreamInputCounterID = OcaMediaStreamInputEndpointCounterID
public typealias Aes67StreamOutputCounterID = OcaMediaStreamOutputEndpointCounterID
