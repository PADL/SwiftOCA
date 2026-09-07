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

struct CM4TestHarness {
  let device: OcaDevice
  let connection: OcaLocalConnection
  let endpointTask: Task<(), Never>

  static func make() async throws -> CM4TestHarness {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(endpoint)
    try await connection.connect()
    return CM4TestHarness(device: device, connection: connection, endpointTask: endpointTask)
  }

  func resolve<T: SwiftOCA.OcaRoot>(_ objectNumber: OcaONo) async throws -> T {
    try await connection.resolve(object: OcaObjectIdentification(
      oNo: objectNumber,
      classIdentification: T.classIdentification
    ))
  }
}

@OcaDevice
func XCTAssertThrowsStatus(
  _ status: OcaStatus,
  file: StaticString = #filePath,
  line: UInt = #line,
  _ body: @OcaDevice () async throws -> some Any
) async {
  do {
    _ = try await body()
    XCTFail("expected \(status) to be thrown", file: file, line: line)
  } catch let Ocp1Error.status(thrown) {
    XCTAssertEqual(thrown, status, file: file, line: line)
  } catch {
    XCTFail("unexpected error \(error)", file: file, line: line)
  }
}

@OcaDevice
private final class TestMediaTransportApplication: SwiftOCADevice.OcaMediaTransportApplication {
  var appliedCommands = [(OcaMediaStreamEndpointID, OcaMediaStreamEndpointCommand)]()

  override func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.25"):
      throw Ocp1Error.status(.notImplemented)
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }

  override func applyEndpointCommand(
    _ id: OcaMediaStreamEndpointID,
    command: OcaMediaStreamEndpointCommand
  ) async throws {
    _ = try endpoint(id)
    appliedCommands.append((id, command))
  }
}

final class MediaTransportApplicationTests: XCTestCase {
  private static let applicationONo: OcaONo = 0x0001_0010

