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

// Adaptation data structures defined by AES70-22 (Tables 2, 4, 8, 9, 16, 17, 21, 28, 29).

/// OcaNetworkInterface.CurrentAdaptationData
public struct MilanNetworkInterfaceAdaptationData: Ocp1TypedBlobRepresentable, Sendable, Equatable {
  public var timeSourceONo: OcaONo
  public var macAddress: OcaMACAddress

  public init(timeSourceONo: OcaONo, macAddress: OcaMACAddress) {
    self.timeSourceONo = timeSourceONo
    self.macAddress = macAddress
  }
}

/// Element of OcaNetworkInterface.Status.AdaptationData (an OcaList<MilanMSRPMapping>)
public struct MilanMSRPMapping: Codable, Sendable, Equatable {
  public var classID: OcaUint8
  public var priority: OcaUint8
  public var vlanID: OcaUint16

  public init(classID: OcaUint8, priority: OcaUint8, vlanID: OcaUint16) {
    self.classID = classID
    self.priority = priority
    self.vlanID = vlanID
  }
}

public typealias MilanNetworkInterfaceStatusAdaptationData = [MilanMSRPMapping]

/// OcaMediaTransportApplication.AdaptationData
public struct MilanMediaTransportAdaptationData: Ocp1TypedBlobRepresentable, Sendable, Equatable {
  public var entityID: OcaUint64
  public var protocolVersion: OcaUint32
  public var certificationVersion: OcaUint32
  public var redundancySupported: OcaBoolean
  public var audioUnits: [MilanAudioUnit]

  public init(
    entityID: OcaUint64,
    protocolVersion: OcaUint32,
    certificationVersion: OcaUint32,
    redundancySupported: OcaBoolean,
    audioUnits: [MilanAudioUnit]
  ) {
    self.entityID = entityID
    self.protocolVersion = protocolVersion
    self.certificationVersion = certificationVersion
    self.redundancySupported = redundancySupported
    self.audioUnits = audioUnits
  }
}

public struct MilanAudioUnit: Codable, Sendable, Equatable {
  public var name: OcaString
  public var clockONo: OcaONo
  public var rateSelectorONo: OcaONo
  public var inputOcaPortIndexRange: OcaInterval<OcaUint16>
  public var outputOcaPortIndexRange: OcaInterval<OcaUint16>

  public init(
    name: OcaString,
    clockONo: OcaONo,
    rateSelectorONo: OcaONo = OcaInvalidONo,
    inputOcaPortIndexRange: OcaInterval<OcaUint16>,
    outputOcaPortIndexRange: OcaInterval<OcaUint16>
  ) {
    self.name = name
    self.clockONo = clockONo
    self.rateSelectorONo = rateSelectorONo
    self.inputOcaPortIndexRange = inputOcaPortIndexRange
    self.outputOcaPortIndexRange = outputOcaPortIndexRange
  }
}

/// OcaMediaStreamEndpoint.IDExternal, and the remote endpoint ID of a session connection.
public struct MilanMediaStreamEndpointIDExternal: Ocp1TypedBlobRepresentable, Sendable, Equatable {
  public var entityID: OcaUint64
  public var streamIndex: OcaUint16

  public static let unbound = MilanMediaStreamEndpointIDExternal(entityID: 0, streamIndex: 0)

  public init(entityID: OcaUint64, streamIndex: OcaUint16) {
    self.entityID = entityID
    self.streamIndex = streamIndex
  }

  /// "<entity ID in hex>:<stream index>", the form used by controllers and tools.
  public init?(string: String) {
    let parts = string.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2,
          let entityID = OcaUint64(parts[0].hasPrefix("0x") ? String(parts[0].dropFirst(2)) : parts[0], radix: 16),
          let streamIndex = OcaUint16(parts[1])
    else { return nil }
    self.init(entityID: entityID, streamIndex: streamIndex)
  }

  public var description: String {
    "\(String(entityID, radix: 16)):\(streamIndex)"
  }
}

/// OcaMediaStreamEndpoint.AdaptationData; all zero while the endpoint is NotReady.
public struct MilanMediaStreamEndpointAdaptationData: Ocp1TypedBlobRepresentable, Sendable, Equatable {
  public var streamID: OcaUint64
  public var macAddress: OcaMACAddress
  public var vlanID: OcaUint16
  public var bufferLength: OcaUint32
  public var presentationTimeOffset: OcaUint32

  public static let notReady = MilanMediaStreamEndpointAdaptationData()

  public init(
    streamID: OcaUint64 = 0,
    macAddress: OcaMACAddress = .zero,
    vlanID: OcaUint16 = 0,
    bufferLength: OcaUint32 = 0,
    presentationTimeOffset: OcaUint32 = 0
  ) {
    self.streamID = streamID
    self.macAddress = macAddress
    self.vlanID = vlanID
    self.bufferLength = bufferLength
    self.presentationTimeOffset = presentationTimeOffset
  }

  /// SetEndpointAdaptationData requires the read-only fields to be zero (AES70-22 §7.3.6.5).
  public var hasOnlyWritableFields: Bool {
    streamID == 0 && macAddress == .zero && bufferLength == 0
  }
}

public typealias MilanEndpointCounterSetID = OcaMediaStreamEndpointCounterSetID

public enum MilanOcaSessionConfigSubstate: OcaUint8, Codable, Sendable, CaseIterable {
  case undefined = 0
  case sourceNotPresent = 1
  case probingSource = 2
  case reservationError = 3
}

/// OcaMediaTransportSessionStatus.AdaptationData
public struct MilanSessionStatusAdaptationData: Ocp1TypedBlobRepresentable, Sendable, Equatable {
  public var substate: MilanOcaSessionConfigSubstate
  public var acmpFailureCode: OcaUint8
  public var srpFailureBridgeID: OcaUint64
  public var srpFailureCode: OcaUint8
  public var msrpAccumulatedLatency: OcaUint32

  public init(
    substate: MilanOcaSessionConfigSubstate = .undefined,
    acmpFailureCode: OcaUint8 = 0,
    srpFailureBridgeID: OcaUint64 = 0,
    srpFailureCode: OcaUint8 = 0,
    msrpAccumulatedLatency: OcaUint32 = 0
  ) {
    self.substate = substate
    self.acmpFailureCode = acmpFailureCode
    self.srpFailureBridgeID = srpFailureBridgeID
    self.srpFailureCode = srpFailureCode
    self.msrpAccumulatedLatency = msrpAccumulatedLatency
  }
}

public enum MilanNetworkInterfaceCounterID {
  public static let linkUp = OcaNetworkInterfaceCounterID.linkUp
  public static let linkDown = OcaNetworkInterfaceCounterID.linkDown
  public static let framesTx = OcaNetworkInterfaceCounterID.framesTx
  public static let framesRx = OcaNetworkInterfaceCounterID.framesRx
  public static let rxCRCError = OcaNetworkInterfaceCounterID.rxCRCError
  public static let gptpGMChanged = OcaNetworkInterfaceCounterID.gptpGMChanged
}

public typealias MilanStreamInputCounterID = OcaMediaStreamInputEndpointCounterID
public typealias MilanStreamOutputCounterID = OcaMediaStreamOutputEndpointCounterID
