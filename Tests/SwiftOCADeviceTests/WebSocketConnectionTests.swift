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

#if os(macOS) || os(iOS)

import FlyingFox
import FlyingSocks
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

// MARK: - helpers

/// Create a sockaddr_in for 127.0.0.1 on the given port
private func localhostAddress(port: UInt16) -> Data {
  var addr = sockaddr_in()
  addr.sin_family = sa_family_t(AF_INET)
  addr.sin_port = port.bigEndian
  addr.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian // 127.0.0.1
  #if canImport(Darwin)
  addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  #endif
  return withUnsafeBytes(of: addr) { Data($0) }
}

/// Create a WebSocket device endpoint on an OS-assigned port, start it,
/// wait until it is listening, then return the endpoint, its task, and actual port.
private func makeWSEndpoint(
  device: OcaDevice,
  timeout: Duration = .seconds(5)
) async throws -> (Ocp1FlyingFoxDeviceEndpoint, Task<(), Error>, UInt16) {
  let address = localhostAddress(port: 0)
  let endpoint = try await Ocp1FlyingFoxDeviceEndpoint(
    address: address,
    timeout: timeout,
    device: device
  )
  let endpointTask = Task { try await endpoint.run() }
  // Wait for the HTTP server to bind and start listening
  try await endpoint.httpServer.waitUntilListening(timeout: 5)
  guard let listeningAddress = await endpoint.httpServer.listeningAddress else {
    throw Ocp1Error.notConnected
  }
  let port: UInt16
  switch listeningAddress {
  case let .ip4(_, p):
    port = p
  case let .ip6(_, p):
    port = p
  default:
    throw Ocp1Error.notConnected
  }
  return (endpoint, endpointTask, port)
}

/// Create a WebSocket client connection to the given port
@OcaConnection
private func makeWSConnection(
  port: UInt16
) -> Ocp1FlyingFoxConnection {
  Ocp1FlyingFoxConnection(host: "127.0.0.1", port: port)
}

// MARK: - tests

final class WebSocketConnectionTests: XCTestCase {
  /// Test basic connect/disconnect over WebSocket.
  func testWSConnectDisconnect() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let connection = await makeWSConnection(port: port)
    try await connection.connect()

    let connected = await connection.isConnected
    XCTAssertTrue(connected, "WebSocket connection should be connected")

    let deviceManagerONo = await connection.deviceManager.objectNumber
    XCTAssertEqual(deviceManagerONo, OcaDeviceManagerONo)

    try await connection.disconnect()
  }

  /// Test reading and writing the device manager's device name over WebSocket.
  func testWSReadWriteDeviceName() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let expectedName = "WebSocketTestDevice"
    let deviceManager = await device.deviceManager!
    Task { @OcaDevice in deviceManager.deviceName = expectedName }

    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let connection = await makeWSConnection(port: port)
    try await connection.connect()

    let deviceName = try await connection.deviceManager.$deviceName._getValue(
      connection.deviceManager
    )
    XCTAssertEqual(deviceName, expectedName, "Device name should match what was set on the device")

    try await connection.disconnect()
  }

  /// Test round-trip: resolve root block members over WebSocket.
  func testWSRoundTrip() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let connection = await makeWSConnection(port: port)
    try await connection.connect()

    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "rootBlock should have members")

    try await connection.disconnect()
  }

  /// Verify WebSocket connection has no OCP.1 heartbeat (relies on WS ping/pong).
  func testWSNoHeartbeat() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let connection = await makeWSConnection(port: port)
    try await connection.connect()

    let heartbeat = await connection.heartbeatTime
    XCTAssertEqual(heartbeat, .zero, "WebSocket connection should have zero heartbeat")

    // Connection should remain alive without keepalives
    try await Task.sleep(for: .seconds(2))
    let connected = await connection.isConnected
    XCTAssertTrue(connected, "WebSocket connection dropped unexpectedly without keepalive")

    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "rootBlock should still have members after wait")

    try await connection.disconnect()
  }

  /// Test that disconnecting a WebSocket client cleans up the server-side controller.
  func testWSControllerCleanup() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (endpoint, endpointTask, port) = try await makeWSEndpoint(
      device: device,
      timeout: .seconds(3)
    )
    defer { endpointTask.cancel() }

    let connection = await makeWSConnection(port: port)
    try await connection.connect()

    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 1, "Expected exactly one controller")

    try await connection.disconnect()

    // Give the server time to detect disconnection and clean up
    try await Task.sleep(for: .seconds(1))
    let controllersAfterDisconnect = await endpoint.controllers
    XCTAssertEqual(
      controllersAfterDisconnect.count, 0,
      "Server controller was not cleaned up after WebSocket client disconnected"
    )
  }
}

#endif
