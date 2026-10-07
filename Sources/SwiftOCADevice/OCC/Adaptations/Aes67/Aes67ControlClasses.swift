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
@OcaDeviceClass
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

  @OcaDeviceMethod(Aes67Parameters.Methods.getEndpointDelayConstraints)
  open func getEndpointDelayConstraints(
    endpointID: OcaMediaStreamEndpointID,
    streamMode: OcaMediaStreamMode,
    from controller: any OcaController
  ) async throws -> Aes67Parameters.EndpointDelayConstraints {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Aes67Parameters.Methods.getPresentationTimeOffsetConstraints)
  open func getPresentationTimeOffsetConstraints(
    endpointID: OcaMediaStreamEndpointID,
    streamMode: OcaMediaStreamMode,
    from controller: any OcaController
  ) async throws -> Aes67Parameters.PresentationTimeOffsetConstraints {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Optional (AES70-21 §10.2.4). A nonzero stream ID selects the stream of a multistream
  /// SDP by UDP port; on success the endpoint's ActiveSDP is the given SDP.
  @OcaDeviceMethod(Aes67Parameters.Methods.configureEndpointFromSDP)
  open func configureEndpointFromSDP(
    endpointID: OcaMediaStreamEndpointID,
    sdpString: OcaSDPString,
    streamID: OcaUint16,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

}

/// AES70-21 (draft) Aes67OcaMediaTransportSessionAgent: SIP parameter records per session
/// (04m01-04m04).
@OcaDeviceClass
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
  @OcaDeviceMethod(Aes67Parameters.Methods.getSIPParameterRecord)
  open func getSIPParameterRecord(
    sessionID: OcaMediaTransportSessionID,
    from controller: any OcaController
  ) async throws -> OcaParameterRecord {
    let adaptationData = try session(sessionID).adaptationData
    return String(decoding: adaptationData, as: UTF8.self)
  }

  @OcaDeviceMethod(Aes67Parameters.Methods.setSIPParameterRecord)
  open func setSIPParameterRecord(
    sessionID: OcaMediaTransportSessionID,
    rec: OcaParameterRecord,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Aes67Parameters.Methods.getSIPParameter)
  open func getSIPParameter(
    sessionID: OcaMediaTransportSessionID,
    parameterKey: OcaString,
    from controller: any OcaController
  ) async throws -> OcaJsonValue {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Aes67Parameters.Methods.setSIPParameter)
  open func setSIPParameter(
    sessionID: OcaMediaTransportSessionID,
    parameterKey: OcaString,
    parameterValue: OcaJsonValue,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

}

/// AES70-21 (draft) Aes67StreamEndpointRegistry: the Stream Source Registry, keyed by
/// IDExternal. Entries are stored here; AddRegistryEntriesFromSDP is left to subclasses.
@OcaDeviceClass
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

  @OcaDeviceMethod(Aes67Parameters.Methods.getRegistryEntry)
  open func getRegistryEntry(idExternal: OcaBlob, from controller: any OcaController) async throws -> Aes67StreamEndpointDescriptor {
    try registry[registryIndex(idExternal: idExternal)]
  }

  @OcaDeviceMethod(Aes67Parameters.Methods.addRegistryEntry)
  open func addRegistryEntry(entry: Aes67StreamEndpointDescriptor, from controller: any OcaController) async throws {
    guard !registry.contains(where: { $0.idExternal == entry.idExternal }) else {
      throw Ocp1Error.status(.invalidRequest)
    }
    registry.append(entry)
    try await notifyRegistryChanged(.itemAdded, entry: entry)
  }

  @OcaDeviceMethod(Aes67Parameters.Methods.setRegistryEntry)
  open func setRegistryEntry(entry: Aes67StreamEndpointDescriptor, from controller: any OcaController) async throws {
    try registry[registryIndex(idExternal: entry.idExternal)] = entry
    try await notifyRegistryChanged(.itemChanged, entry: entry)
  }

  @OcaDeviceMethod(Aes67Parameters.Methods.deleteRegistryEntry)
  open func deleteRegistryEntry(idExternal: OcaBlob, from controller: any OcaController) async throws {
    let entry = try registry.remove(at: registryIndex(idExternal: idExternal))
    try await notifyRegistryChanged(.itemDeleted, entry: entry)
  }

  @OcaDeviceMethod(Aes67Parameters.Methods.addRegistryEntriesFromSDP)
  open func addRegistryEntriesFromSDP(sdpString: OcaSDPString, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
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
@OcaDeviceClass
open class Aes67SDPAgent: OcaAgent {
  override open class var classID: OcaClassID { Aes67Adaptation.sdpAgentClassID }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    setMethodID: OcaMethodID("3.2")
  )
  public var sdpString: OcaSDPString = ""
}
