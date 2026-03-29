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
  addr.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian // 127.0.0.1
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

// MARK: - connection factory helpers

@OcaConnection
private func makeCFSocketTCPConnection(
  port: UInt16
) throws -> Ocp1CFSocketTCPConnection {
  let clientAddress = localhostAddress(port: port)
  return try Ocp1CFSocketTCPConnection(
    deviceAddress: clientAddress,
    options: Ocp1ConnectionOptions(flags: .refreshDeviceTreeOnConnection)
  )
}

#if canImport(Network)
@OcaConnection
private func makeNWTCPConnection(
  port: UInt16
) throws -> Ocp1NWTCPConnection {
  let clientAddress = localhostAddress(port: port)
  return try Ocp1NWTCPConnection(
    deviceAddress: clientAddress,
    options: Ocp1ConnectionOptions(flags: .refreshDeviceTreeOnConnection)
  )
}
#endif

// MARK: - CFSocket TCP connection tests

final class CFSocketConnectionTests: XCTestCase {
  /// Test basic connect/disconnect with CFSocket TCP client against FlyingSocks server.
  func testCFSocketTCPConnectDisconnect() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (endpoint, socket, port) = try await makeTCPEndpoint(device: device)
    let endpointTask = Task { try await endpoint._run(on: socket, pool: endpoint.pool) }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = try await makeCFSocketTCPConnection(port: port)
    try await connection.connect()

    let connected = await connection.isConnected
    XCTAssertTrue(connected, "CFSocket TCP connection should be connected")

    let deviceManagerONo = await connection.deviceManager.objectNumber
    XCTAssertEqual(deviceManagerONo, OcaDeviceManagerONo)

    try await connection.disconnect()
  }

  /// Test round-trip command with CFSocket TCP client.
  func testCFSocketTCPRoundTrip() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (endpoint, socket, port) = try await makeTCPEndpoint(device: device)
    let endpointTask = Task { try await endpoint._run(on: socket, pool: endpoint.pool) }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = try await makeCFSocketTCPConnection(port: port)
    try await connection.connect()

    // Verify round-trip: resolve root block members
    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "rootBlock should have members")

    // Wait then verify again
    try await Task.sleep(for: .seconds(2))
    let membersAgain = try await connection.rootBlock.resolveActionObjects()
    XCTAssertEqual(members.count, membersAgain.count)

    try await connection.disconnect()
  }

  /// Test that the server detects the CFSocket TCP client disconnecting.
  func testCFSocketTCPControllerCleanup() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (endpoint, socket, port) = try await makeTCPEndpoint(device: device, timeout: .seconds(3))
    let endpointTask = Task { try await endpoint._run(on: socket, pool: endpoint.pool) }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = try await makeCFSocketTCPConnection(port: port)
    try await connection.connect()

    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 1)

    try await connection.disconnect()

    // Give the server time to detect disconnection
    try await Task.sleep(for: .seconds(1))
    let controllersAfterDisconnect = await endpoint.controllers
    XCTAssertEqual(
      controllersAfterDisconnect.count, 0,
      "Server controller was not cleaned up after CFSocket client disconnected"
    )
  }
}

// MARK: - NWConnection TCP connection tests

#if canImport(Network)

final class NWConnectionTests: XCTestCase {
  /// Test basic connect/disconnect with NWConnection TCP client against FlyingSocks server.
  func testNWTCPConnectDisconnect() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (endpoint, socket, port) = try await makeTCPEndpoint(device: device)
    let endpointTask = Task { try await endpoint._run(on: socket, pool: endpoint.pool) }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = try await makeNWTCPConnection(port: port)
    try await connection.connect()

    let connected = await connection.isConnected
    XCTAssertTrue(connected, "NWConnection TCP should be connected")

    let deviceManagerONo = await connection.deviceManager.objectNumber
    XCTAssertEqual(deviceManagerONo, OcaDeviceManagerONo)

    try await connection.disconnect()
  }

  /// Test round-trip command with NWConnection TCP client.
  func testNWTCPRoundTrip() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (endpoint, socket, port) = try await makeTCPEndpoint(device: device)
    let endpointTask = Task { try await endpoint._run(on: socket, pool: endpoint.pool) }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = try await makeNWTCPConnection(port: port)
    try await connection.connect()

    // Verify round-trip: resolve root block members
    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "rootBlock should have members")

    // Wait then verify again
    try await Task.sleep(for: .seconds(2))
    let membersAgain = try await connection.rootBlock.resolveActionObjects()
    XCTAssertEqual(members.count, membersAgain.count)

    try await connection.disconnect()
  }

  /// Test that the server detects the NWConnection TCP client disconnecting.
  func testNWTCPControllerCleanup() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (endpoint, socket, port) = try await makeTCPEndpoint(device: device, timeout: .seconds(3))
    let endpointTask = Task { try await endpoint._run(on: socket, pool: endpoint.pool) }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let connection = try await makeNWTCPConnection(port: port)
    try await connection.connect()

    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 1)

    try await connection.disconnect()

    // Give the server time to detect disconnection
    try await Task.sleep(for: .seconds(1))
    let controllersAfterDisconnect = await endpoint.controllers
    XCTAssertEqual(
      controllersAfterDisconnect.count, 0,
      "Server controller was not cleaned up after NWConnection client disconnected"
    )
  }
}

#endif

#endif
