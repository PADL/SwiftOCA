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

import FlyingSocks
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

// MARK: - helpers

/// Get the port assigned by the OS after binding to port 0
private func boundPort(of socket: Socket) throws -> UInt16 {
  let address = try socket.sockname()
  switch address {
  case let .ip4(_, port):
    return port
  case let .ip6(_, port):
    return port
  default:
    throw SocketError.unsupportedAddress
  }
}

/// Create a sockaddr_in for 127.0.0.1 on the given port
private func localhostAddress(port: UInt16) -> Data {
  var addr = sockaddr_in()
  addr.sin_family = sa_family_t(AF_INET)
  addr.sin_port = port.bigEndian
  addr.sin_addr.s_addr = UInt32(0x7f_00_00_01).bigEndian // 127.0.0.1
  #if canImport(Darwin)
  addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  #endif
  return withUnsafeBytes(of: addr) { Data($0) }
}

/// Create a TCP endpoint on an OS-assigned port and return the endpoint, socket, and port
private func makeTCPEndpoint(
  device: OcaDevice,
  timeout: Duration = .seconds(5)
) async throws -> (Ocp1FlyingSocksStreamDeviceEndpoint, Socket, UInt16) {
  let serverAddress = localhostAddress(port: 0)
  let endpoint = try await Ocp1FlyingSocksStreamDeviceEndpoint(
    address: serverAddress,
    timeout: timeout,
    device: device
  )
  let socket = try await endpoint.preparePoolAndSocket()
  let port = try boundPort(of: socket)
  return (endpoint, socket, port)
}

/// Create and connect a TCP client to the given port
@OcaConnection
private func makeTCPConnection(
  port: UInt16
) async throws -> Ocp1FlyingSocksStreamConnection {
  let clientAddress = localhostAddress(port: port)
  let connection = try Ocp1FlyingSocksStreamConnection(
    deviceAddress: clientAddress,
    options: Ocp1ConnectionOptions(flags: .refreshDeviceTreeOnConnection)
  )
  return connection
}

// MARK: - tests

final class KeepAliveTests: XCTestCase {
  /// Both sides have keepalive: client sends keepalives (heartbeatTime=1s by default),
  /// server picks up the interval from the first keepalive PDU.
  /// Connection should remain alive for several heartbeat periods.
  func testBothKeepAlives() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (endpoint, socket, port) = try await makeTCPEndpoint(device: device, timeout: .seconds(3))
    let endpointTask = Task { try await endpoint._run(on: socket, pool: endpoint.pool) }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = try await makeTCPConnection(port: port)
    try await connection.connect()

    var connected = await connection.isConnected
    XCTAssertTrue(connected)

    // Wait for several heartbeat intervals — connection should remain alive
    try await Task.sleep(for: .seconds(3))
    connected = await connection.isConnected
    XCTAssertTrue(connected, "Connection dropped despite active keepalives")

    // Verify device manager is reachable
    let deviceManagerONo = await connection.deviceManager.objectNumber
    XCTAssertEqual(deviceManagerONo, OcaDeviceManagerONo)

    try await connection.disconnect()
  }

  /// Neither side has keepalive: uses OcaLocalConnection (heartbeatTime=.zero) and
  /// OcaLocalDeviceEndpoint (timeout=.zero). Connection should remain alive
  /// indefinitely since no staleness checks are performed.
  func testNoKeepAlive() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)

    let connection = await OcaLocalConnection(endpoint)
    let endpointTask = Task { try? await endpoint.run() }
    defer { endpointTask.cancel() }

    try await connection.connect()

    var connected = await connection.isConnected
    XCTAssertTrue(connected)

    // Local connections have heartbeatTime == .zero
    let heartbeat = await connection.heartbeatTime
    XCTAssertEqual(heartbeat, .zero, "Local connection should have zero heartbeat")

    // Wait a while — connection should remain alive without keepalives
    try await Task.sleep(for: .seconds(2))
    connected = await connection.isConnected
    XCTAssertTrue(connected, "Local connection dropped unexpectedly")

    // Verify device manager is reachable after the wait
    let deviceManagerONo = await connection.deviceManager.objectNumber
    XCTAssertEqual(deviceManagerONo, OcaDeviceManagerONo)

    try await connection.disconnect()
  }

  /// Client has keepalive, server has a short timeout. Verify that the server-side
  /// controller stays alive because the client sends keepalive messages.
  func testClientKeepAliveKeepsServerAlive() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (endpoint, socket, port) = try await makeTCPEndpoint(device: device, timeout: .seconds(3))
    let endpointTask = Task { try await endpoint._run(on: socket, pool: endpoint.pool) }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = try await makeTCPConnection(port: port)
    try await connection.connect()

    let connected = await connection.isConnected
    XCTAssertTrue(connected)

    // The server should have exactly 1 controller connected
    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 1, "Expected exactly one controller")

    // Wait for several keepalive intervals — controller should not be evicted
    try await Task.sleep(for: .seconds(3))
    let controllersAfterWait = await endpoint.controllers
    XCTAssertEqual(
      controllersAfterWait.count, 1,
      "Server evicted controller despite receiving keepalives"
    )

    try await connection.disconnect()
  }

  /// Test that connection can be established and immediately used for a round-trip
  /// command with keepalive active (TCP).
  func testTCPRoundTripWithKeepAlive() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (endpoint, socket, port) = try await makeTCPEndpoint(device: device)
    let endpointTask = Task { try await endpoint._run(on: socket, pool: endpoint.pool) }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = try await makeTCPConnection(port: port)
    try await connection.connect()

    // Verify round-trip communication works alongside keepalive
    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "rootBlock should have members")

    // Wait, then do another round-trip to verify keepalive kept things alive
    try await Task.sleep(for: .seconds(2))
    let membersAgain = try await connection.rootBlock.resolveActionObjects()
    XCTAssertEqual(members.count, membersAgain.count)

    try await connection.disconnect()
  }

  /// Test that a local connection (no keepalive) can perform round-trip commands.
  func testLocalRoundTripNoKeepAlive() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)

    let connection = await OcaLocalConnection(endpoint)
    let endpointTask = Task { try? await endpoint.run() }
    defer { endpointTask.cancel() }

    try await connection.connect()

    // Verify round-trip communication works without keepalive
    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "rootBlock should have members")

    // Wait, then do another round-trip
    try await Task.sleep(for: .seconds(1))
    let membersAgain = try await connection.rootBlock.resolveActionObjects()
    XCTAssertEqual(members.count, membersAgain.count)

    try await connection.disconnect()
  }

  /// Verify that after disconnection, the server-side controller is cleaned up.
  func testControllerCleanupAfterDisconnect() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (endpoint, socket, port) = try await makeTCPEndpoint(device: device, timeout: .seconds(3))
    let endpointTask = Task { try await endpoint._run(on: socket, pool: endpoint.pool) }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = try await makeTCPConnection(port: port)
    try await connection.connect()

    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 1)

    try await connection.disconnect()

    // Give the server time to detect disconnection and clean up
    try await Task.sleep(for: .seconds(1))
    let controllersAfterDisconnect = await endpoint.controllers
    XCTAssertEqual(
      controllersAfterDisconnect.count, 0,
      "Server controller was not cleaned up after client disconnected"
    )
  }
}

#endif
