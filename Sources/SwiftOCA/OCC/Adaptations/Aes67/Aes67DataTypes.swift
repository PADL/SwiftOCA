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

// Datatypes defined by AES70-21 (draft): Tables 7, 8, 9 and 19.

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
  public var submittedSDP: OcaSDPString
  public var activeSDP: OcaSDPString

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
    submittedSDP: OcaSDPString = "",
    activeSDP: OcaSDPString = ""
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
    self.submittedSDP = submittedSDP
    self.activeSDP = activeSDP
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

/// Element of Aes67StreamSourceListAgent.StreamSources.
public struct Aes67StreamSourceDescriptor: Codable, Sendable, Equatable {
  public var idExternal: OcaBlob
  public var direction: OcaIODirection
  public var alignmentLevel: OcaDBFS
  public var streamMode: OcaMediaStreamMode
  public var securityType: OcaSecurityType
  public var streamCastMode: OcaMediaStreamCastMode
  public var adaptationData: OcaAdaptationData
  public var sdpString: OcaSDPString
  public var sipString: OcaString
  public var infoSource: OcaBlob
  public var timestamp: OcaTime

  public init(
    idExternal: OcaBlob,
    direction: OcaIODirection,
    alignmentLevel: OcaDBFS = .nan,
    streamMode: OcaMediaStreamMode,
    securityType: OcaSecurityType = .none,
    streamCastMode: OcaMediaStreamCastMode,
    adaptationData: OcaAdaptationData = OcaBlob(),
    sdpString: OcaSDPString = "",
    sipString: OcaString = "",
    infoSource: OcaBlob = OcaBlob(),
    timestamp: OcaTime
  ) {
    self.idExternal = idExternal
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

/// AES70-21 counter IDs are aligned with the Milan ones.
public typealias Aes67EndpointCounterSetID = OcaMediaStreamEndpointCounterSetID
public typealias Aes67StreamInputCounterID = OcaMediaStreamInputEndpointCounterID
public typealias Aes67StreamOutputCounterID = OcaMediaStreamOutputEndpointCounterID
