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

// Datatypes defined by AES70-23 (draft): Tables 3-10. The OcaChannelEndpoint family is
// unprefixed because the draft expects it to migrate into Core CM4.

public enum OcaChannelEndpointConnectionState: OcaUint8, Codable, Sendable, CaseIterable {
  case notConfigured = 0
  case connecting = 1
  case running = 2
  case connectionFail = 3
}

/// A channel-based routing endpoint (Dante channel).
public struct OcaChannelEndpoint: Codable, Sendable, Equatable {
  public var idExternal: OcaBlob
  public var direction: OcaIODirection
  public var connectionState: OcaChannelEndpointConnectionState
  public var autoRun: OcaBoolean
  public var fault: OcaBoolean
  public var security: OcaSecurityType
  public var streamCastMode: OcaMediaStreamCastMode
  public var adaptationData: OcaAdaptationData
  public var portMap: [OcaPortID]

  public init(
    idExternal: OcaBlob,
    direction: OcaIODirection,
    connectionState: OcaChannelEndpointConnectionState = .notConfigured,
    autoRun: OcaBoolean = true,
    fault: OcaBoolean = false,
    security: OcaSecurityType = .none,
    streamCastMode: OcaMediaStreamCastMode = .none,
    adaptationData: OcaAdaptationData = OcaBlob(),
    portMap: [OcaPortID] = []
  ) {
    self.idExternal = idExternal
    self.direction = direction
    self.connectionState = connectionState
    self.autoRun = autoRun
    self.fault = fault
    self.security = security
    self.streamCastMode = streamCastMode
    self.adaptationData = adaptationData
    self.portMap = portMap
  }
}

/// A Dante channel reference, written on the wire as "<channel>@<device>".
public struct DanteChannelAddress: Codable, Sendable, Equatable {
  public var device: OcaString
  public var channel: OcaString

  public init(device: OcaString = "", channel: OcaString = "") {
    self.device = device
    self.channel = channel
  }

  public init?(string: String) {
    let parts = string.split(separator: "@", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return nil }
    self.init(device: parts[1], channel: parts[0])
  }

  public var description: String {
    channel.isEmpty && device.isEmpty ? "" : "\(channel)@\(device)"
  }
}

public enum DanteRxSubscriptionStatus: OcaUint8, Codable, Sendable, CaseIterable {
  case none = 0
  case subscribedToMulticastFlow = 1
  case subscribedToUnicastFlow = 2
  case unresolved = 3
  case badFormat = 4
  case noTxResources = 5
  case noRxResources = 6
  case permissionError = 7
}

public enum DanteMediaProtocol: OcaUint8, Codable, Sendable, CaseIterable {
  case none = 0
  case atp = 1
  case aes67 = 2
  case smpteST2110 = 3
}

/// OcaChannelEndpoint.AdaptationData; the receive-side fields are unused for transmit channels.
public struct DanteChannelEndpointAdaptationData: Ocp1TypedBlobRepresentable, Sendable, Equatable {
  public var remoteAddress: DanteChannelAddress
  public var subscriptionStatus: DanteRxSubscriptionStatus
  public var channelMute: OcaMuteState
  public var latency: OcaFloat32
  public var mediaProtocol: DanteMediaProtocol
  public var streamEndpointID: OcaMediaStreamEndpointID

  public init(
    remoteAddress: DanteChannelAddress = DanteChannelAddress(),
    subscriptionStatus: DanteRxSubscriptionStatus = .none,
    channelMute: OcaMuteState = .unmuted,
    latency: OcaFloat32 = 0,
    mediaProtocol: DanteMediaProtocol = .none,
    streamEndpointID: OcaMediaStreamEndpointID = 0
  ) {
    self.remoteAddress = remoteAddress
    self.subscriptionStatus = subscriptionStatus
    self.channelMute = channelMute
    self.latency = latency
    self.mediaProtocol = mediaProtocol
    self.streamEndpointID = streamEndpointID
  }
}

public enum DanteChannelEndpointOperatingState: OcaUint8, Codable, Sendable, CaseIterable {
  case none = 0
  case noSignal = 1
  case active = 2
  case overload = 3
}

/// Element of DanteOcaMediaTransportApplication.ChannelEndpointOperatingStates.
public struct DanteChannelEndpointOperatingStateData: Ocp1TypedBlobRepresentable, Sendable,
  Equatable
{
  public var state: DanteChannelEndpointOperatingState

  public init(state: DanteChannelEndpointOperatingState) {
    self.state = state
  }
}
