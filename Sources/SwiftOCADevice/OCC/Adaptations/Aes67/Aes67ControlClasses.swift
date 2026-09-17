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

import SwiftOCA

/// AES70-21 (draft) Aes67OcaMediaTransportApplication: adds presentation time offset
/// negotiation and endpoint configuration from SDP to CM4.
open class Aes67OcaMediaTransportApplication: OcaMediaTransportApplication {
  public typealias Aes67Parameters = SwiftOCA.Aes67OcaMediaTransportApplication

  override open class var classID: OcaClassID { Aes67Adaptation.mediaTransportApplicationClassID }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var streamSourceRegistryONo = OcaInvalidONo

  public required init(
    objectNumber: OcaONo? = nil,
    lockable: OcaBoolean = true,
    role: OcaString? = nil,
    deviceDelegate: OcaDevice? = nil,
    addToRootBlock: Bool = true
  ) async throws {
    try await super.init(
      objectNumber: objectNumber,
      lockable: lockable,
      role: role,
      deviceDelegate: deviceDelegate,
      addToRootBlock: addToRootBlock
    )
    adaptationIdentifier = Aes67Adaptation.identifier
  }

  public required init(from decoder: Decoder) throws {
    throw DecodingError.objectNotDecodable(decoder)
  }

  open func getEndpointDelayConstraints(
    _ id: OcaMediaStreamEndpointID,
    streamMode: OcaMediaStreamMode
  ) async throws -> Aes67Parameters.EndpointDelayConstraints {
    throw Ocp1Error.status(.notImplemented)
  }

  open func getPresentationTimeOffsetConstraints(
    _ id: OcaMediaStreamEndpointID,
    streamMode: OcaMediaStreamMode
  ) async throws -> Aes67Parameters.PresentationTimeOffsetConstraints {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Optional (AES70-21 §10.2.4). A nonzero stream ID selects the stream of a multistream
  /// SDP by UDP port; on success the endpoint's ActiveSDP is the given SDP.
  open func configureEndpointFromSDP(
    _ id: OcaMediaStreamEndpointID,
    sdpString: OcaSDPString,
    streamID: OcaUint16
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("4.1"):
      let parameters: Aes67Parameters.EndpointStreamModeParameters = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try await controller.encodeResponse(getEndpointDelayConstraints(
        parameters.endpointID,
        streamMode: parameters.streamMode
      ))
    case OcaMethodID("4.2"):
      let parameters: Aes67Parameters.EndpointStreamModeParameters = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try await controller.encodeResponse(getPresentationTimeOffsetConstraints(
        parameters.endpointID,
        streamMode: parameters.streamMode
      ))
    case OcaMethodID("4.5"):
      let parameters: Aes67Parameters.ConfigureEndpointFromSDPParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await configureEndpointFromSDP(
        parameters.endpointID,
        sdpString: parameters.sdpString,
        streamID: parameters.streamID
      )
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}

/// AES70-21 (draft) Aes67OcaMediaTransportSessionAgent: SIP parameter records per session.
/// The draft's 03m01-03m04 collide with the parent's methods, so 4.1-4.4 are used.
open class Aes67OcaMediaTransportSessionAgent: OcaMediaTransportSessionAgent {
  public typealias Aes67Parameters = SwiftOCA.Aes67OcaMediaTransportSessionAgent

  override open class var classID: OcaClassID { Aes67Adaptation.mediaTransportSessionAgentClassID }

  public required init(
    objectNumber: OcaONo? = nil,
    lockable: OcaBoolean = true,
    role: OcaString? = nil,
    deviceDelegate: OcaDevice? = nil,
    addToRootBlock: Bool = true
  ) async throws {
    try await super.init(
      objectNumber: objectNumber,
      lockable: lockable,
      role: role,
      deviceDelegate: deviceDelegate,
      addToRootBlock: addToRootBlock
    )
    sessionType = Aes67Adaptation.identifier
  }

  public required init(from decoder: Decoder) throws {
    throw DecodingError.objectNotDecodable(decoder)
  }

  /// Default: the session's adaptation data, which AES70-21 defines as the SIP record.
  open func getSIPParameterRecord(
    session id: OcaMediaTransportSessionID
  ) async throws -> OcaParameterRecord {
    let adaptationData = try session(id).adaptationData
    return String(decoding: adaptationData, as: UTF8.self)
  }

  open func setSIPParameterRecord(
    session id: OcaMediaTransportSessionID,
    _ parameterRecord: OcaParameterRecord
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func getSIPParameter(
    session id: OcaMediaTransportSessionID,
    key: OcaString
  ) async throws -> OcaJsonValue {
    throw Ocp1Error.status(.notImplemented)
  }

  open func setSIPParameter(
    session id: OcaMediaTransportSessionID,
    key: OcaString,
    value: OcaJsonValue
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("4.1"):
      let id: OcaMediaTransportSessionID = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try await controller.encodeResponse(getSIPParameterRecord(session: id))
    case OcaMethodID("4.2"):
      let parameters: Aes67Parameters.SIPParameterRecordParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setSIPParameterRecord(session: parameters.sessionID, parameters.parameterRecord)
      return Ocp1Response()
    case OcaMethodID("4.3"):
      let parameters: Aes67Parameters.SIPParameterKeyParameters = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try await controller.encodeResponse(getSIPParameter(
        session: parameters.sessionID,
        key: parameters.key
      ))
    case OcaMethodID("4.4"):
      let parameters: Aes67Parameters.SIPParameterParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setSIPParameter(
        session: parameters.sessionID,
        key: parameters.key,
        value: parameters.value
      )
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}

/// AES70-21 (draft) Aes67StreamEndpointRegistry: the Stream Source Registry. The draft
/// gives no signatures for the entry methods, so only the registry and its events are here.
open class Aes67StreamEndpointRegistry: OcaAgent {
  public typealias Aes67Parameters = SwiftOCA.Aes67StreamEndpointRegistry

  override open class var classID: OcaClassID { Aes67Adaptation.streamEndpointRegistryClassID }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var registry = [Aes67StreamEndpointDescriptor]()

  /// Raises RegistryChanged for an entry already reflected in `registry`.
  public func notifyRegistryChanged(
    _ changeType: OcaPropertyChangeType,
    entry: Aes67StreamEndpointDescriptor
  ) async throws {
    try await deviceDelegate?.notifySubscribers(
      OcaEvent(emitterONo: objectNumber, eventID: Aes67Parameters.registryChangedEventID),
      eventData: Aes67RegistryChangedEventData(changeType: changeType, entry: entry)
    )
  }

  /// Raises RegistryRebuilt with the current `registry`.
  public func notifyRegistryRebuilt() async throws {
    try await deviceDelegate?.notifySubscribers(
      OcaEvent(emitterONo: objectNumber, eventID: Aes67Parameters.registryRebuiltEventID),
      eventData: Aes67RegistryRebuiltEventData(registry: registry)
    )
  }
}

/// AES70-21 (draft) Aes67SDPAgent: an SDP string handed to the device, whose processing
/// is device-defined.
open class Aes67SDPAgent: OcaAgent {
  override open class var classID: OcaClassID { Aes67Adaptation.sdpAgentClassID }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    setMethodID: OcaMethodID("3.2")
  )
  public var sdpString: OcaSDPString = ""
}
