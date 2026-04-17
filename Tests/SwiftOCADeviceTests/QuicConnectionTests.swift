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

#if canImport(SwiftMsQuicHelper)

import Foundation
import SocketAddress
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
import SwiftMsQuicHelper
@preconcurrency import XCTest

// MARK: - helpers

/// Generate a self-signed certificate for testing using openssl CLI.
private func generateSelfSignedCert() throws -> (certPath: String, keyPath: String) {
  let tmpDir = NSTemporaryDirectory()
  let certPath = (tmpDir as NSString).appendingPathComponent("quic_test_cert.pem")
  let keyPath = (tmpDir as NSString).appendingPathComponent("quic_test_key.pem")

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
  process.arguments = [
    "req", "-x509", "-newkey", "rsa:2048",
    "-keyout", keyPath, "-out", certPath,
    "-days", "1", "-nodes",
    "-subj", "/CN=localhost",
  ]
  process.standardOutput = Pipe()
  process.standardError = Pipe()
  try process.run()
  process.waitUntilExit()

  guard process.terminationStatus == 0 else {
    throw NSError(
      domain: "QuicTest",
      code: Int(process.terminationStatus),
      userInfo: [NSLocalizedDescriptionKey: "Failed to generate self-signed cert"]
    )
  }

  return (certPath, keyPath)
}

private func makeQuicEndpoint(
  device: OcaDevice,
  certPath: String,
  keyPath: String,
  port: UInt16 = 0,
  timeout: Duration = .seconds(5)
) async throws -> Ocp1QuicDeviceEndpoint {
  var addr = sockaddr_in()
  addr.sin_family = sa_family_t(AF_INET)
  addr.sin_port = port.bigEndian
  addr.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian // 127.0.0.1
  let address = addr as any SocketAddress

  return try await Ocp1QuicDeviceEndpoint(
    address: address,
    credential: .certificateFile(certPath: certPath, keyPath: keyPath),
    timeout: timeout,
    device: device
  )
}

@OcaConnection
private func makeQuicConnection(port: UInt16) throws -> Ocp1QuicConnection {
  Ocp1QuicConnection(
    address: "127.0.0.1",
    port: port,
    options: Ocp1ConnectionOptions(flags: [
      .refreshDeviceTreeOnConnection,
      .disableCertificateVerification,
    ])
  )
}

// MARK: - tests

final class QuicConnectionTests: XCTestCase {
  private var certPath: String!
  private var keyPath: String!

  override func setUp() async throws {
    try SwiftMsQuicAPI.open().throwIfFailed()
    let certs = try generateSelfSignedCert()
    certPath = certs.certPath
    keyPath = certs.keyPath
  }

  override func tearDown() async throws {
    SwiftMsQuicAPI.close()
    try? FileManager.default.removeItem(atPath: certPath)
    try? FileManager.default.removeItem(atPath: keyPath)
  }

  /// Test basic QUIC connect and disconnect.
  func testQuicConnectDisconnect() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let endpoint = try await makeQuicEndpoint(
      device: device,
      certPath: certPath,
      keyPath: keyPath,
      port: 0
    )

    let endpointTask = Task { try await endpoint.run() }
    defer { endpointTask.cancel() }

    // Give the server time to start listening
    try await Task.sleep(for: .milliseconds(500))

    let serverPort = endpoint.port
    XCTAssertNotEqual(serverPort, 0, "Server should have been assigned a port")

    let connection = try await makeQuicConnection(port: serverPort)
    try await connection.connect()

    let connected = await connection.isConnected
    XCTAssertTrue(connected, "QUIC connection should be connected")

    try await connection.disconnect()
  }

  /// Test round-trip OCP.1 command over QUIC.
  func testQuicRoundTrip() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let endpoint = try await makeQuicEndpoint(
      device: device,
      certPath: certPath,
      keyPath: keyPath,
      port: 0
    )

    let endpointTask = Task { try await endpoint.run() }
    defer { endpointTask.cancel() }

    try await Task.sleep(for: .milliseconds(500))

    let connection = try await makeQuicConnection(port: endpoint.port)
    try await connection.connect()

    // Verify round-trip: resolve root block members
    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "rootBlock should have members")

    let deviceManagerONo = await connection.deviceManager.objectNumber
    XCTAssertEqual(deviceManagerONo, OcaDeviceManagerONo)

    try await connection.disconnect()
  }
}

#endif
