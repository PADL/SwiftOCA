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
  @OcaDeviceMethod(Parameters.Methods.addSession)
  open func addSession(
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

  @OcaDeviceMethod(Parameters.Methods.deleteSession)
  open func deleteSession(id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.resetSession)
  open func resetSession(id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.setStreamingEnabled)
  open func setStreamingEnabled(
    id: OcaMediaTransportSessionID,
    active: OcaBoolean,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.startStreaming)
  open func startStreaming(id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.stopStreaming)
  open func stopStreaming(id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Returns the given descriptor with its ID set to the allocated connection ID.
  @OcaDeviceMethod(Parameters.Methods.addConnection)
  open func addConnection(
    sessionID: OcaMediaTransportSessionID,
    connection: OcaMediaTransportSessionConnection,
    from controller: any OcaController
  ) async throws -> OcaMediaTransportSessionConnection {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.configureConnection)
  open func configureConnection(
    sessionID: OcaMediaTransportSessionID,
    connectionID: OcaMediaTransportSessionConnectionID,
    localEndpointID: OcaMediaStreamEndpointID,
    remoteEndpointID: OcaBlob,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.deleteConnection)
  open func deleteConnection(
    sessionID: OcaMediaTransportSessionID,
    connectionID: OcaMediaTransportSessionConnectionID,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.deleteConnections)
  open func deleteConnections(sessionID: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  // MARK: - Command dispatch

  @OcaDeviceMethod(Parameters.Methods.getSession)
  func getSession(id: OcaMediaTransportSessionID, from controller: any OcaController) throws
    -> OcaMediaTransportSession
  {
    try session(id)
  }

  @OcaDeviceMethod(Parameters.Methods.configureSession)
  func configureSession(
    idInternal: OcaMediaTransportSessionID,
    idExternal: OcaBlob,
    userLabel: OcaString,
    adaptationData: OcaAdaptationData,
    from controller: any OcaController
  ) async throws {
    var session = try session(idInternal)
    session.idExternal = idExternal
    session.userLabel = userLabel
    session.adaptationData = adaptationData
    try await configure(session: session)
  }

  // the model names GetSessionStatus's output Session, like GetSession's
  @OcaDeviceMethod(Parameters.Methods.getSessionStatus)
  func getSessionStatus(id: OcaMediaTransportSessionID, from controller: any OcaController) throws
    -> OcaMediaTransportSessionStatus
  {
    try sessionStatus(id)
  }

}
