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

public enum OcaMediaStreamEndpointState: OcaUint8, Codable, Sendable {
    case unknown = 0
    case notReady = 1
    case ready = 2
    case connected = 3
    case running = 4
    case errorHalt = 5
}

public enum OcaMediaStreamEndpointCommand: OcaUint8, Codable, Sendable {
    case none = 0
    case setReady = 1
    case connect = 2
    case connectAndStart = 3
    case disconnect = 4
    case stopAndDisconnect = 5
    case start = 6
    case stop = 7
}

public final class OcaMediaStreamEndpoint: Codable, Sendable {
    public let iDInternal: OcaMediaStreamEndpointID
    public let iDExternal: OcaBlob
    public let direction: OcaIODirection
    public let userLabel: OcaString
    public let networkAssignmentIDs: OcaList<OcaID16>
    public let streamModeCapabilityIDs: OcaList<OcaID16>
    public let clockONo: OcaONo
    public let channelMapDynamic: OcaBoolean
    public let channelMap: OcaMultiMap<OcaUint16, OcaPortID>
    public let alignmentLevel: OcaDBFS
    public let currentStreamMode: OcaMediaStreamMode
    public let securityType: OcaSecurityType
    public let streamCastMode: OcaMediaStreamCastMode
    public let adaptationData: OcaAdaptationData
    public let redundantSetID: OcaID16

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iDInternal = try container.decode(OcaMediaStreamEndpointID.self, forKey: .iDInternal)
        iDExternal = try container.decode(OcaBlob.self, forKey: .iDExternal)
        direction = try container.decode(OcaIODirection.self, forKey: .direction)
        userLabel = try container.decode(OcaString.self, forKey: .userLabel)
        networkAssignmentIDs = try container.decode([OcaID16].self, forKey: .networkAssignmentIDs)
        streamModeCapabilityIDs = try container.decode(
            [OcaID16].self,
            forKey: .streamModeCapabilityIDs
        )
        clockONo = try container.decode(OcaONo.self, forKey: .clockONo)
        channelMapDynamic = try container.decode(OcaBoolean.self, forKey: .channelMapDynamic)
        channelMap = try container.decode(
            OcaMultiMap<OcaUint16, OcaPortID>.self,
            forKey: .channelMap
        )
        alignmentLevel = try container.decode(OcaDBFS.self, forKey: .alignmentLevel)
        currentStreamMode = try container.decode(
            OcaMediaStreamMode.self,
            forKey: .currentStreamMode
        )
        securityType = try container.decode(OcaSecurityType.self, forKey: .securityType)
        streamCastMode = try container.decode(OcaMediaStreamCastMode.self, forKey: .streamCastMode)
        adaptationData = try container.decode(OcaAdaptationData.self, forKey: .adaptationData)
        redundantSetID = try container.decode(OcaID16.self, forKey: .redundantSetID)
    }
}

public struct OcaMediaStreamEndpointStatus: Codable, Sendable {
    public let state: OcaMediaStreamEndpointState
    public let errorCode: OcaUint16

    public init(state: OcaMediaStreamEndpointState, errorCode: OcaUint16) {
        self.state = state
        self.errorCode = errorCode
    }
}

public enum OcaMediaFrameFormat: OcaUint8, Codable, Sendable {
    case undefined = 0
    case rtp = 1
    case aaf = 2
    case crf_milan = 3
    case iec_61883_6 = 4
    case usb_audio_2_0 = 5
    case extensionPoint = 65
}

// MIME type example: audio/pcm;rate=48000;encoding=float;bits=32

public struct OcaMediaStreamMode: Codable, Sendable {
    public let frameFormat: OcaMediaFrameFormat
    public let encodingType: OcaMimeType
    public let samplingRate: OcaFrequency
    public let channelCount: OcaUint16
    public let packetTime: OcaTimeInterval
    public let mediaStreamEndpoint: OcaMediaStreamEndpoint

    public init(
        frameFormat: OcaMediaFrameFormat,
        encodingType: OcaMimeType,
        samplingRate: OcaFrequency,
        channelCount: OcaUint16,
        packetTime: OcaTimeInterval,
        mediaStreamEndpoint: OcaMediaStreamEndpoint
    ) {
        self.frameFormat = frameFormat
        self.encodingType = encodingType
        self.samplingRate = samplingRate
        self.channelCount = channelCount
        self.packetTime = packetTime
        self.mediaStreamEndpoint = mediaStreamEndpoint
    }
}

