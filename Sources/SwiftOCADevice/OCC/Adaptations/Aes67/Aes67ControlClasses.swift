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
/// negotiation and SDP tunnelling to CM4. Method IDs 4.3-4.7 are provisional.
open class Aes67OcaMediaTransportApplication: OcaMediaTransportApplication {
  public typealias Aes67Parameters = SwiftOCA.Aes67OcaMediaTransportApplication

  override open class var classID: OcaClassID { Aes67Adaptation.mediaTransportApplicationClassID }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.6"),
    setMethodID: OcaMethodID("4.7")
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

  open func submitSDP(_ id: OcaMediaStreamEndpointID, sdp: OcaSDPString) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Default: the SubmittedSDP field of the endpoint's adaptation data.
  open func getSubmittedSDP(_ id: OcaMediaStreamEndpointID) async throws -> OcaSDPString {
    try endpoint(id).adaptationData.decode(Aes67EndpointAdaptationData.self).submittedSDP
  }

  /// Default: the ActiveSDP field of the endpoint's adaptation data.
  open func getActiveSDP(_ id: OcaMediaStreamEndpointID) async throws -> OcaSDPString {
    try endpoint(id).adaptationData.decode(Aes67EndpointAdaptationData.self).activeSDP
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
    case OcaMethodID("4.3"):
      let parameters: Aes67Parameters.SubmitSDPParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await submitSDP(parameters.endpointID, sdp: parameters.sdp)
      return Ocp1Response()
    case OcaMethodID("4.4"):
      let id: OcaMediaStreamEndpointID = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try await controller.encodeResponse(getSubmittedSDP(id))
    case OcaMethodID("4.5"):
      let id: OcaMediaStreamEndpointID = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try await controller.encodeResponse(getActiveSDP(id))
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}

/// AES70-21 (draft) Aes67OcaMediaTransportSessionAgent: SIP parameter records per session.
/// Method IDs 4.1-4.4 are provisional.
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

/// AES70-21 (draft) Aes67StreamSourceListAgent: the Stream Source Registry.
open class Aes67StreamSourceListAgent: OcaAgent {
  override open class var classID: OcaClassID { Aes67Adaptation.streamSourceListAgentClassID }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    setMethodID: OcaMethodID("3.2")
  )
  public var purpose: OcaString = Aes67Adaptation.streamSourceRegistryPurpose

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.3")
  )
  public var streamSources = [Aes67StreamSourceDescriptor]()
}
