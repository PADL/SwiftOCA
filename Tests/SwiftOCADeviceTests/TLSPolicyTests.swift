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

import Foundation
@_spi(SwiftOCAPrivate) import SwiftOCA
@testable import SwiftOCADevice
import SwiftOCASecure
import SwiftOCASecureDevice
@preconcurrency import XCTest

/// Policy-level checks for `Ocp1TLSCredential.validate()` and the security
/// manager's PSK admission path. RFC 9257 §6 mandates ≥128-bit PSKs and
/// non-empty identities; these enforce that at configuration time so the
/// misconfiguration is caught before any handshake runs.
final class TLSPolicyTests: XCTestCase {
  func testValidateRejectsEmptyIdentity() {
    let cred = Ocp1TLSCredential.preSharedKey(
      identity: "",
      key: Data(repeating: 0x42, count: 32)
    )
    XCTAssertThrowsError(try cred.validate())
  }

  func testValidateRejectsShortKey() {
    let cred = Ocp1TLSCredential.preSharedKey(
      identity: OcaPreSharedKeyIdentityHint,
      key: Data(repeating: 0x42, count: OcaMinimumPreSharedKeyLength - 1)
    )
    XCTAssertThrowsError(try cred.validate())
  }

  func testValidateAcceptsBoundary() {
    let cred = Ocp1TLSCredential.preSharedKey(
      identity: OcaPreSharedKeyIdentityHint,
      key: Data(repeating: 0x42, count: OcaMinimumPreSharedKeyLength)
    )
    XCTAssertNoThrow(try cred.validate())
  }

  func testValidateAcceptsNonPSK() {
    // Cert variants don't carry length / identity bytes — `validate()`
    // is a no-op for them. Parse failures surface at TLS-backend load
    // time, not here.
    let cred = Ocp1TLSCredential.certificateFile(
      certPath: "/nonexistent.crt",
      keyPath: "/nonexistent.key"
    )
    XCTAssertNoThrow(try cred.validate())
  }

  func testSecurityManagerRejectsShortPSK() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let shortKey = Data(repeating: 0x00, count: 8) // 64 bits
    await XCTAssertThrowsErrorAsync(try await device.securityManager.loadPreSharedKey(
      identity: OcaPreSharedKeyIdentityHint,
      key: shortKey
    ))
  }

  func testSecurityManagerRejectsEmptyIdentity() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let validKey = Data(repeating: 0x00, count: 32)
    await XCTAssertThrowsErrorAsync(try await device.securityManager.loadPreSharedKey(
      identity: "",
      key: validKey
    ))
  }

  func testSecurityManagerAcceptsValidPSK() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let validKey = Data(repeating: 0x00, count: 32)
    try await device.securityManager.loadPreSharedKey(
      identity: OcaPreSharedKeyIdentityHint,
      key: validKey
    )
    let stored = await device.securityManager.withPreSharedKey(
      forIdentity: OcaPreSharedKeyIdentityHint
    ) { Data(buffer: $0) }
    XCTAssertEqual(stored, validKey)
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