  @OcaDevice
  private func makeApplication(
    _ harness: CM4TestHarness
  ) async throws -> TestMediaTransportApplication {
    let application = try await TestMediaTransportApplication(
      objectNumber: Self.applicationONo,
      role: "Test Media Transport Application",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    application.maxInputEndpoints = 2
    application.maxOutputEndpoints = 1
    application.ports = [
      OcaPort(owner: Self.applicationONo, id: OcaPortID(mode: .output, index: 1), name: "Ch 1"),
    ]
    let inputCounterSet = try OcaCounterSet(
      id: application.makeEndpointCounterSetID(endpointID: 1),
      counter: [OcaCounter(
        id: OcaMediaStreamInputEndpointCounterID.mediaLocked,
        value: 3,
        initialValue: 0,
        role: "MEDIA_LOCKED",
        notifiers: []
      )]
    )
    application.insert(
      endpoint: OcaMediaStreamEndpoint(idInternal: 1, direction: .input, userLabel: "Input 1"),
      status: OcaMediaStreamEndpointStatus(state: .ready),
      counterSet: inputCounterSet
    )
    application.insert(
      endpoint: OcaMediaStreamEndpoint(idInternal: 1001, direction: .output, userLabel: "Output 1"),
      status: OcaMediaStreamEndpointStatus(state: .running)
    )
    return application
  }

  @OcaDevice
  func testEndpointRoundTrips() async throws {
    let harness = try await CM4TestHarness.make()
    defer { harness.endpointTask.cancel() }
    let application = try await makeApplication(harness)
    let client: SwiftOCA.OcaMediaTransportApplication =
      try await harness.resolve(Self.applicationONo)

    let endpoints = try await client.$endpoints._getValue(client, flags: [])
    XCTAssertEqual(endpoints, application.endpoints)
    let output = try await client.getEndpoint(1001)
    XCTAssertEqual(output.direction, .output)
    let outputStatus = try await client.getEndpointStatus(1001)
    XCTAssertEqual(outputStatus.state, .running)
    let counts = try await client.getMaxEndpointCounts()
    XCTAssertEqual(counts, .init(maxInputEndpoints: 2, maxOutputEndpoints: 1))
    let portName = try await client.getPortName(OcaPortID(mode: .output, index: 1))
    XCTAssertEqual(portName, "Ch 1")

    try await client.setEndpoint(1, userLabel: "Renamed")
    XCTAssertEqual(try application.endpoint(1).userLabel, "Renamed")

    await XCTAssertThrowsStatus(.parameterOutOfRange) { try await client.getEndpoint(7) }
  }

  @OcaDevice
  func testEndpointCommandsAndCounters() async throws {
    let harness = try await CM4TestHarness.make()
    defer { harness.endpointTask.cancel() }
    let application = try await makeApplication(harness)
    let client: SwiftOCA.OcaMediaTransportApplication =
      try await harness.resolve(Self.applicationONo)

    try await client.applyEndpointCommand(1, command: .start)
    XCTAssertEqual(application.appliedCommands.count, 1)
    XCTAssertEqual(application.appliedCommands.first?.0, 1)
    XCTAssertEqual(application.appliedCommands.first?.1, .start)

    await XCTAssertThrowsStatus(.notImplemented) {
      try await client.add(endpoint: OcaMediaStreamEndpoint(idInternal: 2, direction: .input))
    }
    await XCTAssertThrowsStatus(.notImplemented) {
      try await client.setEndpoint(1, alignmentLevel: -18.0)
    }

    let counter = try await client.getEndpointCounter(1, counterID: 1)
    XCTAssertEqual(counter.value, 3)
    try await client.attachEndpointCounterNotifier(endpointID: 1, counterID: 1, oNo: 4096)
    let attached = try await client.getEndpointCounterSet(1)
    XCTAssertEqual(attached.counter(id: 1)?.notifiers, [4096])
    try await client.detachEndpointCounterNotifier(endpointID: 1, counterID: 1, oNo: 4096)
    let detached = try await client.getEndpointCounterSet(1)
    XCTAssertEqual(detached.counter(id: 1)?.notifiers, [])
    let counterSetID = try detached.id.decode(OcaMediaStreamEndpointCounterSetID.self)
    XCTAssertEqual(counterSetID.ownerONo, Self.applicationONo)
    XCTAssertEqual(counterSetID.endpointID, 1)
  }

  @OcaDevice
  func testNetworkInterfaceCounters() async throws {
    let harness = try await CM4TestHarness.make()
    defer { harness.endpointTask.cancel() }
    let interfaceONo: OcaONo = 0x0001_0011
    let interface = try await SwiftOCADevice.OcaNetworkInterface(
      objectNumber: interfaceONo,
      role: "Test Network Interface",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    interface.counterSet = OcaCounterSet(counter: [
      OcaCounter(id: 1, value: 1, initialValue: 0, role: "LINK_UP", notifiers: []),
      OcaCounter(id: 2, value: 0, initialValue: 0, role: "LINK_DOWN", notifiers: []),
    ])
    let client: SwiftOCA.OcaNetworkInterface = try await harness.resolve(interfaceONo)

    try interface.increment(counter: OcaNetworkInterfaceCounterID.linkDown)
    let linkDown = try await client.get(counter: 2)
    XCTAssertEqual(linkDown.value, 1)
    try await client.attach(counter: 1, to: 4096)
    XCTAssertEqual(interface.counterSet.counter(id: 1)?.notifiers, [4096])
    try await client.resetCounters()
    let reset = try await client.get(counter: 2)
    XCTAssertEqual(reset.value, 0)
    await XCTAssertThrowsStatus(.notImplemented) { try await client.apply(command: .restart) }
  }
}

final class PropertyChangesTests: XCTestCase {
  /// `propertyChanges` signals every property once for its current value, then the ID of
  /// each property whose value changes.
  func testPropertyChangesSignalsTheChangedPropertyID() async throws {
    let harness = try await CM4TestHarness.make()
    defer { harness.endpointTask.cancel() }
    let application = try await OcaMediaTransportApplication(
      objectNumber: 0x8000_0001,
      deviceDelegate: harness.device
    )
    let propertyCount = await application.allDevicePropertyKeyPaths.count
    var iterator = await application.propertyChanges.makeAsyncIterator()

    var initial = Set<OcaPropertyID>()
    for _ in 0..<propertyCount {
      if let id = try await iterator.next() { initial.insert(id) }
    }
    XCTAssertEqual(initial.count, propertyCount)

    await Task { @OcaDevice in application.adaptationIdentifier = "changed" }.value
    let changed = try await iterator.next()
    XCTAssertEqual(changed, OcaPropertyID("2.4"))
  }
}
