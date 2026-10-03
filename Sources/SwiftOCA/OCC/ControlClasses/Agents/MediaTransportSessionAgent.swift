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

open class OcaMediaTransportSessionAgent: OcaAgent, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.2.20") }
  override open class var classVersion: OcaClassVersionNumber { 1 }

  // MARK: - Parameter structures shared with SwiftOCADevice

  /// The model names SetStreamingEnabled's parameters ID and Active.
  public struct SetStreamingEnabledParameters: OcaParametersReflectable {
    public let id: OcaMediaTransportSessionID
    public let active: OcaBoolean

    public init(id: OcaMediaTransportSessionID, active: OcaBoolean) {
      self.id = id
      self.active = active
    }
  }

  /// ConfigureSession takes the session's identity, label and adaptation data; its
  /// connections and streaming switch have methods of their own.
  public struct ConfigureSessionParameters: OcaParametersReflectable {
    public let idInternal: OcaMediaTransportSessionID
    public let idExternal: OcaBlob
    public let userLabel: OcaString
    public let adaptationData: OcaAdaptationData

    public init(
      idInternal: OcaMediaTransportSessionID,
      idExternal: OcaBlob,
      userLabel: OcaString,
      adaptationData: OcaAdaptationData
    ) {
      self.idInternal = idInternal
      self.idExternal = idExternal
      self.userLabel = userLabel
      self.adaptationData = adaptationData
    }

    public init(_ session: OcaMediaTransportSession) {
      self.init(
        idInternal: session.idInternal,
        idExternal: session.idExternal,
        userLabel: session.userLabel,
        adaptationData: session.adaptationData
      )
    }
  }

  public struct AddConnectionParameters: OcaParametersReflectable {
    public let sessionID: OcaMediaTransportSessionID
    public let connection: OcaMediaTransportSessionConnection

    public init(
      sessionID: OcaMediaTransportSessionID,
      connection: OcaMediaTransportSessionConnection
    ) {
      self.sessionID = sessionID
      self.connection = connection
    }
  }

  /// Parameter shape needs verification against AES70-2A; AES70-22 shows
  /// ConfigureConnection(LocalEndpointID, RemoteEndpointID) with the session implied.
  public struct ConfigureConnectionParameters: OcaParametersReflectable {
    public let sessionID: OcaMediaTransportSessionID
    public let connectionID: OcaMediaTransportSessionConnectionID
    public let localEndpointID: OcaMediaStreamEndpointID
    public let remoteEndpointID: OcaBlob

    public init(
      sessionID: OcaMediaTransportSessionID,
      connectionID: OcaMediaTransportSessionConnectionID,
      localEndpointID: OcaMediaStreamEndpointID,
      remoteEndpointID: OcaBlob
    ) {
      self.sessionID = sessionID
      self.connectionID = connectionID
      self.localEndpointID = localEndpointID
      self.remoteEndpointID = remoteEndpointID
    }
  }

  public struct SessionConnectionParameters: OcaParametersReflectable {
    public let sessionID: OcaMediaTransportSessionID
    public let connectionID: OcaMediaTransportSessionConnectionID

    public init(
      sessionID: OcaMediaTransportSessionID,
      connectionID: OcaMediaTransportSessionConnectionID
    ) {
      self.sessionID = sessionID
      self.connectionID = connectionID
    }
  }

  // MARK: - Properties

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    ocp2GetName: "Type"
  )
  public var sessionType: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.2")
  )
  public var sessions: OcaListProperty<OcaMediaTransportSession>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.11"),
    ocp2GetName: "Sessions"
  )
  public var sessionStatuses: OcaMapProperty<
    OcaMediaTransportSessionID,
    OcaMediaTransportSessionStatus
  >.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.4"),
    getMethodID: OcaMethodID("3.17"),
    setMethodID: OcaMethodID("3.18"),
    ocp2GetName: "Data",
    ocp2SetName: "Data"
  )
  public var adaptationData: OcaProperty<OcaAdaptationData>.PropertyValue

  // MARK: - Sessions

  public static let getSession =
    OcaMethodDescription<OcaMediaTransportSessionID, OcaMediaTransportSession>(
      "3.3",
      name: "GetSession",
      parameterNames: ["ID"],
      resultNames: ["Session"]
    )

  public func getSession(_ id: OcaMediaTransportSessionID) async throws
    -> OcaMediaTransportSession
  {
    try await invoke(Self.getSession, id)
  }

  public static let addSession =
    OcaMethodDescription<OcaMediaTransportSession, OcaMediaTransportSession>(
      "3.4",
      name: "AddSession",
      parameterNames: ["Session"],
      resultNames: ["Session"]
    )

  /// Returns the given descriptor with its IDInternal set to the ID the device allocated.
  @discardableResult
  public func add(session: OcaMediaTransportSession) async throws -> OcaMediaTransportSession {
    try await invoke(Self.addSession, session)
  }

  public static let configureSession =
    OcaMethodDescription<ConfigureSessionParameters, Void>("3.5", name: "ConfigureSession")

  /// Sends the session's IDs, label and adaptation data, which is all ConfigureSession
  /// takes.
  public func configure(session: OcaMediaTransportSession) async throws {
    try await invoke(Self.configureSession, .init(session))
  }

  public static let deleteSession = OcaMethodDescription<OcaMediaTransportSessionID, Void>(
    "3.6",
    name: "DeleteSession",
    parameterNames: ["ID"]
  )

  public func delete(session id: OcaMediaTransportSessionID) async throws {
    try await invoke(Self.deleteSession, id)
  }

  public static let resetSession = OcaMethodDescription<OcaMediaTransportSessionID, Void>(
    "3.7",
    name: "ResetSession",
    parameterNames: ["ID"]
  )

  public func reset(session id: OcaMediaTransportSessionID) async throws {
    try await invoke(Self.resetSession, id)
  }

  public static let setStreamingEnabled = OcaMethodDescription<SetStreamingEnabledParameters, Void>(
    "3.8",
    name: "SetStreamingEnabled",
    parameterNames: ["ID", "Active"]
  )

  public func set(session id: OcaMediaTransportSessionID, streamingEnabled: OcaBoolean) async throws {
    try await invoke(Self.setStreamingEnabled, .init(id: id, active: streamingEnabled))
  }

  public static let startStreaming = OcaMethodDescription<OcaMediaTransportSessionID, Void>(
    "3.9",
    name: "StartStreaming",
    parameterNames: ["ID"]
  )

  public func startStreaming(session id: OcaMediaTransportSessionID) async throws {
    try await invoke(Self.startStreaming, id)
  }

  public static let stopStreaming = OcaMethodDescription<OcaMediaTransportSessionID, Void>(
    "3.10",
    name: "StopStreaming",
    parameterNames: ["ID"]
  )

  public func stopStreaming(session id: OcaMediaTransportSessionID) async throws {
    try await invoke(Self.stopStreaming, id)
  }

  public static let getSessionStatus =
    OcaMethodDescription<OcaMediaTransportSessionID, OcaMediaTransportSessionStatus>(
      "3.12",
      name: "GetSessionStatus",
      parameterNames: ["ID"],
      resultNames: ["Session"]
    )

  public func getSessionStatus(_ id: OcaMediaTransportSessionID) async throws
    -> OcaMediaTransportSessionStatus
  {
    try await invoke(Self.getSessionStatus, id)
  }

  // MARK: - Connections

  public static let addConnection =
    OcaMethodDescription<AddConnectionParameters, OcaMediaTransportSessionConnection>(
      "3.13",
      name: "AddConnection",
      resultNames: ["Connection"]
    )

  /// Returns the given descriptor with its ID set to the ID the device allocated.
  @discardableResult
  public func add(
    connection: OcaMediaTransportSessionConnection,
    to sessionID: OcaMediaTransportSessionID
  ) async throws -> OcaMediaTransportSessionConnection {
    try await invoke(Self.addConnection, .init(sessionID: sessionID, connection: connection))
  }

  public static let configureConnection =
    OcaMethodDescription<ConfigureConnectionParameters, Void>("3.14", name: "ConfigureConnection")

  public func configureConnection(
    sessionID: OcaMediaTransportSessionID,
    connectionID: OcaMediaTransportSessionConnectionID = 1,
    localEndpointID: OcaMediaStreamEndpointID,
    remoteEndpointID: OcaBlob
  ) async throws {
    try await invoke(
      Self.configureConnection,
      .init(
        sessionID: sessionID,
        connectionID: connectionID,
        localEndpointID: localEndpointID,
        remoteEndpointID: remoteEndpointID
      )
    )
  }

  public static let deleteConnection =
    OcaMethodDescription<SessionConnectionParameters, Void>("3.15", name: "DeleteConnection")

  public func delete(
    connection id: OcaMediaTransportSessionConnectionID,
    from sessionID: OcaMediaTransportSessionID
  ) async throws {
    try await invoke(Self.deleteConnection, .init(sessionID: sessionID, connectionID: id))
  }

  public static let deleteConnections = OcaMethodDescription<OcaMediaTransportSessionID, Void>(
    "3.16",
    name: "DeleteConnections",
    parameterNames: ["SessionID"]
  )

  public func deleteConnections(session id: OcaMediaTransportSessionID) async throws {
    try await invoke(Self.deleteConnections, id)
  }
}
