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

/// Controller proxy for the AES70-22 session agent (class 1.2.20.A.2200).
open class MilanOcaMediaTransportSessionAgent: OcaMediaTransportSessionAgent, @unchecked Sendable {
  override open class var classID: OcaClassID { MilanAdaptation.sessionAgentClassID }

  /// Models Milan BIND_RX for the session of a local input endpoint.
  public func configureConnection(
    localEndpointID: OcaMediaStreamEndpointID,
    remote: MilanMediaStreamEndpointIDExternal
  ) async throws {
    try await configureConnection(
      sessionID: localEndpointID,
      localEndpointID: localEndpointID,
      remoteEndpointID: remote.blob
    )
  }

  public func milanStatus(
    for sessionID: OcaMediaTransportSessionID
  ) async throws -> (OcaMediaTransportSessionState, MilanSessionStatusAdaptationData) {
    let status = try await getSessionStatus(sessionID)
    let adaptationData = status.adaptationData.isEmpty
      ? MilanSessionStatusAdaptationData()
      : try status.adaptationData.decode(MilanSessionStatusAdaptationData.self)
    return (status.state, adaptationData)
  }
}
