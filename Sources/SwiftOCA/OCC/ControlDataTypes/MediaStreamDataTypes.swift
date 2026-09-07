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

public typealias OcaMediaStreamEndpointID = OcaUint32

public enum OcaMediaStreamEndpointState: OcaUint8, Codable, Sendable, CaseIterable {
  case unknown = 0
  case notReady = 1
  case ready = 2
  case connected = 3
  case running = 4
  case errorHalt = 5
}

public enum OcaMediaStreamEndpointCommand: OcaUint8, Codable, Sendable, CaseIterable {
  case none = 0
  case setReady = 1
  case connect = 2
  case connectAndStart = 3
  case disconnect = 4
  case stopAndDisconnect = 5
  case start = 6
  case stop = 7
}

public struct OcaMediaStreamEndpoint: Codable, Sendable, Equatable {
  public var idInternal: OcaMediaStreamEndpointID
  public var idExternal: OcaBlob
  public var direction: OcaIODirection
  public var userLabel: OcaString
  public var networkAssignmentIDs: OcaList<OcaID16>
  public var streamModeCapabilityIDs: OcaList<OcaID16>
  public var clockONo: OcaONo
  public var channelMapDynamic: OcaBoolean
  public var channelMap: OcaMultiMap<OcaUint16, OcaPortID>
  public var alignmentLevel: OcaDBFS
  public var currentStreamMode: OcaMediaStreamMode
  public var securityType: OcaSecurityType
  public var streamCastMode: OcaMediaStreamCastMode
  public var adaptationData: OcaAdaptationData
  public var redundantSetID: OcaID16

  public init(
    idInternal: OcaMediaStreamEndpointID,
    idExternal: OcaBlob = OcaBlob(),
    direction: OcaIODirection,
    userLabel: OcaString = "",
    networkAssignmentIDs: OcaList<OcaID16> = [],
    streamModeCapabilityIDs: OcaList<OcaID16> = [],
    clockONo: OcaONo = OcaInvalidONo,
    channelMapDynamic: OcaBoolean = false,
    channelMap: OcaMultiMap<OcaUint16, OcaPortID> = [:],
    alignmentLevel: OcaDBFS = .nan,
    currentStreamMode: OcaMediaStreamMode = .undefined,
    securityType: OcaSecurityType = .none,
    streamCastMode: OcaMediaStreamCastMode = .none,
    adaptationData: OcaAdaptationData = OcaBlob(),
    redundantSetID: OcaID16 = 0
  ) {
    self.idInternal = idInternal
    self.idExternal = idExternal
    self.direction = direction
    self.userLabel = userLabel
    self.networkAssignmentIDs = networkAssignmentIDs
    self.streamModeCapabilityIDs = streamModeCapabilityIDs
    self.clockONo = clockONo
    self.channelMapDynamic = channelMapDynamic
    self.channelMap = channelMap
    self.alignmentLevel = alignmentLevel
    self.currentStreamMode = currentStreamMode
    self.securityType = securityType
    self.streamCastMode = streamCastMode
    self.adaptationData = adaptationData
    self.redundantSetID = redundantSetID
  }

  // AlignmentLevel is NaN when unused, so compare it bitwise.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.idInternal == rhs.idInternal &&
      lhs.idExternal == rhs.idExternal &&
      lhs.direction == rhs.direction &&
      lhs.userLabel == rhs.userLabel &&
      lhs.networkAssignmentIDs == rhs.networkAssignmentIDs &&
      lhs.streamModeCapabilityIDs == rhs.streamModeCapabilityIDs &&
      lhs.clockONo == rhs.clockONo &&
      lhs.channelMapDynamic == rhs.channelMapDynamic &&
      lhs.channelMap == rhs.channelMap &&
      lhs.alignmentLevel.bitPattern == rhs.alignmentLevel.bitPattern &&
      lhs.currentStreamMode == rhs.currentStreamMode &&
      lhs.securityType == rhs.securityType &&
      lhs.streamCastMode == rhs.streamCastMode &&
      lhs.adaptationData == rhs.adaptationData &&
      lhs.redundantSetID == rhs.redundantSetID
  }
}

