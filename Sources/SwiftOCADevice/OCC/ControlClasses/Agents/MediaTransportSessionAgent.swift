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

@OcaDeviceMethods
open class OcaMediaTransportSessionAgent: OcaAgent {
  public typealias Parameters = SwiftOCA.OcaMediaTransportSessionAgent

  override open class var classID: OcaClassID { OcaClassID("1.2.20") }

  override open class var classVersion: OcaClassVersionNumber { 1 }

  override open class var transientPropertyIDs: Set<OcaPropertyID> { ["3.3"] }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    ocp2GetName: "Type"
  )
  public var sessionType = ""

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.2")
  )
  public var sessions = [OcaMediaTransportSession]()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.11"),
    ocp2GetName: "Sessions"
  )
  public var sessionStatuses = OcaMediaTransportSessionStatusMap()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.4"),
    getMethodID: OcaMethodID("3.17"),
    setMethodID: OcaMethodID("3.18"),
    ocp2GetName: "Data",
    ocp2SetName: "Data"
  )
  public var adaptationData: OcaAdaptationData = OcaBlob()

  // MARK: - Session access for subclasses

  public func sessionIndex(_ id: OcaMediaTransportSessionID) throws -> Int {
    guard let index = sessions.firstIndex(where: { $0.idInternal == id }) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return index
  }

  public func session(_ id: OcaMediaTransportSessionID) throws -> OcaMediaTransportSession {
    try sessions[sessionIndex(id)]
  }

  public func sessionStatus(_ id: OcaMediaTransportSessionID) throws
    -> OcaMediaTransportSessionStatus
  {
    guard let status = sessionStatuses[id] else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return status
  }

  /// Replaces the session with the same internal ID; subscribers see the whole list.
  public func update(session: OcaMediaTransportSession) throws {
    let index = try sessionIndex(session.idInternal)
    guard sessions[index] != session else { return }
    sessions[index] = session
  }

  public func update(
    sessionID id: OcaMediaTransportSessionID,
    status: OcaMediaTransportSessionStatus
  ) {
    guard sessionStatuses[id] != status else { return }
    sessionStatuses[id] = status
  }

  public func insert(
    session: OcaMediaTransportSession,
    status: OcaMediaTransportSessionStatus = .init(state: .unconfigured)
  ) {
    if let index = sessions.firstIndex(where: { $0.idInternal == session.idInternal }) {
      sessions[index] = session
    } else {
      sessions.append(session)
    }
    sessionStatuses[session.idInternal] = status
  }

  public func remove(sessionID id: OcaMediaTransportSessionID) {
    sessions.removeAll { $0.idInternal == id }
    sessionStatuses.removeValue(forKey: id)
  }

  // MARK: - Overridable behaviour

  /// Returns the given descriptor with its IDInternal set to the allocated session ID.
  @OcaDeviceMethod(Parameters.addSession, access: .write)
  open func add(
    session: OcaMediaTransportSession,
    from controller: any OcaController
  ) async throws -> OcaMediaTransportSession {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Called with the stored session carrying the IDs, label and adaptation data from the
  /// command; connections and the streaming switch are the stored ones.
  open func configure(session: OcaMediaTransportSession) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.deleteSession, access: .write)
  open func delete(session id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.resetSession, access: .write)
  open func reset(session id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.setStreamingEnabled, access: .write)
  open func set(
    session id: OcaMediaTransportSessionID,
    streamingEnabled active: OcaBoolean,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.startStreaming, access: .write)
  open func startStreaming(session id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.stopStreaming, access: .write)
  open func stopStreaming(session id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Returns the given descriptor with its ID set to the allocated connection ID.
  @OcaDeviceMethod(Parameters.addConnection, access: .write)
  open func add(
    connection: OcaMediaTransportSessionConnection,
    to sessionID: OcaMediaTransportSessionID,
    from controller: any OcaController
  ) async throws -> OcaMediaTransportSessionConnection {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.configureConnection, access: .write)
  open func configureConnection(
    sessionID: OcaMediaTransportSessionID,
    connectionID: OcaMediaTransportSessionConnectionID,
    localEndpointID: OcaMediaStreamEndpointID,
    remoteEndpointID: OcaBlob,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.deleteConnection, access: .write)
  open func delete(
    connection connectionID: OcaMediaTransportSessionConnectionID,
    from sessionID: OcaMediaTransportSessionID,
    controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.deleteConnections, access: .write)
  open func deleteConnections(session id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  // MARK: - Command dispatch

  @OcaDeviceMethod(Parameters.getSession, access: .read)
  func getSession(_ id: OcaMediaTransportSessionID, from controller: any OcaController) throws
    -> OcaMediaTransportSession
  {
    try session(id)
  }

  @OcaDeviceMethod(Parameters.configureSession, access: .write)
  func configureSession(
    _ parameters: Parameters.ConfigureSessionParameters,
    from controller: any OcaController
  ) async throws {
    var session = try session(parameters.idInternal)
    session.idExternal = parameters.idExternal
    session.userLabel = parameters.userLabel
    session.adaptationData = parameters.adaptationData
    try await configure(session: session)
  }

  // the model names GetSessionStatus's output Session, like GetSession's
  @OcaDeviceMethod(Parameters.getSessionStatus, access: .read)
  func getSessionStatus(_ id: OcaMediaTransportSessionID, from controller: any OcaController) throws
    -> OcaMediaTransportSessionStatus
  {
    try sessionStatus(id)
  }

}
