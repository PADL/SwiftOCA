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

/// After a TLS handshake failure, the Ocp1OpenSSLConnection must report
/// itself as not-connected and a subsequent disconnect must be a clean
/// no-op — the fix at Ocp1OpenSSLConnection.connectDevice nils `_socket`
/// in the throw path so stale transport state isn't visible to callers.
final class OpenSSLHandshakeFailureCleanupTests: XCTestCase {
  private static let serverIdentity = OcaPreSharedKeyIdentityHint
  private static let serverKey = Data(repeating: 0x42, count: 32)
  private static let wrongKey = Data(repeating: 0x55, count: 32)

  private func loopbackAddress(port: UInt16) -> sockaddr_in {
    var sin = sockaddr_in()
    sin.sin_family = sa_family_t(AF_INET)
    sin.sin_port = port.bigEndian
    sin.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
    return sin
  }

  func testWrongPSKLeavesConnectionClean() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    try await device.securityManager.loadPreSharedKey(
      identity: Self.serverIdentity,
      key: Self.serverKey
    )
    let endpoint = try await Ocp1OpenSSLStreamDeviceEndpoint(
      address: loopbackAddress(port: 0),
      timeout: .seconds(5),
      device: device
    )
    let port = endpoint.port
    XCTAssertNotEqual(port, 0)
    let serverTask = Task { try await endpoint.run() }
    defer {
      serverTask.cancel()
      _ = try? Task { try? await serverTask.value }
    }
    try await Task.sleep(for: .milliseconds(100))

    let connection = try await Ocp1OpenSSLConnection(
      host: "127.0.0.1",
      port: port,
      credential: .preSharedKey(identity: Self.serverIdentity, key: Self.wrongKey),
      options: Ocp1ConnectionOptions()
    )

    // The handshake must reject our wrong key.
    await XCTAssertThrowsErrorAsync(try await connection.connect())

    // After the failure the connection should look "not connected", not
    // half-initialised. The previous behaviour stashed the socket before
    // the handshake threw, so disconnect-after-failure / read-after-failure
    // would touch dead transport state.
    let connected = await connection.isConnected
    XCTAssertFalse(connected, "wrong-PSK connect must leave isConnected == false")

    // Disconnect on an already-failed connection must be a safe no-op.
    try? await connection.disconnect()
  }
}

private func XCTAssertThrowsErrorAsync(
  _ expression: @autoclosure () async throws -> some Any,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("expected error was not thrown", file: file, line: line)
  } catch {
    // expected
  }
}

#endif
#endif
