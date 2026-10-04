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
@OcaMethods
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

  public struct ConfigureEndpointFromSDPParameters: OcaParametersReflectable {
    public let endpointID: OcaMediaStreamEndpointID
    public let sdpString: OcaSDPString
    /// UDP port of the stream within a multistream SDP; zero for a single stream.
    public let streamID: OcaUint16

    public init(
      endpointID: OcaMediaStreamEndpointID,
      sdpString: OcaSDPString,
      streamID: OcaUint16
    ) {
      self.endpointID = endpointID
      self.sdpString = sdpString
      self.streamID = streamID
    }
  }

  /// ONo of the Aes67StreamEndpointRegistry, or zero when there is no registry.
  @OcaProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var streamSourceRegistryONo: OcaProperty<OcaONo>.PropertyValue

  @OcaMethod(
    "4.1",
    name: "GetEndpointDelayConstraints",
    parameters: EndpointStreamModeParameters.self
  )
  public func getEndpointDelayConstraints(
    endpointID: OcaMediaStreamEndpointID,
    streamMode: OcaMediaStreamMode
  ) async throws -> EndpointDelayConstraints

  @OcaMethod(
    "4.2",
    name: "GetPresentationTimeOffsetConstraints",
    parameters: EndpointStreamModeParameters.self
  )
  public func getPresentationTimeOffsetConstraints(
    endpointID: OcaMediaStreamEndpointID,
    streamMode: OcaMediaStreamMode
  ) async throws -> PresentationTimeOffsetConstraints

  // the draft spells the SDP string's name in capitals
  /// Optional in AES70-21 §10.2.4; sets the endpoint's AdaptationData.ActiveSDP.
  @OcaMethod(
    "4.5",
    name: "ConfigureEndpointFromSDP",
    parameters: ConfigureEndpointFromSDPParameters.self,
    parameterNames: ["EndpointID", "SDPString", "StreamID"]
  )
  public func configureEndpointFromSDP(
    endpointID: OcaMediaStreamEndpointID,
    sdpString: OcaSDPString,
    streamID: OcaUint16 = 0
  ) async throws
}

/// Controller proxy for AES70-21's Aes67OcaMediaTransportSessionAgent (1.2.20.A.2101),
/// which adds SIP parameter access to each session's AdaptationData (04m01-04m04).
@OcaMethods
open class Aes67OcaMediaTransportSessionAgent: OcaMediaTransportSessionAgent, @unchecked Sendable {
  override open class var classID: OcaClassID { Aes67Adaptation.mediaTransportSessionAgentClassID }

  public struct SIPParameterRecordParameters: OcaParametersReflectable {
    public let sessionID: OcaMediaTransportSessionID
    public let rec: OcaParameterRecord

    public init(sessionID: OcaMediaTransportSessionID, rec: OcaParameterRecord) {
      self.sessionID = sessionID
      self.rec = rec
    }
  }

  public struct SIPParameterKeyParameters: OcaParametersReflectable {
    public let sessionID: OcaMediaTransportSessionID
    public let parameterKey: OcaString

    public init(sessionID: OcaMediaTransportSessionID, parameterKey: OcaString) {
      self.sessionID = sessionID
      self.parameterKey = parameterKey
    }
  }

  public struct SIPParameterParameters: OcaParametersReflectable {
    public let sessionID: OcaMediaTransportSessionID
    public let parameterKey: OcaString
    public let parameterValue: OcaJsonValue

    public init(
      sessionID: OcaMediaTransportSessionID,
      parameterKey: OcaString,
      parameterValue: OcaJsonValue
    ) {
      self.sessionID = sessionID
      self.parameterKey = parameterKey
      self.parameterValue = parameterValue
    }
  }

  // named as the draft's pseudocode names them (§10.4.1): Rec, ParameterKey, ParameterValue
  @OcaMethod(
    "4.1",
    name: "GetSIPParameterRecord",
    parameterNames: ["SessionID"],
    resultNames: ["Rec"]
  )
  public func getSIPParameterRecord(
    sessionID: OcaMediaTransportSessionID
  ) async throws -> OcaParameterRecord

  @OcaMethod(
    "4.2",
    name: "SetSIPParameterRecord",
    parameters: SIPParameterRecordParameters.self,
    parameterNames: ["SessionID", "Rec"]
  )
  public func setSIPParameterRecord(
    sessionID: OcaMediaTransportSessionID,
    rec: OcaParameterRecord
  ) async throws

  @OcaMethod(
    "4.3",
    name: "GetSIPParameter",
    parameters: SIPParameterKeyParameters.self,
    parameterNames: ["SessionID", "ParameterKey"],
    resultNames: ["ParameterValue"]
  )
  public func getSIPParameter(
    sessionID: OcaMediaTransportSessionID,
    parameterKey: OcaString
  ) async throws -> OcaJsonValue

  @OcaMethod(
    "4.4",
    name: "SetSIPParameter",
    parameters: SIPParameterParameters.self,
    parameterNames: ["SessionID", "ParameterKey", "ParameterValue"]
  )
  public func setSIPParameter(
    sessionID: OcaMediaTransportSessionID,
    parameterKey: OcaString,
    parameterValue: OcaJsonValue
  ) async throws
}

/// Controller proxy for AES70-21's Aes67StreamEndpointRegistry (1.2.A.2102), the Stream
/// Source Registry. Entries are keyed by IDExternal (§10.3.2).
@OcaMethods
open class Aes67StreamEndpointRegistry: OcaAgent, @unchecked Sendable {
  override open class var classID: OcaClassID { Aes67Adaptation.streamEndpointRegistryClassID }

  public static let registryChangedEventID = OcaEventID(defLevel: 3, eventIndex: 1)
  public static let registryRebuiltEventID = OcaEventID(defLevel: 3, eventIndex: 2)

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var registry: OcaListProperty<Aes67StreamEndpointDescriptor>.PropertyValue

  @OcaMethod(
    "3.2",
    name: "GetRegistryEntry",
    parameterNames: ["IDExternal"],
    resultNames: ["Entry"]
  )
  public func getRegistryEntry(idExternal: OcaBlob) async throws -> Aes67StreamEndpointDescriptor

  @OcaMethod("3.3", name: "AddRegistryEntry", parameterNames: ["Entry"])
  public func addRegistryEntry(entry: Aes67StreamEndpointDescriptor) async throws

  @OcaMethod("3.4", name: "SetRegistryEntry", parameterNames: ["Entry"])
  public func setRegistryEntry(entry: Aes67StreamEndpointDescriptor) async throws

  @OcaMethod("3.5", name: "DeleteRegistryEntry", parameterNames: ["IDExternal"])
  public func deleteRegistryEntry(idExternal: OcaBlob) async throws

  /// Optional in AES70-21 §10.3.3: the device builds entries from the SDP.
  @OcaMethod("3.6", name: "AddRegistryEntriesFromSDP", parameterNames: ["SDPString"])
  public func addRegistryEntriesFromSDP(sdpString: OcaSDPString) async throws
}

/// Controller proxy for AES70-21's Aes67SDPAgent (1.2.A.2103), which passes an SDP string
/// to the device for device-defined processing.
open class Aes67SDPAgent: OcaAgent, @unchecked Sendable {
  override open class var classID: OcaClassID { Aes67Adaptation.sdpAgentClassID }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    setMethodID: OcaMethodID("3.2")
  )
  public var sdpString: OcaProperty<OcaSDPString>.PropertyValue
}
