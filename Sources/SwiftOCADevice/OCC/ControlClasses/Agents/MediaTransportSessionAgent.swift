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

open class OcaMediaTransportSessionAgent: OcaAgent {
  public typealias Parameters = SwiftOCA.OcaMediaTransportSessionAgent

  override open class var classID: OcaClassID { OcaClassID("1.2.20") }

  override open class var classVersion: OcaClassVersionNumber { 1 }

  override open class var transientPropertyIDs: Set<OcaPropertyID> { ["3.3"] }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var sessionType = ""

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.2")
  )
  public var sessions = [OcaMediaTransportSession]()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.11")
  )
  public var sessionStatuses = OcaMediaTransportSessionStatusMap()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.4"),
    getMethodID: OcaMethodID("3.17"),
    setMethodID: OcaMethodID("3.18")
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

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.3"):
      let id: OcaMediaTransportSessionID = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try encodeResponse(session(id))
    case OcaMethodID("3.4"):
      let session: OcaMediaTransportSession = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      return try await encodeResponse(add(session: session))
    case OcaMethodID("3.5"):
      let session: OcaMediaTransportSession = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await configure(session: session)
      return Ocp1Response()
    case OcaMethodID("3.6"):
      let id: OcaMediaTransportSessionID = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await delete(session: id)
      return Ocp1Response()
    case OcaMethodID("3.7"):
      let id: OcaMediaTransportSessionID = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await reset(session: id)
      return Ocp1Response()
    case OcaMethodID("3.8"):
      let parameters: Parameters.SetStreamingEnabledParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await set(session: parameters.sessionID, streamingEnabled: parameters.enabled)
      return Ocp1Response()
    case OcaMethodID("3.9"):
      let id: OcaMediaTransportSessionID = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await startStreaming(session: id)
      return Ocp1Response()
    case OcaMethodID("3.10"):
      let id: OcaMediaTransportSessionID = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await stopStreaming(session: id)
      return Ocp1Response()
    case OcaMethodID("3.12"):
      let id: OcaMediaTransportSessionID = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try encodeResponse(sessionStatus(id))
    case OcaMethodID("3.13"):
      let parameters: Parameters.AddConnectionParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      return try await encodeResponse(add(
        connection: parameters.connection,
        to: parameters.sessionID
      ))
    case OcaMethodID("3.14"):
      let parameters: Parameters.ConfigureConnectionParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await configureConnection(
        sessionID: parameters.sessionID,
        connectionID: parameters.connectionID,
        localEndpointID: parameters.localEndpointID,
        remoteEndpointID: parameters.remoteEndpointID
      )
      return Ocp1Response()
    case OcaMethodID("3.15"):
      let parameters: Parameters.SessionConnectionParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await delete(connection: parameters.connectionID, from: parameters.sessionID)
      return Ocp1Response()
    case OcaMethodID("3.16"):
      let id: OcaMediaTransportSessionID = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await deleteConnections(session: id)
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
