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

/// AES70-22 §7.3: the Milan constraints on OcaMediaTransportApplication. Shares class ID
/// 1.7.1 with its superclass, so it is not registered.
open class MilanOcaMediaTransportApplication: OcaMediaTransportApplication {
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
    adaptationIdentifier = MilanAdaptation.identifier
  }

  public required init(from decoder: Decoder) throws {
    throw Ocp1Error.notImplemented
  }

  /// Applies a new stream mode; called only for endpoints in the NotReady state.
  open func milanSetEndpoint(
    _ endpoint: OcaMediaStreamEndpoint,
    mediaStreamMode: OcaMediaStreamMode
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Applies a new channel map; called only when the endpoint's map is dynamic.
  open func milanSetEndpoint(
    _ endpoint: OcaMediaStreamEndpoint,
    channelMap: OcaMultiMap<OcaUint16, OcaPortID>
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Applies VlanID and PresentationTimeOffset to a NotReady output endpoint.
  open func milanSetEndpoint(
    _ endpoint: OcaMediaStreamEndpoint,
    vlanID: OcaUint16,
    presentationTimeOffset: OcaUint32
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  override open func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    mediaStreamMode: OcaMediaStreamMode
  ) async throws {
    let endpoint = try endpoint(id)
    guard try endpointStatus(id).state == .notReady else {
      throw Ocp1Error.status(.invalidRequest)
    }
    try await milanSetEndpoint(endpoint, mediaStreamMode: mediaStreamMode)
  }

  override open func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    channelMap: OcaMultiMap<OcaUint16, OcaPortID>
  ) async throws {
    let endpoint = try endpoint(id)
    guard endpoint.channelMapDynamic else {
      throw Ocp1Error.status(.invalidRequest)
    }
    if endpoint.direction == .output {
      guard try endpointStatus(id).state == .notReady else {
        throw Ocp1Error.status(.invalidRequest)
      }
    }
    try await milanSetEndpoint(endpoint, channelMap: channelMap)
  }

  override open func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    adaptationData: OcaAdaptationData
  ) async throws {
    let endpoint = try endpoint(id)
    guard endpoint.direction == .output, try endpointStatus(id).state == .notReady else {
      throw Ocp1Error.status(.invalidRequest)
    }
    let milanData = try adaptationData.decode(MilanMediaStreamEndpointAdaptationData.self)
    guard milanData.hasOnlyWritableFields else {
      throw Ocp1Error.status(.parameterError)
    }
    try await milanSetEndpoint(
      endpoint,
      vlanID: milanData.vlanID,
      presentationTimeOffset: milanData.presentationTimeOffset
    )
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("2.6"), // SetNetworkInterfaceAssignments
         OcaMethodID("2.9"), // SetAdaptationData
         OcaMethodID("2.14"), // ResetCounters
         OcaMethodID("3.1"), // AddPort
         OcaMethodID("3.2"), // DeletePort
         OcaMethodID("3.7"), // SetPortClockMap
         OcaMethodID("3.8"), // SetPortClockMapEntry
         OcaMethodID("3.9"), // DeletePortClockMapEntry
         OcaMethodID("3.16"), // SetMediaStreamModeCapabilities
         OcaMethodID("3.19"), // SetTransportTimingParameters
         OcaMethodID("3.25"), // AddEndpoint
         OcaMethodID("3.26"), // DeleteEndpoint
         OcaMethodID("3.27"), // ApplyEndpointCommand
         OcaMethodID("3.39"), // ResetEndpointCounterSet
         OcaMethodID("3.41"): // SetTransportSessionControlAgentONos
      throw Ocp1Error.status(.notImplemented)
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
