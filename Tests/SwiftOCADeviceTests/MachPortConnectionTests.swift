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

#if canImport(Darwin)

@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

private func uniqueServiceName(_ test: String) -> String {
  "com.padl.SwiftOCA.test.machport.\(ProcessInfo.processInfo.processIdentifier).\(test).\(UInt32.random(in: 0...UInt32.max))"
}

@OcaConnection
private func makeMachPortConnection(
  serviceName: String
) -> Ocp1MachPortConnection {
  Ocp1MachPortConnection(
    serviceName: serviceName,
    options: Ocp1ConnectionOptions(flags: .refreshDeviceTreeOnConnection)
  )
}

final class MachPortConnectionTests: XCTestCase {
  func testMachPortConnectDisconnect() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let serviceName = uniqueServiceName("connectDisconnect")
    let endpoint = try await Ocp1MachPortDeviceEndpoint(
      serviceName: serviceName,
      device: device
    )
    let endpointTask = Task { try await endpoint.run() }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = await makeMachPortConnection(serviceName: serviceName)
    try await connection.connect()

    let connected = await connection.isConnected
    XCTAssertTrue(connected, "Mach port connection should be connected")

    let deviceManagerONo = await connection.deviceManager.objectNumber
    XCTAssertEqual(deviceManagerONo, OcaDeviceManagerONo)

