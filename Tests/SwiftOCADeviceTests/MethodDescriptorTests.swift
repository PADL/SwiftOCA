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

#if NonEmbeddedBuild
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

/// An agent that keeps the sessions AddSession and DeleteSession bring it: the hooks
/// `@OcaDeviceMethod` is on are `open`, and the table reaches these overrides.
@OcaDevice
private final class SessionStore: SwiftOCADevice.OcaMediaTransportSessionAgent {
  override func addSession(
    session: OcaMediaTransportSession,
    from controller: any OcaController
  ) async throws -> OcaMediaTransportSession {
    var session = session
    session.idInternal = (sessions.map(\.idInternal).max() ?? 0) + 1
    insert(session: session, status: OcaMediaTransportSessionStatus(state: .unconfigured))
    return session
  }

  override func deleteSession(id: OcaMediaTransportSessionID, from controller: any OcaController) async throws {
    _ = try session(id)
    remove(sessionID: id)
  }
}

/// The client methods declared by descriptors, round-tripped to the device methods that
/// take the same descriptors.
final class MethodDescriptorTests: XCTestCase {
  private static let workerONo: OcaONo = 0x0001_0030
  private static let agentONo: OcaONo = 0x0001_0031

  @OcaDevice
  func testConvertedMethodsRoundTripOnOcp1() async throws {
    try await roundTrip(.ocp1)
  }

  @OcaDevice
  func testConvertedMethodsRoundTripOnOcp2() async throws {
    try await roundTrip(.ocp2)
  }

