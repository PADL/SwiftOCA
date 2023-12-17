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

public typealias OcaMediaConnectorID = OcaUint16

public enum OcaMediaConnectorState: OcaUint8, Codable, Sendable {
    case stopped = 0
    case settingUp = 1
    case running = 2
    case paused = 3
    case fault = 4
}

public enum OcaMediaConnectorCommand: OcaUint8, Codable, Sendable {
    case none = 0
    case start = 1
    case pause = 2
}

public enum OcaMediaStreamCastMode: OcaUint8, Codable, Sendable {
    case none = 0
    case unicast = 1
    case multicast = 2
}

public typealias OcaMediaStreamParameters = OcaBlob

public typealias OcaMediaCodingSchemeID = OcaUint16

public struct OcaMediaCoding: Codable, Sendable {
    public let codingSchemeID: OcaMediaCodingSchemeID
    public let codecParameters: OcaString
    public let clockONO: OcaONo

    public init() {
        codingSchemeID = 0
        codecParameters = ""
        clockONO = OcaInvalidONo
    }

    public init(
        codingSchemeID: OcaMediaCodingSchemeID,
        codecParameters: OcaString,
        clockONO: OcaONo
    ) {
        self.codingSchemeID = codingSchemeID
        self.codecParameters = codecParameters
        self.clockONO = clockONO
    }
}

public struct OcaMediaConnection: Codable, Sendable {
    public let secure: OcaBoolean
    public let streamParameters: OcaMediaStreamParameters
    public let streamCastMode: OcaMediaStreamCastMode
    public let streamChannelCount: OcaUint16

    public init(
        secure: OcaBoolean,
        streamParameters: OcaMediaStreamParameters,
        streamCastMode: OcaMediaStreamCastMode,
        streamChannelCount: OcaUint16
    ) {
        self.secure = secure
        self.streamParameters = streamParameters
        self.streamCastMode = streamCastMode
        self.streamChannelCount = streamChannelCount
    }
}

public struct OcaMediaConnectorStatus: Codable, Sendable {
    public let connectorID: OcaMediaConnectorID
    public let state: OcaMediaConnectorState
    public let errorCode: OcaUint16

    public init(
        connectorID: OcaMediaConnectorID,
        state: OcaMediaConnectorState,
        errorCode: OcaUint16
    ) {
        self.connectorID = connectorID
        self.state = state
        self.errorCode = errorCode
    }
}

public struct OcaMediaSinkConnector: Codable, Sendable {
    public let IDInternal: OcaMediaConnectorID
    public let IDExternal: OcaString
    public let connection: OcaMediaConnection
    public let availableCodings: OcaList<OcaMediaCoding>
    public let pinCount: OcaUint16
    public let channelPinMap: OcaMultiMap<OcaUint16, OcaPortID>
    public let alignmentLevel: OcaDBFS
    public let alignmentGain: OcaDB
    public let currentCoding: OcaMediaCoding

    public init(
        IDInternal: OcaMediaConnectorID,
        IDExternal: OcaString,
        connection: OcaMediaConnection,
        availableCodings: OcaList<OcaMediaCoding>,
        pinCount: OcaUint16,
        channelPinMap: OcaMultiMap<OcaUint16, OcaPortID>,
        alignmentLevel: OcaDBFS,
        alignmentGain: OcaDB,
        currentCoding: OcaMediaCoding
    ) {
        self.IDInternal = IDInternal
        self.IDExternal = IDExternal
        self.connection = connection
        self.availableCodings = availableCodings
        self.pinCount = pinCount
        self.channelPinMap = channelPinMap
        self.alignmentLevel = alignmentLevel
        self.alignmentGain = alignmentGain
        self.currentCoding = currentCoding
    }
}

public struct OcaMediaSourceConnector: Codable, Sendable {
    public let IDInternal: OcaMediaConnectorID
    public let IDExternal: OcaString
    public let connection: OcaMediaConnection
    public let availableCodings: OcaList<OcaMediaCoding>
    public let pinCount: OcaUint16
    public let channelPinMap: OcaMultiMap<OcaUint16, OcaPortID>
    public let alignmentLevel: OcaDBFS
    public let currentCoding: OcaMediaCoding

    public init(
        IDInternal: OcaMediaConnectorID,
        IDExternal: OcaString,
        connection: OcaMediaConnection,
        availableCodings: OcaList<OcaMediaCoding>,
        pinCount: OcaUint16,
        channelPinMap: OcaMultiMap<OcaUint16, OcaPortID>,
        alignmentLevel: OcaDBFS,
        currentCoding: OcaMediaCoding
    ) {
        self.IDInternal = IDInternal
        self.IDExternal = IDExternal
        self.connection = connection
        self.availableCodings = availableCodings
        self.pinCount = pinCount
        self.channelPinMap = channelPinMap
        self.alignmentLevel = alignmentLevel
        self.currentCoding = currentCoding
    }
}