public struct OcaMediaStreamEndpointStatus: Codable, Sendable, Equatable {
  public var state: OcaMediaStreamEndpointState
  public var errorCode: OcaUint16

  public init(state: OcaMediaStreamEndpointState, errorCode: OcaUint16 = 0) {
    self.state = state
    self.errorCode = errorCode
  }
}

public typealias OcaMediaStreamEndpointStatusMap =
  OcaMap<OcaMediaStreamEndpointID, OcaMediaStreamEndpointStatus>

public enum OcaMediaFrameFormat: OcaUint8, Codable, Sendable, CaseIterable {
  case undefined = 0
  case rtp = 1
  case aaf = 2
  case crf_milan = 3
  case iec_61883_6 = 4
  case usb_audio_2_0 = 5
  case extensionPoint = 65
}

public struct OcaMediaStreamMode: Codable, Sendable, Hashable {
  public var frameFormat: OcaMediaFrameFormat
  public var encodingType: OcaMimeType
  public var samplingRate: OcaFrequency
  public var channelCount: OcaUint16
  public var packetTime: OcaTimeInterval

  public init(
    frameFormat: OcaMediaFrameFormat,
    encodingType: OcaMimeType,
    samplingRate: OcaFrequency,
    channelCount: OcaUint16,
    packetTime: OcaTimeInterval
  ) {
    self.frameFormat = frameFormat
    self.encodingType = encodingType
    self.samplingRate = samplingRate
    self.channelCount = channelCount
    self.packetTime = packetTime
  }

  public static let undefined = OcaMediaStreamMode(
    frameFormat: .undefined,
    encodingType: "",
    samplingRate: 0,
    channelCount: 0,
    packetTime: 0
  )
}

public struct OcaMediaStreamModeCapability: Codable, Sendable, Equatable {
  public var id: OcaID16
  public var name: OcaString
  public var direction: OcaMediaStreamModeCapabilityDirection
  public var frameFormatList: OcaList<OcaMediaFrameFormat>
  public var encodingTypeList: OcaList<OcaMimeType>
  public var samplingRateList: OcaList<OcaFrequency>
  public var channelCountList: OcaList<OcaUint16>
  public var channelCountRange: OcaInterval<OcaUint16>
  public var packetTimeList: OcaList<OcaTimeInterval>
  public var packetTimeRange: OcaInterval<OcaTimeInterval>

  public init(
    id: OcaID16,
    name: OcaString,
    direction: OcaMediaStreamModeCapabilityDirection,
    frameFormatList: OcaList<OcaMediaFrameFormat>,
    encodingTypeList: OcaList<OcaMimeType>,
    samplingRateList: OcaList<OcaFrequency>,
    channelCountList: OcaList<OcaUint16>,
    channelCountRange: OcaInterval<OcaUint16>,
    packetTimeList: OcaList<OcaTimeInterval>,
    packetTimeRange: OcaInterval<OcaTimeInterval>
  ) {
    self.id = id
    self.name = name
    self.direction = direction
    self.frameFormatList = frameFormatList
    self.encodingTypeList = encodingTypeList
    self.samplingRateList = samplingRateList
    self.channelCountList = channelCountList
    self.channelCountRange = channelCountRange
    self.packetTimeList = packetTimeList
    self.packetTimeRange = packetTimeRange
  }
}

/// Bitset: bit 0 = input, bit 1 = output.
public struct OcaMediaStreamModeCapabilityDirection: OptionSet, Codable, Sendable, Hashable {
  public let rawValue: OcaUint16

  public init(rawValue: OcaUint16) {
    self.rawValue = rawValue
  }

  public static let input = OcaMediaStreamModeCapabilityDirection(rawValue: 1 << 0)
  public static let output = OcaMediaStreamModeCapabilityDirection(rawValue: 1 << 1)
}

