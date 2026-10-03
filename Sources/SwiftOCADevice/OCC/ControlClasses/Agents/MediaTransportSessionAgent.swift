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
  open func add(session: OcaMediaTransportSession) async throws -> OcaMediaTransportSession {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Called with the stored session carrying the IDs, label and adaptation data from the
  /// command; connections and the streaming switch are the stored ones.
  open func configure(session: OcaMediaTransportSession) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func delete(session id: OcaMediaTransportSessionID) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func reset(session id: OcaMediaTransportSessionID) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func set(session id: OcaMediaTransportSessionID, streamingEnabled: OcaBoolean) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func startStreaming(session id: OcaMediaTransportSessionID) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func stopStreaming(session id: OcaMediaTransportSessionID) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Returns the given descriptor with its ID set to the allocated connection ID.
  open func add(
    connection: OcaMediaTransportSessionConnection,
    to sessionID: OcaMediaTransportSessionID
  ) async throws -> OcaMediaTransportSessionConnection {
    throw Ocp1Error.status(.notImplemented)
  }

  open func configureConnection(
    sessionID: OcaMediaTransportSessionID,
    connectionID: OcaMediaTransportSessionConnectionID,
    localEndpointID: OcaMediaStreamEndpointID,
    remoteEndpointID: OcaBlob
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func delete(
    connection id: OcaMediaTransportSessionConnectionID,
    from sessionID: OcaMediaTransportSessionID
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func deleteConnections(session id: OcaMediaTransportSessionID) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  // MARK: - Command dispatch

  @OcaDeviceMethod("3.3", name: "GetSession", access: .read, parameterNames: ["ID"], resultNames: ["Session"])
  func getSession(_ id: OcaMediaTransportSessionID, from controller: any OcaController) throws
    -> OcaMediaTransportSession
  {
    try session(id)
  }

  @OcaDeviceMethod("3.4", name: "AddSession", access: .write, resultNames: ["Session"])
  func addSession(_ session: OcaMediaTransportSession, from controller: any OcaController) async throws
    -> OcaMediaTransportSession
  {
    try await add(session: session)
  }

  @OcaDeviceMethod("3.5", name: "ConfigureSession", access: .write)
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

  @OcaDeviceMethod("3.6", name: "DeleteSession", access: .write, parameterNames: ["ID"])
  func deleteSession(_ id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    try await delete(session: id)
  }

  @OcaDeviceMethod("3.7", name: "ResetSession", access: .write, parameterNames: ["ID"])
  func resetSession(_ id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    try await reset(session: id)
  }

  @OcaDeviceMethod("3.8", name: "SetStreamingEnabled", access: .write)
  func setStreamingEnabled(
    _ parameters: Parameters.SetStreamingEnabledParameters,
    from controller: any OcaController
  ) async throws {
    try await set(session: parameters.id, streamingEnabled: parameters.active)
  }

  @OcaDeviceMethod("3.9", name: "StartStreaming", access: .write, parameterNames: ["ID"])
  func startStreaming(_ id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    try await startStreaming(session: id)
  }

  @OcaDeviceMethod("3.10", name: "StopStreaming", access: .write, parameterNames: ["ID"])
  func stopStreaming(_ id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    try await stopStreaming(session: id)
  }

  // the model names GetSessionStatus's output Session, like GetSession's
  @OcaDeviceMethod("3.12", name: "GetSessionStatus", access: .read, parameterNames: ["ID"], resultNames: ["Session"])
  func getSessionStatus(_ id: OcaMediaTransportSessionID, from controller: any OcaController) throws
    -> OcaMediaTransportSessionStatus
  {
    try sessionStatus(id)
  }

  @OcaDeviceMethod("3.13", name: "AddConnection", access: .write, resultNames: ["Connection"])
  func addConnection(
    _ parameters: Parameters.AddConnectionParameters,
    from controller: any OcaController
  ) async throws -> OcaMediaTransportSessionConnection {
    try await add(connection: parameters.connection, to: parameters.sessionID)
  }

  @OcaDeviceMethod("3.14", name: "ConfigureConnection", access: .write)
  func configureConnection(
    _ parameters: Parameters.ConfigureConnectionParameters,
    from controller: any OcaController
  ) async throws {
    try await configureConnection(
      sessionID: parameters.sessionID,
      connectionID: parameters.connectionID,
      localEndpointID: parameters.localEndpointID,
      remoteEndpointID: parameters.remoteEndpointID
    )
  }

  @OcaDeviceMethod("3.15", name: "DeleteConnection", access: .write)
  func deleteConnection(
    _ parameters: Parameters.SessionConnectionParameters,
    from controller: any OcaController
  ) async throws {
    try await delete(connection: parameters.connectionID, from: parameters.sessionID)
  }

  @OcaDeviceMethod("3.16", name: "DeleteConnections", access: .write, parameterNames: ["SessionID"])
  func deleteConnections(_ id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    try await deleteConnections(session: id)
  }
}