  @OcaDevice
  private func roundTrip(_ controlProtocol: OcaControlProtocol) async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device, controlProtocol: controlProtocol)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    defer { endpointTask.cancel() }
    let connection = await OcaLocalConnection(
      endpoint,
      options: OcaConnectionOptions(controlProtocol: controlProtocol)
    )
    try await connection.connect()

    let worker = try await SwiftOCADevice.OcaWorker(
      objectNumber: Self.workerONo,
      role: "Worker",
      deviceDelegate: device
    )
    let portID = OcaPortID(direction: .input, index: 1)
    worker.ports = [OcaPort(owner: worker.objectNumber, id: portID, role: "In 1")]
    let store = try await SessionStore(
      objectNumber: Self.agentONo,
      role: "Sessions",
      deviceDelegate: device
    )
    let client: SwiftOCA.OcaWorker = try await connection.resolve(object: OcaObjectIdentification(
      oNo: Self.workerONo,
      classIdentification: SwiftOCA.OcaWorker.classIdentification
    ))
    let sessions: SwiftOCA.OcaMediaTransportSessionAgent = try await connection
      .resolve(object: OcaObjectIdentification(
        oNo: Self.agentONo,
        classIdentification: SwiftOCA.OcaMediaTransportSessionAgent.classIdentification
      ))

    // SetPortName: two arguments into the shared record
    try await client.setPortName(id: portID, name: "Mic")
    XCTAssertEqual(worker.ports.first?.role, "Mic")
    await XCTAssertThrowsStatus(.parameterOutOfRange) {
      try await client.setPortName(id: OcaPortID(direction: .output, index: 9), name: "None")
    }

    // GetPath: no parameters, a record result
    let path = try await client.getPath()
    XCTAssertEqual(path.rolePath, ["Worker"])
    XCTAssertEqual(path.oNoPath, [Self.workerONo])

    // the port clock map: a scalar parameter named ID, a record result named Entry
    let entry = OcaPortClockMapEntry(clockONo: 0x1234, srcType: .synchronous)
    try await client.setPortClockMapEntry(portID: portID, entry: entry)
    XCTAssertEqual(worker.portClockMap[portID], entry)
    let read = try await client.getPortClockMapEntry(id: portID)
    XCTAssertEqual(read, entry)
    try await client.deletePortClockMapEntry(id: portID)
    XCTAssertTrue(worker.portClockMap.isEmpty)
    await XCTAssertThrowsStatus(.invalidRequest) {
      _ = try await client.getPortClockMapEntry(id: portID)
    }

    // AddSession and GetSession carry a record each way; DeleteSession a scalar named ID
    let added = try await sessions.addSession(session: OcaMediaTransportSession(idInternal: 0, userLabel: "Main"))
    XCTAssertEqual(added.idInternal, 1)
    XCTAssertEqual(added.userLabel, "Main")
    XCTAssertEqual(store.sessions, [added])
    let fetched = try await sessions.getSession(id: 1)
    XCTAssertEqual(fetched, added)
    try await sessions.deleteSession(id: 1)
    XCTAssertTrue(store.sessions.isEmpty)
    await XCTAssertThrowsStatus(.parameterOutOfRange) { try await sessions.getSession(id: 1) }

    try await connection.disconnect()
  }

  /// A descriptor names the OCP.2 parameters as the model does, from its explicit names
  /// and then the record's fields; the client used to send SetPortName's port as `Id`.
  func testDescriptorsNameTheWire() throws {
    let setPortName = SwiftOCA.OcaWorker.Methods.setPortName.erased
    XCTAssertEqual(setPortName.parameters.map(\.name), ["ID", "Name"])
    XCTAssertTrue(setPortName.results.isEmpty)
    let encoded = try Ocp2Encoder().encodeParameters(
      SwiftOCA.OcaWorker.SetPortNameParameters(id: OcaPortID(direction: .input, index: 1), name: "Mic"),
      parameterNames: setPortName.parameterNames
    )
    XCTAssertEqual(Set(encoded.keys), ["ID", "Name"])

    let getPath = SwiftOCA.OcaWorker.Methods.getPath.erased
    XCTAssertTrue(getPath.parameters.isEmpty)
    XCTAssertEqual(getPath.results.map(\.name), ["RolePath", "ONoPath"])

    let getEntry = SwiftOCA.OcaWorker.Methods.getPortClockMapEntry.erased
    XCTAssertEqual(getEntry.parameters.map(\.name), ["ID"])
    XCTAssertTrue(getEntry.parameters[0].type == OcaPortID.self)
    XCTAssertEqual(getEntry.results.map(\.name), ["Entry"])

    let addSession = SwiftOCA.OcaMediaTransportSessionAgent.Methods.addSession.erased
    XCTAssertEqual(addSession.parameters.map(\.name), ["Session"])
    XCTAssertEqual(addSession.results.map(\.name), ["Session"])
  }

  /// The device's table entries for the converted methods are the client's descriptors.
  @OcaDevice
  func testTheDeviceTakesTheClientsDescriptors() async throws {
    let descriptors: [(OcaAnyMethodDescriptor, [OcaDeviceMethodDescriptor])] = [
      (SwiftOCA.OcaWorker.Methods.setPortName.erased, SwiftOCADevice.OcaWorker.deviceMethods),
      (SwiftOCA.OcaWorker.Methods.getPath.erased, SwiftOCADevice.OcaWorker.deviceMethods),
      (SwiftOCA.OcaWorker.Methods.getPortClockMapEntry.erased, SwiftOCADevice.OcaWorker.deviceMethods),
      (SwiftOCA.OcaWorker.Methods.setPortClockMapEntry.erased, SwiftOCADevice.OcaWorker.deviceMethods),
      (SwiftOCA.OcaWorker.Methods.deletePortClockMapEntry.erased, SwiftOCADevice.OcaWorker.deviceMethods),
      (
        SwiftOCA.OcaMediaTransportSessionAgent.Methods.getSession.erased,
        SwiftOCADevice.OcaMediaTransportSessionAgent.deviceMethods
      ),
      (
        SwiftOCA.OcaMediaTransportSessionAgent.Methods.addSession.erased,
        SwiftOCADevice.OcaMediaTransportSessionAgent.deviceMethods
      ),
      (
        SwiftOCA.OcaMediaTransportSessionAgent.Methods.deleteSession.erased,
        SwiftOCADevice.OcaMediaTransportSessionAgent.deviceMethods
      ),
    ]
    for (descriptor, table) in descriptors {
      let entry = try XCTUnwrap(table.first { $0.methodID == descriptor.methodID }, descriptor.name)
      XCTAssertEqual(entry.name, descriptor.name)
      XCTAssertEqual(entry.parameters.map(\.name), descriptor.parameters.map(\.name))
      XCTAssertEqual(entry.results.map(\.name), descriptor.results.map(\.name))
      XCTAssertEqual(
        entry.method.parametersType.map { ObjectIdentifier($0) },
        descriptor.parametersType.map { ObjectIdentifier($0) }
      )
      XCTAssertEqual(
        entry.method.resultType.map { ObjectIdentifier($0) },
        descriptor.resultType.map { ObjectIdentifier($0) }
      )
    }
  }
}
#endif