public typealias OcaMediaTransportSessionID = OcaUint32
public typealias OcaMediaTransportSessionConnectionID = OcaUint32

public struct OcaMediaTransportSession: Codable, Sendable, Equatable {
  public typealias ConnectionStateMap =
    [OcaMediaTransportSessionConnectionID: OcaMediaTransportSessionConnectionState]

  public var idInternal: OcaMediaTransportSessionID
  public var idExternal: OcaBlob
  public var userLabel: OcaString
  public var streamingEnabled: OcaBoolean
  public var adaptationData: OcaAdaptationData
  public var connections: [OcaMediaTransportSessionConnection]
  public var connectionStates: ConnectionStateMap

  public init(
    idInternal: OcaMediaTransportSessionID,
    idExternal: OcaBlob = OcaBlob(),
    userLabel: OcaString = "",
    streamingEnabled: OcaBoolean = false,
    adaptationData: OcaAdaptationData = OcaBlob(),
    connections: [OcaMediaTransportSessionConnection] = [],
    connectionStates: ConnectionStateMap = [:]
  ) {
    self.idInternal = idInternal
    self.idExternal = idExternal
    self.userLabel = userLabel
    self.streamingEnabled = streamingEnabled
    self.adaptationData = adaptationData
    self.connections = connections
    self.connectionStates = connectionStates
  }
}

public struct OcaMediaTransportSessionConnection: Codable, Sendable, Equatable {
  public var id: OcaMediaTransportSessionConnectionID
  public var localEndpointID: OcaMediaStreamEndpointID
  public var remoteEndpointID: OcaBlob

  public init(
    id: OcaMediaTransportSessionConnectionID,
    localEndpointID: OcaMediaStreamEndpointID,
    remoteEndpointID: OcaBlob
  ) {
    self.id = id
    self.localEndpointID = localEndpointID
    self.remoteEndpointID = remoteEndpointID
  }
}

public struct OcaMediaTransportSessionConnectionState: Codable, Sendable, Equatable {
  public var localEndpointState: OcaMediaStreamEndpointState
  public var remoteEndpointState: OcaMediaStreamEndpointState

  public init(
    localEndpointState: OcaMediaStreamEndpointState,
    remoteEndpointState: OcaMediaStreamEndpointState
  ) {
    self.localEndpointState = localEndpointState
    self.remoteEndpointState = remoteEndpointState
  }
}

public enum OcaMediaTransportSessionState: OcaUint8, Codable, Sendable, CaseIterable {
  case unconfigured = 1
  case configured = 2
  case connectedNotStreaming = 3
  case connectedStreaming = 4
  case error = 5
}

public struct OcaMediaTransportSessionStatus: Codable, Sendable, Equatable {
  public var state: OcaMediaTransportSessionState
  public var adaptationData: OcaAdaptationData

  public init(state: OcaMediaTransportSessionState, adaptationData: OcaAdaptationData = OcaBlob()) {
    self.state = state
    self.adaptationData = adaptationData
  }
}

public typealias OcaMediaTransportSessionStatusMap =
  OcaMap<OcaMediaTransportSessionID, OcaMediaTransportSessionStatus>

public struct OcaMediaTransportTimingParameters: Codable, Sendable, Equatable {
  public var minReceiveBufferCapacity: OcaTimeInterval
  public var maxReceiveBufferCapacity: OcaTimeInterval
  public var transmissionTimeVariation: OcaTimeInterval

  public init(
    minReceiveBufferCapacity: OcaTimeInterval = 0,
    maxReceiveBufferCapacity: OcaTimeInterval = 0,
    transmissionTimeVariation: OcaTimeInterval = 0
  ) {
    self.minReceiveBufferCapacity = minReceiveBufferCapacity
    self.maxReceiveBufferCapacity = maxReceiveBufferCapacity
    self.transmissionTimeVariation = transmissionTimeVariation
  }
}
