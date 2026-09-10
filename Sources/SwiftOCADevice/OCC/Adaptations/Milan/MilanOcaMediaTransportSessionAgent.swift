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
/// unbound with ResetSession, and started or stopped with SetStreamingEnabled. A
/// concrete subclass implements those hooks and refuses the methods Milan omits.
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
    throw DecodingError.objectNotDecodable(decoder)
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
}
