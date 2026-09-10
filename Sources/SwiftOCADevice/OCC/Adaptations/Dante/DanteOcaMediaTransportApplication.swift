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

/// AES70-23 (draft) DanteOcaMediaTransportApplication: channel-based routing on top of
/// CM4. Method IDs 4.1-4.8 are provisional.
open class DanteOcaMediaTransportApplication: OcaMediaTransportApplication {
  public typealias DanteParameters = SwiftOCA.DanteOcaMediaTransportApplication
  public typealias ChannelEndpointMap = DanteParameters.ChannelEndpointMap

  override open class var classID: OcaClassID { DanteAdaptation.mediaTransportApplicationClassID }

  override open class var transientPropertyIDs: Set<OcaPropertyID> {
    super.transientPropertyIDs.union(["4.2"])
  }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var channelEndpoints = ChannelEndpointMap()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.8")
  )
  public var channelEndpointOperatingStates = DanteParameters.ChannelEndpointOperatingStateMap()

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
    adaptationIdentifier = DanteAdaptation.identifier
  }

  public required init(from decoder: Decoder) throws {
    throw DecodingError.objectNotDecodable(decoder)
  }

  public func channelEndpoint(_ id: OcaID16) throws -> OcaChannelEndpoint {
    guard let channelEndpoint = channelEndpoints[id] else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return channelEndpoint
  }

  public func update(channelEndpointID id: OcaID16, _ channelEndpoint: OcaChannelEndpoint) {
    guard channelEndpoints[id] != channelEndpoint else { return }
    channelEndpoints[id] = channelEndpoint
  }

  public func update(channelEndpointID id: OcaID16, operatingState: DanteChannelEndpointOperatingState) throws {
    let blob = try DanteChannelEndpointOperatingStateData(state: operatingState).blob
    guard channelEndpointOperatingStates[id] != blob else { return }
    channelEndpointOperatingStates[id] = blob
  }

  open func setChannelEndpoint(_ id: OcaID16, _ channelEndpoint: OcaChannelEndpoint) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func clearChannelEndpoint(_ id: OcaID16) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func add(channelEndpoint: OcaChannelEndpoint) async throws -> OcaID16 {
    throw Ocp1Error.status(.notImplemented)
  }

  open func delete(channelEndpoint id: OcaID16) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("4.2"):
      let endpoints: ChannelEndpointMap = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      for (id, channelEndpoint) in endpoints {
        try await setChannelEndpoint(id, channelEndpoint)
      }
      return Ocp1Response()
    case OcaMethodID("4.3"):
      let id: OcaID16 = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try controller.encodeResponse(channelEndpoint(id))
    case OcaMethodID("4.4"):
      let parameters: DanteParameters.SetChannelEndpointParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setChannelEndpoint(parameters.id, parameters.channelEndpoint)
      return Ocp1Response()
    case OcaMethodID("4.5"):
      let id: OcaID16 = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await clearChannelEndpoint(id)
      return Ocp1Response()
    case OcaMethodID("4.6"):
      let channelEndpoint: OcaChannelEndpoint = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      return try await controller.encodeResponse(add(channelEndpoint: channelEndpoint))
    case OcaMethodID("4.7"):
      let id: OcaID16 = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await delete(channelEndpoint: id)
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
