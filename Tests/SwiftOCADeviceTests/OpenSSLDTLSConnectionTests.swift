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

#if os(Linux)
#if canImport(COpenSSL) && canImport(IORing)

import Foundation
import Glibc
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
import SwiftOCASecure
@testable import SwiftOCASecureDevice
@preconcurrency import XCTest

private func dtlsLoopbackAddress(port: UInt16) -> sockaddr_in {
  var sin = sockaddr_in()
  sin.sin_family = sa_family_t(AF_INET)
  sin.sin_port = port.bigEndian
  sin.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
  return sin
}

private func dtlsLoopbackAddressData(port: UInt16) -> Data {
  let sin = dtlsLoopbackAddress(port: port)
  return withUnsafeBytes(of: sin) { Data($0) }
}

@OcaConnection
private func makeDTLSConnection(
  port: UInt16,
  credential: Ocp1TLSCredential
) throws -> Ocp1OpenSSLDTLSConnection {
  try Ocp1OpenSSLDTLSConnection(
    deviceAddress: dtlsLoopbackAddressData(port: port),
    credential: credential,
    options: Ocp1ConnectionOptions(flags: .refreshDeviceTreeOnConnection)
  )
}

final class OpenSSLDTLSConnectionTests: XCTestCase {
  private static let testIdentity = OcaPreSharedKeyIdentityHint
  private static let testKey = Data(repeating: 0x42, count: 32)

  private func makeSecureServer(
    timeout: Duration = .seconds(5)
  ) async throws -> (Ocp1OpenSSLDTLSDeviceEndpoint, UInt16, Task<Void, Error>) {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    try await device.securityManager.loadPreSharedKey(
      identity: Self.testIdentity,
      key: Self.testKey
    )

    let endpoint = try await Ocp1OpenSSLDTLSDeviceEndpoint(
      address: dtlsLoopbackAddress(port: 0),
      timeout: timeout,
      device: device
    )
    let port = endpoint.port
    XCTAssertNotEqual(port, 0, "endpoint should report bound port after init")
    let task = Task { try await endpoint.run() }
    return (endpoint, port, task)
  }

  /// PSK handshake + round-trip over DTLS. Confirms the engine selects
  /// DTLS_*_method when transport is .datagram, that the per-peer demux on
  /// the server feeds records into the right engine, and that the message
  /// round-trip survives the BIO pump.
  func testDTLSConnectAndRoundTrip() async throws {
    let (endpoint, port, task) = try await makeSecureServer()
    defer { task.cancel() }
    _ = endpoint

    try await Task.sleep(for: .milliseconds(100))

    let connection = try await makeDTLSConnection(
      port: port,
      credential: .preSharedKey(identity: Self.testIdentity, key: Self.testKey)
    )
    try await connection.connect()

    let connected = await connection.isConnected
    XCTAssertTrue(connected, "DTLS PSK connection should establish")
    let hasTLS = await connection.hasTransportLayerSecurity
    XCTAssertTrue(hasTLS, "Ocp1OpenSSLDTLSConnection should report hasTransportLayerSecurity")
    let isDatagram = await connection.isDatagram
    XCTAssertTrue(isDatagram, "Ocp1OpenSSLDTLSConnection should report isDatagram")

    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "rootBlock round-trip over DTLS should succeed")

    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 1)
    if let serverController = controllers.first {
      XCTAssertTrue(
        serverController.flags.contains(.hasTransportLayerSecurity),
        "server-side controller should report hasTransportLayerSecurity"
      )
    }

    try await connection.disconnect()
  }

  /// Wrong PSK key on the client side must not complete the DTLS handshake.
  /// With OpenSSL silently dropping bad-binder ClientHellos rather than
  /// alerting (a deliberate DoS-amplification mitigation), the client's
  /// `connect()` should hit the connection-timeout path and fail.
  func testDTLSPSKWrongKeyRejected() async throws {
    let (endpoint, port, task) = try await makeSecureServer()
    defer { task.cancel() }
    _ = endpoint

    try await Task.sleep(for: .milliseconds(100))

    let wrongKey = Data(repeating: 0x11, count: 32)
    let connection = try await Ocp1OpenSSLDTLSConnection(
      deviceAddress: dtlsLoopbackAddressData(port: port),
      credential: .preSharedKey(identity: Self.testIdentity, key: wrongKey),
      options: Ocp1ConnectionOptions(
        flags: .refreshDeviceTreeOnConnection,
        connectionTimeout: .seconds(2)
      )
    )
    do {
      try await connection.connect()
      XCTFail("Wrong-PSK client should not have completed the DTLS handshake")
    } catch {
      // expected: handshake never completes, connect times out
    }
  }
}

#endif
#endif
