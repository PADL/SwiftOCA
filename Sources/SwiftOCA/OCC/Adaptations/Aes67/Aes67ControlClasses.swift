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

/// Controller proxy for AES70-21's Aes67OcaMediaTransportApplication (1.7.1.A.2100).
/// The SDP and registry method IDs are "TBD" in the draft; 4.3-4.7 are provisional.
open class Aes67OcaMediaTransportApplication: OcaMediaTransportApplication, @unchecked Sendable {
  override open class var classID: OcaClassID { Aes67Adaptation.mediaTransportApplicationClassID }

  public struct EndpointStreamModeParameters: OcaParametersReflectable {
    public let endpointID: OcaMediaStreamEndpointID
    public let streamMode: OcaMediaStreamMode

    public init(endpointID: OcaMediaStreamEndpointID, streamMode: OcaMediaStreamMode) {
      self.endpointID = endpointID
      self.streamMode = streamMode
    }
  }

  public struct EndpointDelayConstraints: OcaParametersReflectable, Equatable {
    public let bufferingTimeRange: OcaInterval<OcaTimeInterval>
    public let processingTimeRange: OcaInterval<OcaTimeInterval>

    public init(
      bufferingTimeRange: OcaInterval<OcaTimeInterval>,
      processingTimeRange: OcaInterval<OcaTimeInterval>
    ) {
      self.bufferingTimeRange = bufferingTimeRange
      self.processingTimeRange = processingTimeRange
    }
  }

  public struct PresentationTimeOffsetConstraints: OcaParametersReflectable, Equatable {
    public let range: OcaInterval<OcaTimeInterval>
    public let list: [OcaTimeInterval]

    public init(range: OcaInterval<OcaTimeInterval>, list: [OcaTimeInterval]) {
      self.range = range
      self.list = list
    }
  }

  public struct SubmitSDPParameters: OcaParametersReflectable {
    public let endpointID: OcaMediaStreamEndpointID
    public let sdp: OcaSDPString

    public init(endpointID: OcaMediaStreamEndpointID, sdp: OcaSDPString) {
      self.endpointID = endpointID
      self.sdp = sdp
    }
  }

  /// ONo of the Aes67StreamSourceListAgent, or zero when there is no registry.
  @OcaProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.6"),
    setMethodID: OcaMethodID("4.7")
  )
  public var streamSourceRegistryONo: OcaProperty<OcaONo>.PropertyValue

  public func getEndpointDelayConstraints(
    _ endpointID: OcaMediaStreamEndpointID,
    streamMode: OcaMediaStreamMode
  ) async throws -> EndpointDelayConstraints {
    try await sendCommandRrq(
      methodID: OcaMethodID("4.1"),
      parameters: EndpointStreamModeParameters(endpointID: endpointID, streamMode: streamMode)
    )
  }

  public func getPresentationTimeOffsetConstraints(
    _ endpointID: OcaMediaStreamEndpointID,
    streamMode: OcaMediaStreamMode
  ) async throws -> PresentationTimeOffsetConstraints {
    try await sendCommandRrq(
      methodID: OcaMethodID("4.2"),
      parameters: EndpointStreamModeParameters(endpointID: endpointID, streamMode: streamMode)
    )
  }

  public func submitSDP(_ endpointID: OcaMediaStreamEndpointID, sdp: OcaSDPString) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("4.3"),
      parameters: SubmitSDPParameters(endpointID: endpointID, sdp: sdp)
    )
  }

  public func getSubmittedSDP(_ endpointID: OcaMediaStreamEndpointID) async throws -> OcaSDPString {
    try await sendCommandRrq(methodID: OcaMethodID("4.4"), parameters: endpointID)
  }

  public func getActiveSDP(_ endpointID: OcaMediaStreamEndpointID) async throws -> OcaSDPString {
    try await sendCommandRrq(methodID: OcaMethodID("4.5"), parameters: endpointID)
  }
}

/// Controller proxy for AES70-21's Aes67OcaMediaTransportSessionAgent (1.2.20.A.2101),
/// which adds SIP parameter access. Method IDs 4.1-4.4 are provisional.
open class Aes67OcaMediaTransportSessionAgent: OcaMediaTransportSessionAgent, @unchecked Sendable {
  override open class var classID: OcaClassID { Aes67Adaptation.mediaTransportSessionAgentClassID }

  public struct SIPParameterRecordParameters: OcaParametersReflectable {
    public let sessionID: OcaMediaTransportSessionID
    public let parameterRecord: OcaParameterRecord

    public init(sessionID: OcaMediaTransportSessionID, parameterRecord: OcaParameterRecord) {
      self.sessionID = sessionID
      self.parameterRecord = parameterRecord
    }
  }

  public struct SIPParameterKeyParameters: OcaParametersReflectable {
    public let sessionID: OcaMediaTransportSessionID
    public let key: OcaString

    public init(sessionID: OcaMediaTransportSessionID, key: OcaString) {
      self.sessionID = sessionID
      self.key = key
    }
  }

  public struct SIPParameterParameters: OcaParametersReflectable {
    public let sessionID: OcaMediaTransportSessionID
    public let key: OcaString
    public let value: OcaJsonValue

    public init(sessionID: OcaMediaTransportSessionID, key: OcaString, value: OcaJsonValue) {
      self.sessionID = sessionID
      self.key = key
      self.value = value
    }
  }

  public func getSIPParameterRecord(
    session id: OcaMediaTransportSessionID
  ) async throws -> OcaParameterRecord {
    try await sendCommandRrq(methodID: OcaMethodID("4.1"), parameters: id)
  }

  public func setSIPParameterRecord(
    session id: OcaMediaTransportSessionID,
    _ parameterRecord: OcaParameterRecord
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("4.2"),
      parameters: SIPParameterRecordParameters(sessionID: id, parameterRecord: parameterRecord)
    )
  }

  public func getSIPParameter(
    session id: OcaMediaTransportSessionID,
    key: OcaString
  ) async throws -> OcaJsonValue {
    try await sendCommandRrq(
      methodID: OcaMethodID("4.3"),
      parameters: SIPParameterKeyParameters(sessionID: id, key: key)
    )
  }

  public func setSIPParameter(
    session id: OcaMediaTransportSessionID,
    key: OcaString,
    value: OcaJsonValue
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("4.4"),
      parameters: SIPParameterParameters(sessionID: id, key: key, value: value)
    )
  }
}

/// Controller proxy for AES70-21's Aes67StreamSourceListAgent (1.2.A.2102), the Stream
/// Source Registry.
open class Aes67StreamSourceListAgent: OcaAgent, @unchecked Sendable {
  override open class var classID: OcaClassID { Aes67Adaptation.streamSourceListAgentClassID }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    setMethodID: OcaMethodID("3.2")
  )
  public var purpose: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.3")
  )
  public var streamSources: OcaListProperty<Aes67StreamSourceDescriptor>.PropertyValue
}
