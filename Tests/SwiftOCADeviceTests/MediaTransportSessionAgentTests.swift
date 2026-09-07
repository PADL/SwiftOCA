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

@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

@OcaDevice
private final class TestSessionAgent: SwiftOCADevice.OcaMediaTransportSessionAgent {
  var configured = [(OcaMediaTransportSessionID, OcaMediaStreamEndpointID, OcaBlob)]()
  var streamingEnabled = [OcaMediaTransportSessionID: OcaBoolean]()

  override func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.9"):
      throw Ocp1Error.status(.notImplemented)
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }

  override func add(session: OcaMediaTransportSession) async throws -> OcaMediaTransportSession {
    var session = session
    session.idInternal = (sessions.map(\.idInternal).max() ?? 0) + 1
    insert(session: session, status: OcaMediaTransportSessionStatus(state: .unconfigured))
    return session
  }

  override func add(
    connection: OcaMediaTransportSessionConnection,
    to sessionID: OcaMediaTransportSessionID
  ) async throws -> OcaMediaTransportSessionConnection {
    var session = try session(sessionID)
    var connection = connection
    connection.id = (session.connections.map(\.id).max() ?? 0) + 1
    session.connections.append(connection)
    try update(session: session)
    return connection
  }

  override func configureConnection(
    sessionID: OcaMediaTransportSessionID,
    connectionID: OcaMediaTransportSessionConnectionID,
    localEndpointID: OcaMediaStreamEndpointID,
    remoteEndpointID: OcaBlob
  ) async throws {
    _ = try session(sessionID)
    configured.append((sessionID, localEndpointID, remoteEndpointID))
  }

  override func set(
    session id: OcaMediaTransportSessionID,
    streamingEnabled: OcaBoolean
  ) async throws {
    var session = try session(id)
    session.streamingEnabled = streamingEnabled
    try update(session: session)
    self.streamingEnabled[id] = streamingEnabled
  }
}

final class MediaTransportSessionAgentTests: XCTestCase {
  private static let agentONo: OcaONo = 0x0001_0020

  @OcaDevice
  private func makeAgent(_ harness: CM4TestHarness) async throws -> TestSessionAgent {
    let agent = try await TestSessionAgent(
      objectNumber: Self.agentONo,
      role: "Test Session Agent",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    agent.sessionType = "OcaTest"
    agent.insert(
      session: OcaMediaTransportSession(
        idInternal: 1,
        connections: [OcaMediaTransportSessionConnection(
          id: 1,
          localEndpointID: 1,
          remoteEndpointID: OcaBlob()
        )],
        connectionStates: [1: .init(localEndpointState: .notReady, remoteEndpointState: .unknown)]
      ),
      status: OcaMediaTransportSessionStatus(state: .unconfigured)
    )
    return agent
  }

  @OcaDevice
  func testSessionRoundTrips() async throws {
    let harness = try await CM4TestHarness.make()
    defer { harness.endpointTask.cancel() }
    let agent = try await makeAgent(harness)
    let client: SwiftOCA.OcaMediaTransportSessionAgent = try await harness.resolve(Self.agentONo)

    let sessionType = try await client.$sessionType._getValue(client, flags: [])
    XCTAssertEqual(sessionType, "OcaTest")
    let sessions = try await client.$sessions._getValue(client, flags: [])
    XCTAssertEqual(sessions, agent.sessions)
    let session = try await client.getSession(1)
    XCTAssertEqual(session.connections.count, 1)
    let status = try await client.getSessionStatus(1)
    XCTAssertEqual(status.state, .unconfigured)

    let remote = OcaBlob([0x00, 0x0B, 0x5E, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00])
    try await client.configureConnection(sessionID: 1, localEndpointID: 1, remoteEndpointID: remote)
    XCTAssertEqual(agent.configured.count, 1)
    XCTAssertEqual(agent.configured.first?.2, remote)

    try await client.set(session: 1, streamingEnabled: true)
    let streaming = try await client.getSession(1)
    XCTAssertTrue(streaming.streamingEnabled)

    // AddSession and AddConnection return the whole descriptor carrying the allocated ID
    let added = try await client.add(session: OcaMediaTransportSession(idInternal: 0))
    XCTAssertEqual(added.idInternal, 2)
    let connection = try await client.add(
      connection: OcaMediaTransportSessionConnection(id: 0, localEndpointID: 5, remoteEndpointID: OcaBlob()),
      to: 2
    )
    XCTAssertEqual(connection.id, 1)
    XCTAssertEqual(connection.localEndpointID, 5)

    await XCTAssertThrowsStatus(.notImplemented) { try await client.startStreaming(session: 1) }
    await XCTAssertThrowsStatus(.notImplemented) { try await client.reset(session: 1) }
    await XCTAssertThrowsStatus(.parameterOutOfRange) { try await client.getSession(9) }
  }

  @OcaDevice
  func testMilanSessionAgent() async throws {
    let harness = try await CM4TestHarness.make()
    defer { harness.endpointTask.cancel() }
    let agentONo: OcaONo = 0x0001_0021
    let agent = try await SwiftOCADevice.MilanOcaMediaTransportSessionAgent(
      objectNumber: agentONo,
      role: "Milan Session Agent",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    agent.insert(session: try SwiftOCADevice.MilanOcaMediaTransportSessionAgent.makeSession(inputEndpointID: 1))
    try agent.update(
      sessionID: 1,
      state: .configured,
      milanStatus: MilanSessionStatusAdaptationData(substate: .sourceNotPresent)
    )
    let client: SwiftOCA.MilanOcaMediaTransportSessionAgent = try await harness.resolve(agentONo)

    let sessionType = try await client.$sessionType._getValue(client, flags: [])
    XCTAssertEqual(sessionType, "OcaMilan")
    let (state, milanStatus) = try await client.milanStatus(for: 1)
    XCTAssertEqual(state, .configured)
    XCTAssertEqual(milanStatus.substate, .sourceNotPresent)
    let session = try await client.getSession(1)
    XCTAssertEqual(
      try session.connections.first?.remoteEndpointID.decode(MilanMediaStreamEndpointIDExternal.self),
      .unbound
    )
    await XCTAssertThrowsStatus(.notImplemented) { try await client.startStreaming(session: 1) }
    await XCTAssertThrowsStatus(.notImplemented) {
      try await client.add(session: OcaMediaTransportSession(idInternal: 2))
    }
    // ConfigureConnection is left to the transport-specific subclass
    await XCTAssertThrowsStatus(.notImplemented) {
      try await client.configureConnection(localEndpointID: 1, remote: .unbound)
    }
  }

  #if NonEmbeddedBuild
  @OcaDevice
  func testSessionStatusesAreTransient() async throws {
    let harness = try await CM4TestHarness.make()
    defer { harness.endpointTask.cancel() }
    let agent = try await makeAgent(harness)

    let serialized = try await agent.serialize()
    XCTAssertNotNil(serialized["3.2"])
    XCTAssertNil(serialized["3.3"])
  }
  #endif
}