public struct OcaMediaStreamModeCapability: Codable, Sendable {
    public let id: OcaID16
    public let name: OcaString
    public let direction: OcaMediaStreamModeCapabilityDirection
    public let frameFormatList: [OcaMediaFrameFormat]
    public let encodingTypeList: [OcaMimeType]
    public let samplingRateList: [OcaFrequency]
    public let channelCountList: [OcaUint16]
    public let channelCountRange: Range<OcaUint16>
    public let packetTimeList: [OcaTimeInterval]
    public let packetTimeRange: Range<OcaTimeInterval>
    public let mediaStreamEndpoint: OcaMediaStreamEndpoint

    public init(
        id: OcaID16,
        name: OcaString,
        direction: OcaMediaStreamModeCapabilityDirection,
        frameFormatList: [OcaMediaFrameFormat],
        encodingTypeList: [OcaMimeType],
        samplingRateList: [OcaFrequency],
        channelCountList: [OcaUint16],
        channelCountRange: Range<OcaUint16>,
        packetTimeList: [OcaTimeInterval],
        packetTimeRange: Range<OcaTimeInterval>,
        mediaStreamEndpoint: OcaMediaStreamEndpoint
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
        self.mediaStreamEndpoint = mediaStreamEndpoint
    }
}

public enum OcaMediaStreamModeCapabilityDirection: OcaUint8, Codable, Sendable {
    case input = 1
    case output = 2
}

public struct OcaMediaTransportSession: Codable, Sendable {
    public typealias ConnectionStateMap =
        [OcaMediaTransportSessionConnectionID: OcaMediaTransportSessionConnectionState]

    public let idInternal: OcaMediaTransportSessionID
    public let idExternal: OcaBlob
    public let userLabel: OcaString
    public let streamingEnabled: OcaBoolean
    public let adaptationData: OcaAdaptationData
    public let connections: [OcaMediaTransportSessionConnection]
    public let connectionStates: ConnectionStateMap

    public init(
        idInternal: OcaMediaTransportSessionID,
        idExternal: OcaBlob,
        userLabel: OcaString,
        streamingEnabled: OcaBoolean,
        adaptationData: OcaAdaptationData,
        connections: [OcaMediaTransportSessionConnection],
        connectionStates: ConnectionStateMap
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

public struct OcaMediaTransportSessionConnection: Codable, Sendable {
    public let id: OcaMediaTransportSessionConnectionID
    public let localEndpointID: OcaMediaStreamEndpointID
    public let remoteEndpointID: OcaBlob
    /*
     public let mediaTransportSession: OcaMediaTransportSession
     */

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

public typealias OcaMediaTransportSessionConnectionID = OcaUint32

public struct OcaMediaTransportSessionConnectionState: Codable, Sendable {
    public let localEndpointState: OcaMediaStreamEndpointState
    public let remoteEndpointState: OcaMediaStreamEndpointState

    public init(
        localEndpointState: OcaMediaStreamEndpointState,
        remoteEndpointState: OcaMediaStreamEndpointState
    ) {
        self.localEndpointState = localEndpointState
        self.remoteEndpointState = remoteEndpointState
    }
}

public typealias OcaMediaTransportSessionID = OcaUint32

public enum OcaMediaTransportSessionState: OcaUint8, Codable, Sendable {
    case unconfigured = 1
    case configured = 2
    case connectedNotStreaming = 3
    case connectedStreaming = 4
    case error = 5
}

public struct OcaMediaTransportSessionStatus: Codable, Sendable {
    public let state: OcaMediaTransportSessionState
    public let adaptationData: OcaBlob

    public init(state: OcaMediaTransportSessionState, adaptationData: OcaBlob) {
        self.state = state
        self.adaptationData = adaptationData
    }
}

public struct OcaMediaTransportTimingParameters: Codable, Sendable {
    public let minReceiveBufferCapacity: OcaTimeInterval
    public let maxReceiveBufferCapacity: OcaTimeInterval
    public let transmissionTimeVariation: OcaTimeInterval

    public init(
        minReceiveBufferCapacity: OcaTimeInterval,
        maxReceiveBufferCapacity: OcaTimeInterval,
        transmissionTimeVariation: OcaTimeInterval
    ) {
        self.minReceiveBufferCapacity = minReceiveBufferCapacity
        self.maxReceiveBufferCapacity = maxReceiveBufferCapacity
        self.transmissionTimeVariation = transmissionTimeVariation
    }
}
