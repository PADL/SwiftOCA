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
@OcaDeviceMethods
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

  @OcaDeviceMethod(DanteParameters.setChannelEndpoint, access: .write)
  open func setChannelEndpoint(
    _ id: OcaID16,
    _ channelEndpoint: OcaChannelEndpoint,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(DanteParameters.clearChannelEndpoint, access: .write)
  open func clearChannelEndpoint(_ id: OcaID16, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(DanteParameters.addChannelEndpoint, access: .write)
  open func add(channelEndpoint: OcaChannelEndpoint, from controller: any OcaController) async throws -> OcaID16 {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(DanteParameters.deleteChannelEndpoint, access: .write)
  open func delete(channelEndpoint id: OcaID16, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(DanteParameters.getChannelEndpoint, access: .read)
  func getChannelEndpoint(_ id: OcaID16, from controller: any OcaController) throws -> OcaChannelEndpoint {
    try channelEndpoint(id)
  }

  /// SetChannelEndpoints (4.2) stays an arm: it is the setter of a property, applied
  /// one endpoint at a time.
  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("4.2"):
      let endpoints: ChannelEndpointMap = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      for (id, channelEndpoint) in endpoints {
        try await setChannelEndpoint(id, channelEndpoint, from: controller)
      }
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
