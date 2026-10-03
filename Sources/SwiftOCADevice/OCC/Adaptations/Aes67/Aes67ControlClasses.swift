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
@OcaDeviceMethods
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


  @OcaDeviceMethod(Aes67Parameters.getEndpointDelayConstraints, access: .read)
  func getEndpointDelayConstraints(
    _ parameters: Aes67Parameters.EndpointStreamModeParameters,
    from controller: any OcaController
  ) async throws -> Aes67Parameters.EndpointDelayConstraints {
    try await getEndpointDelayConstraints(parameters.endpointID, streamMode: parameters.streamMode)
  }

  @OcaDeviceMethod(Aes67Parameters.getPresentationTimeOffsetConstraints, access: .read)
  func getPresentationTimeOffsetConstraints(
    _ parameters: Aes67Parameters.EndpointStreamModeParameters,
    from controller: any OcaController
  ) async throws -> Aes67Parameters.PresentationTimeOffsetConstraints {
    try await getPresentationTimeOffsetConstraints(parameters.endpointID, streamMode: parameters.streamMode)
  }

  @OcaDeviceMethod(Aes67Parameters.configureEndpointFromSDP, access: .write)
  func configureEndpointFromSDP(
    _ parameters: Aes67Parameters.ConfigureEndpointFromSDPParameters,
    from controller: any OcaController
  ) async throws {
    try await configureEndpointFromSDP(
      parameters.endpointID,
      sdpString: parameters.sdpString,
      streamID: parameters.streamID
    )
  }
}

/// AES70-21 (draft) Aes67OcaMediaTransportSessionAgent: SIP parameter records per session
/// (04m01-04m04).
@OcaDeviceMethods
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


  @OcaDeviceMethod(Aes67Parameters.getSIPParameterRecord, access: .read)
  func getSIPParameterRecord(_ id: OcaMediaTransportSessionID, from controller: any OcaController) async throws
    -> OcaParameterRecord
  {
    try await getSIPParameterRecord(session: id)
  }

  @OcaDeviceMethod(Aes67Parameters.setSIPParameterRecord, access: .write)
  func setSIPParameterRecord(
    _ parameters: Aes67Parameters.SIPParameterRecordParameters,
    from controller: any OcaController
  ) async throws {
    try await setSIPParameterRecord(session: parameters.sessionID, parameters.parameterRecord)
  }

  @OcaDeviceMethod(Aes67Parameters.getSIPParameter, access: .read)
  func getSIPParameter(
    _ parameters: Aes67Parameters.SIPParameterKeyParameters,
    from controller: any OcaController
  ) async throws -> OcaJsonValue {
    try await getSIPParameter(session: parameters.sessionID, key: parameters.key)
  }

  @OcaDeviceMethod(Aes67Parameters.setSIPParameter, access: .write)
  func setSIPParameter(
    _ parameters: Aes67Parameters.SIPParameterParameters,
    from controller: any OcaController
  ) async throws {
    try await setSIPParameter(session: parameters.sessionID, key: parameters.key, value: parameters.value)
  }
}

/// AES70-21 (draft) Aes67StreamEndpointRegistry: the Stream Source Registry, keyed by
/// IDExternal. Entries are stored here; AddRegistryEntriesFromSDP is left to subclasses.
@OcaDeviceMethods
open class Aes67StreamEndpointRegistry: OcaAgent {
  public typealias Aes67Parameters = SwiftOCA.Aes67StreamEndpointRegistry

  override open class var classID: OcaClassID { Aes67Adaptation.streamEndpointRegistryClassID }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var registry = [Aes67StreamEndpointDescriptor]()

  public func registryIndex(idExternal: OcaBlob) throws -> Int {
    guard let index = registry.firstIndex(where: { $0.idExternal == idExternal }) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return index
  }

  open func getRegistryEntry(idExternal: OcaBlob) async throws -> Aes67StreamEndpointDescriptor {
    try registry[registryIndex(idExternal: idExternal)]
  }

  open func addRegistryEntry(_ entry: Aes67StreamEndpointDescriptor) async throws {
    guard !registry.contains(where: { $0.idExternal == entry.idExternal }) else {
      throw Ocp1Error.status(.invalidRequest)
    }
    registry.append(entry)
    try await notifyRegistryChanged(.itemAdded, entry: entry)
  }

  open func setRegistryEntry(_ entry: Aes67StreamEndpointDescriptor) async throws {
    try registry[registryIndex(idExternal: entry.idExternal)] = entry
    try await notifyRegistryChanged(.itemChanged, entry: entry)
  }

  open func deleteRegistryEntry(idExternal: OcaBlob) async throws {
    let entry = try registry.remove(at: registryIndex(idExternal: idExternal))
    try await notifyRegistryChanged(.itemDeleted, entry: entry)
  }

  open func addRegistryEntriesFromSDP(_ sdpString: OcaSDPString) async throws {
    throw Ocp1Error.status(.notImplemented)
  }


  @OcaDeviceMethod(Aes67Parameters.getRegistryEntry, access: .read)
  func getRegistryEntry(_ idExternal: OcaBlob, from controller: any OcaController) async throws
    -> Aes67StreamEndpointDescriptor
  {
    try await getRegistryEntry(idExternal: idExternal)
  }

  @OcaDeviceMethod(Aes67Parameters.addRegistryEntry, access: .write)
  func addRegistryEntry(_ entry: Aes67StreamEndpointDescriptor, from controller: any OcaController) async throws {
    try await addRegistryEntry(entry)
  }

  @OcaDeviceMethod(Aes67Parameters.setRegistryEntry, access: .write)
  func setRegistryEntry(_ entry: Aes67StreamEndpointDescriptor, from controller: any OcaController) async throws {
    try await setRegistryEntry(entry)
  }

  @OcaDeviceMethod(Aes67Parameters.deleteRegistryEntry, access: .write)
  func deleteRegistryEntry(_ idExternal: OcaBlob, from controller: any OcaController) async throws {
    try await deleteRegistryEntry(idExternal: idExternal)
  }

  @OcaDeviceMethod(Aes67Parameters.addRegistryEntriesFromSDP, access: .write)
  func addRegistryEntriesFromSDP(_ sdpString: OcaSDPString, from controller: any OcaController) async throws {
    try await addRegistryEntriesFromSDP(sdpString)
  }

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
