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
@_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
import SwiftOCASecure
import SwiftOCASecureDevice
@preconcurrency import XCTest

/// Fail-closed configuration checks for the OpenSSL backend: a missing /
/// unreadable CA bundle must surface as a configuration error at
/// connection / endpoint init, not silently drop the verify policy.
final class TLSFailClosedTests: XCTestCase {
  private static let testIdentity = OcaPreSharedKeyIdentityHint
  private static let testKey = Data(repeating: 0x42, count: 32)
  private static let nonexistentCAPath = "/nonexistent/no-such-ca-\(UUID().uuidString).pem"

  private func loopbackAddress(port: UInt16) -> sockaddr_in {
    var sin = sockaddr_in()
    sin.sin_family = sa_family_t(AF_INET)
    sin.sin_port = port.bigEndian
    sin.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian // 127.0.0.1
    return sin
  }

  /// Cert-mode client init with a non-existent CA file must throw rather
  /// than silently fall back to "any cert from any CA passes."
  @OcaConnection
  func testClientWithMissingCAFileThrows() async throws {
    guard let (certPath, keyPath) = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available")
    }
    defer {
      let dir = (certPath as NSString).deletingLastPathComponent
      try? FileManager.default.removeItem(atPath: dir)
    }
    XCTAssertThrowsError(
      try Ocp1OpenSSLConnection(
        host: "127.0.0.1",
        port: 65535,
        credential: .certificateFile(certPath: certPath, keyPath: keyPath),
        trustRoots: .caFile(Self.nonexistentCAPath),
        options: Ocp1ConnectionOptions()
      ),
      "init must throw when the configured CA file is unreadable"
    )
  }

  /// Server-side mTLS endpoint init with a non-existent client CA file
  /// must throw — the alternative is logging "mTLS enabled" while every
  /// client cert is accepted.
  func testServerWithMissingClientCAFileThrows() async throws {
    guard let (certPath, keyPath) = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available")
    }
    defer {
      let dir = (certPath as NSString).deletingLastPathComponent
      try? FileManager.default.removeItem(atPath: dir)
    }
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    await XCTAssertThrowsErrorAsync(try await Ocp1OpenSSLStreamDeviceEndpoint(
      address: loopbackAddress(port: 0),
      credential: .certificateFile(certPath: certPath, keyPath: keyPath),
      clientCertificateTrustRoots: .caFile(Self.nonexistentCAPath),
      timeout: .seconds(5),
      device: device
    ))
  }
}

private func XCTAssertThrowsErrorAsync(
  _ expression: @autoclosure () async throws -> some Any,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail(message.isEmpty ? "expected error was not thrown" : message, file: file, line: line)
  } catch {
    // expected
  }
}

#endif
#endif
