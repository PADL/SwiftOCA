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

  public struct SetStreamingEnabledParameters: OcaParametersReflectable {
    public let sessionID: OcaMediaTransportSessionID
    public let enabled: OcaBoolean

    public init(sessionID: OcaMediaTransportSessionID, enabled: OcaBoolean) {
      self.sessionID = sessionID
      self.enabled = enabled
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

  public func getSession(_ id: OcaMediaTransportSessionID) async throws
    -> OcaMediaTransportSession
  {
    try await sendCommandRrq(methodID: OcaMethodID("3.3"), parameters: id, parameterNames: ["ID"])
  }

  /// Returns the given descriptor with its IDInternal set to the ID the device allocated.
  @discardableResult
  public func add(session: OcaMediaTransportSession) async throws -> OcaMediaTransportSession {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.4"),
      parameters: session,
      parameterNames: ["Session"]
    )
  }

  public func configure(session: OcaMediaTransportSession) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.5"), parameters: session)
  }

  public func delete(session id: OcaMediaTransportSessionID) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.6"), parameters: id, parameterNames: ["ID"])
  }

  public func reset(session id: OcaMediaTransportSessionID) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.7"), parameters: id, parameterNames: ["ID"])
  }

  public func set(session id: OcaMediaTransportSessionID, streamingEnabled: OcaBoolean) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.8"),
      parameters: SetStreamingEnabledParameters(sessionID: id, enabled: streamingEnabled)
    )
  }

  public func startStreaming(session id: OcaMediaTransportSessionID) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.9"), parameters: id, parameterNames: ["ID"])
  }

  public func stopStreaming(session id: OcaMediaTransportSessionID) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.10"), parameters: id, parameterNames: ["ID"])
  }

  public func getSessionStatus(_ id: OcaMediaTransportSessionID) async throws
    -> OcaMediaTransportSessionStatus
  {
    try await sendCommandRrq(methodID: OcaMethodID("3.12"), parameters: id, parameterNames: ["ID"])
  }

  // MARK: - Connections

  /// Returns the given descriptor with its ID set to the ID the device allocated.
  @discardableResult
  public func add(
    connection: OcaMediaTransportSessionConnection,
    to sessionID: OcaMediaTransportSessionID
  ) async throws -> OcaMediaTransportSessionConnection {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.13"),
      parameters: AddConnectionParameters(sessionID: sessionID, connection: connection)
    )
  }

  public func configureConnection(
    sessionID: OcaMediaTransportSessionID,
    connectionID: OcaMediaTransportSessionConnectionID = 1,
    localEndpointID: OcaMediaStreamEndpointID,
    remoteEndpointID: OcaBlob
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.14"),
      parameters: ConfigureConnectionParameters(
        sessionID: sessionID,
        connectionID: connectionID,
        localEndpointID: localEndpointID,
        remoteEndpointID: remoteEndpointID
      )
    )
  }

  public func delete(
    connection id: OcaMediaTransportSessionConnectionID,
    from sessionID: OcaMediaTransportSessionID
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.15"),
      parameters: SessionConnectionParameters(sessionID: sessionID, connectionID: id)
    )
  }

  public func deleteConnections(session id: OcaMediaTransportSessionID) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.16"),
      parameters: id,
      parameterNames: ["SessionID"]
    )
  }
}