    try await connection.disconnect()
  }

  func testMachPortRoundTrip() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let serviceName = uniqueServiceName("roundTrip")
    let endpoint = try await Ocp1MachPortDeviceEndpoint(
      serviceName: serviceName,
      device: device
    )
    let endpointTask = Task { try await endpoint.run() }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = await makeMachPortConnection(serviceName: serviceName)
    try await connection.connect()

    // Verify OCA command round-trip via device manager
    let deviceManagerONo = await connection.deviceManager.objectNumber
    XCTAssertEqual(deviceManagerONo, OcaDeviceManagerONo)

    // Verify we can query the network manager too
    let networkManagerONo = await connection.networkManager.objectNumber
    XCTAssertEqual(networkManagerONo, OcaNetworkManagerONo)

    // Verify actual OCA command round-trip
    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "Root block should have action objects")

    try await connection.disconnect()
  }

  func testMachPortControllerCleanup() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let serviceName = uniqueServiceName("controllerCleanup")
    let endpoint = try await Ocp1MachPortDeviceEndpoint(
      serviceName: serviceName,
      timeout: .seconds(3),
      device: device
    )
    let endpointTask = Task { try await endpoint.run() }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = await makeMachPortConnection(serviceName: serviceName)
    try await connection.connect()

    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 1)

    try await connection.disconnect()

    try await Task.sleep(for: .seconds(1))
    let controllersAfterDisconnect = await endpoint.controllers
    XCTAssertEqual(
      controllersAfterDisconnect.count, 0,
      "Server controller was not cleaned up after Mach port client disconnected"
    )
  }

  func testMachPortMultipleConnections() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let serviceName = uniqueServiceName("multipleConnections")
    let endpoint = try await Ocp1MachPortDeviceEndpoint(
      serviceName: serviceName,
      device: device
    )
    let endpointTask = Task { try await endpoint.run() }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection1 = await makeMachPortConnection(serviceName: serviceName)
    let connection2 = await makeMachPortConnection(serviceName: serviceName)

    try await connection1.connect()
    try await connection2.connect()

    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 2, "Should have two controllers for two connections")

    // Verify both connections can issue OCA commands
    let ono1 = await connection1.deviceManager.objectNumber
    let ono2 = await connection2.deviceManager.objectNumber
    XCTAssertEqual(ono1, ono2)

    try await connection1.disconnect()
    try await connection2.disconnect()
  }

  func testMachPortConnectToNonexistentService() async throws {
    let connection = await makeMachPortConnection(
      serviceName: uniqueServiceName("nonexistent")
    )
    do {
      try await connection.connect()
      XCTFail("Should have thrown when connecting to nonexistent service")
    } catch {
      // expected — bootstrap lookup should fail
    }
  }

  func testMachPortRepeatedConnectDisconnect() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let serviceName = uniqueServiceName("repeatedConnectDisconnect")
    let endpoint = try await Ocp1MachPortDeviceEndpoint(
      serviceName: serviceName,
      device: device
    )
    let endpointTask = Task { try await endpoint.run() }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    for _ in 0..<5 {
      let connection = await makeMachPortConnection(serviceName: serviceName)
      try await connection.connect()

      let connected = await connection.isConnected
      XCTAssertTrue(connected)

      let ono = await connection.deviceManager.objectNumber
      XCTAssertEqual(ono, OcaDeviceManagerONo)

      try await connection.disconnect()
      try await Task.sleep(for: .milliseconds(50))
    }

    try await Task.sleep(for: .seconds(1))
    let controllers = await endpoint.controllers
    XCTAssertEqual(
      controllers.count, 0,
      "All controllers should be cleaned up after repeated connect/disconnect"
    )
  }

  func testMachPortVsTCPLatency() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    // Add 50 actuators to stress-test round-trips
    var actuators = [SwiftOCADevice.OcaBooleanActuator]()
    for i in 0..<50 {
      let actuator = try await SwiftOCADevice.OcaBooleanActuator(
        objectNumber: OcaONo(20000 + i),
        role: "Actuator-\(i)",
        deviceDelegate: device
      )
      actuators.append(actuator)
    }

    let iterations = 10

    // --- Mach port ---
    let machServiceName = uniqueServiceName("perfMach")
    let machEndpoint = try await Ocp1MachPortDeviceEndpoint(
      serviceName: machServiceName,
      device: device
    )
    let machEndpointTask = Task { try await machEndpoint.run() }
    defer { machEndpointTask.cancel() }
    try await Task.sleep(for: .milliseconds(100))

    let machConnection = await makeMachPortConnection(serviceName: machServiceName)
    try await machConnection.connect()

    // warm up
    _ = await machConnection.rootBlock.getJsonValue(flags: [])
    let machStart = ContinuousClock.now
    for _ in 0..<iterations {
      _ = await machConnection.rootBlock.getJsonValue(flags: [])
    }
    let machElapsed = ContinuousClock.now - machStart
    try await machConnection.disconnect()

    // --- TCP (CFSocket) ---
    var listenAddress = sockaddr_in()
    listenAddress.sin_family = sa_family_t(AF_INET)
    listenAddress.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
    listenAddress.sin_port = 0
    listenAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    let addressData = withUnsafeBytes(of: listenAddress) { Data($0) }

    let tcpEndpoint = try await Ocp1FlyingSocksStreamDeviceEndpoint(
      address: addressData,
      device: device
    )
    let socket = try await tcpEndpoint.preparePoolAndSocket()
    let port: UInt16 = try {
      let addr = try socket.sockname()
      switch addr {
      case let .ip4(_, port): return port
      case let .ip6(_, port): return port
      default: throw Ocp1Error.notConnected
      }
    }()
    let tcpEndpointTask = Task { try await tcpEndpoint._run(on: socket, pool: tcpEndpoint.pool) }
    defer { tcpEndpointTask.cancel() }
    try await Task.sleep(for: .milliseconds(100))

    var clientAddr = sockaddr_in()
    clientAddr.sin_family = sa_family_t(AF_INET)
    clientAddr.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
    clientAddr.sin_port = port.bigEndian
    clientAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    let clientAddrData = withUnsafeBytes(of: clientAddr) { Data($0) }

    let tcpConnection = try await {
      @OcaConnection in
      try Ocp1CFSocketTCPConnection(
        deviceAddress: clientAddrData,
        options: Ocp1ConnectionOptions(flags: .refreshDeviceTreeOnConnection)
      )
    }()
    try await tcpConnection.connect()

    // warm up
    _ = await tcpConnection.rootBlock.getJsonValue(flags: [])
    let tcpStart = ContinuousClock.now
    for _ in 0..<iterations {
      _ = await tcpConnection.rootBlock.getJsonValue(flags: [])
    }
    let tcpElapsed = ContinuousClock.now - tcpStart
    try await tcpConnection.disconnect()

    // cleanup
    for actuator in actuators {
      try await device.rootBlock.delete(actionObject: actuator)
    }

    let machMs = Double(machElapsed.components.seconds) * 1000.0
      + Double(machElapsed.components.attoseconds) / 1e15
    let tcpMs = Double(tcpElapsed.components.seconds) * 1000.0
      + Double(tcpElapsed.components.attoseconds) / 1e15

    print("Mach port: \(iterations) iterations in \(String(format: "%.1f", machMs))ms (\(String(format: "%.2f", machMs / Double(iterations)))ms/iter)")
    print("TCP:       \(iterations) iterations in \(String(format: "%.1f", tcpMs))ms (\(String(format: "%.2f", tcpMs / Double(iterations)))ms/iter)")
    print("Speedup:   \(String(format: "%.1f", tcpMs / machMs))x")
  }

  func testMachPortEndpointCancellation() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let serviceName = uniqueServiceName("endpointCancellation")
    let endpoint = try await Ocp1MachPortDeviceEndpoint(
      serviceName: serviceName,
      device: device
    )
    let endpointTask = Task { try await endpoint.run() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = await makeMachPortConnection(serviceName: serviceName)
    try await connection.connect()

    let connected = await connection.isConnected
    XCTAssertTrue(connected)

    // Cancel the endpoint — this should tear down the server side
    endpointTask.cancel()
    try await Task.sleep(for: .milliseconds(500))

    // Client should detect disconnection on next operation
    try await connection.disconnect()
  }
}

#endif
