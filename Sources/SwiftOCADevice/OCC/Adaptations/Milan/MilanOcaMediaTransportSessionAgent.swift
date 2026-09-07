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

/// AES70-22 §7.4: one session per input endpoint, bound with ConfigureConnection,
/// unbound with ResetSession, and started or stopped with SetStreamingEnabled.
open class MilanOcaMediaTransportSessionAgent: OcaMediaTransportSessionAgent {
  override open class var classID: OcaClassID { MilanAdaptation.sessionAgentClassID }

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
    sessionType = MilanAdaptation.sessionType
  }

  public required init(from decoder: Decoder) throws {
    throw Ocp1Error.notImplemented
  }

  /// A session in the shape of AES70-22 Tables 24 and 25.
  public static func makeSession(
    inputEndpointID: OcaMediaStreamEndpointID,
    remote: MilanMediaStreamEndpointIDExternal = .unbound,
    streamingEnabled: OcaBoolean = false,
    localEndpointState: OcaMediaStreamEndpointState = .notReady
  ) throws -> OcaMediaTransportSession {
    try OcaMediaTransportSession(
      idInternal: inputEndpointID,
      streamingEnabled: streamingEnabled,
      connections: [OcaMediaTransportSessionConnection(
        id: 1,
        localEndpointID: inputEndpointID,
        remoteEndpointID: remote.blob
      )],
      connectionStates: [1: OcaMediaTransportSessionConnectionState(
        localEndpointState: localEndpointState,
        remoteEndpointState: .unknown
      )]
    )
  }

  public func update(
    sessionID id: OcaMediaTransportSessionID,
    remote: MilanMediaStreamEndpointIDExternal,
    streamingEnabled: OcaBoolean,
    localEndpointState: OcaMediaStreamEndpointState
  ) throws {
    try update(session: Self.makeSession(
      inputEndpointID: id,
      remote: remote,
      streamingEnabled: streamingEnabled,
      localEndpointState: localEndpointState
    ))
  }

  public func update(
    sessionID id: OcaMediaTransportSessionID,
    state: OcaMediaTransportSessionState,
    milanStatus: MilanSessionStatusAdaptationData
  ) throws {
    try update(sessionID: id, status: OcaMediaTransportSessionStatus(
      state: state,
      adaptationData: milanStatus.blob
    ))
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.4"), // AddSession
         OcaMethodID("3.5"), // ConfigureSession
         OcaMethodID("3.6"), // DeleteSession
         OcaMethodID("3.9"), // StartStreaming
         OcaMethodID("3.10"), // StopStreaming
         OcaMethodID("3.13"), // AddConnection
         OcaMethodID("3.15"), // DeleteConnection
         OcaMethodID("3.16"), // DeleteConnections
         OcaMethodID("3.18"): // SetAdaptationData
      throw Ocp1Error.status(.notImplemented)
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
