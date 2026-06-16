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

// Regression tests for the Apple-backend TLS findings called out in
// Documentation/TLS-SecurityReview.md (HIGH-1, HIGH-2). The previous
// implementations passed every legitimate cert chain to a server-cert
// policy on the server endpoint, and let a PSK client silently accept a
// server-cert fallback. These tests guard the fail-closed behavior added
// by the fixes.
//
// Scaffolded under `(macOS || iOS) && NonEmbeddedBuild` so they compile
// on Linux but only execute on Apple test runs.

#if (os(macOS) || os(iOS)) && NonEmbeddedBuild

import FlyingSocks
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
import SwiftOCASecure
import SwiftOCASecureDevice
@preconcurrency import XCTest

private func localhostAddress(port: UInt16) -> Data {
  var addr = sockaddr_in()
  addr.sin_family = sa_family_t(AF_INET)
  addr.sin_port = port.bigEndian
  addr.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
  #if canImport(Darwin)
  addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  #endif
  return withUnsafeBytes(of: addr) { Data($0) }
}

/// `Ocp1NWSecureTCPConnection.init` is `@OcaConnection`-isolated; hop
/// onto the actor to construct one from an XCTestCase method.
@OcaConnection
private func makePSKClientWithTrustRoots(
  port: UInt16,
  hostname: String,
  caData: Data
) throws -> Ocp1NWSecureTCPConnection {
  try Ocp1NWSecureTCPConnection(
    deviceAddress: localhostAddress(port: port),
    credential: .preSharedKey(
      identity: OcaPreSharedKeyIdentityHint,
      key: Data(repeating: 0x42, count: 32)
    ),
    sniHostname: hostname,
    trustRoots: .caData(caData)
  )
}

@OcaConnection
private func makePSKClient(
  port: UInt16,
  identity: String,
  key: Data
) throws -> Ocp1NWSecureTCPConnection {
  try Ocp1NWSecureTCPConnection(
    deviceAddress: localhostAddress(port: port),
    credential: .preSharedKey(identity: identity, key: key)
  )
}

@OcaConnection
private func makeMTLSClient(
  port: UInt16,
  hostname: String,
  p12Data: Data,
  caData: Data
) throws -> Ocp1NWSecureTCPConnection {
  try Ocp1NWSecureTCPConnection(
    deviceAddress: localhostAddress(port: port),
    credential: .pkcs12(data: p12Data, password: testPKCS12Password),
    sniHostname: hostname,
    trustRoots: .caData(caData)
  )
}

private func localhostUDPAddress(port: UInt16) -> Data { localhostAddress(port: port) }

@OcaConnection
private func makePSKDTLSClient(
  port: UInt16,
  identity: String,
  key: Data
) throws -> Ocp1NWSecureUDPConnection {
  try Ocp1NWSecureUDPConnection(
    deviceAddress: localhostUDPAddress(port: port),
    credential: .preSharedKey(identity: identity, key: key)
  )
}

@OcaConnection
private func makePSKDTLSClientWithTrustRoots(
  port: UInt16,
  hostname: String,
  caData: Data
) throws -> Ocp1NWSecureUDPConnection {
  try Ocp1NWSecureUDPConnection(
    deviceAddress: localhostUDPAddress(port: port),
    credential: .preSharedKey(
      identity: OcaPreSharedKeyIdentityHint,
      key: Data(repeating: 0x42, count: 32)
    ),
    sniHostname: hostname,
    trustRoots: .caData(caData)
  )
}

@OcaConnection
private func makeMTLSDTLSClient(
  port: UInt16,
  hostname: String,
  p12Data: Data,
  caData: Data
) throws -> Ocp1NWSecureUDPConnection {
  try Ocp1NWSecureUDPConnection(
    deviceAddress: localhostUDPAddress(port: port),
    credential: .pkcs12(data: p12Data, password: testPKCS12Password),
    sniHostname: hostname,
    trustRoots: .caData(caData)
  )
}

final class AppleTLSPolicyRegressionTests: XCTestCase {
  /// HIGH-2 regression: a PSK-credentialled client MUST NOT silently
  /// authenticate via the server's certificate. Even with a trusted CA
  /// pinned, the connection must fail closed because the client opted
  /// into PSK, not cert auth.
  func testPSKClientRefusesCertOnlyServer() async throws {
    guard let (caCertPath, leafCertPath, leafKeyPath) = try generateCASignedCert(
      leafCommonName: "ocp1-test",
      leafSubjectAltNames: "DNS:ocp1-test,IP:127.0.0.1"
    ) else {
      throw XCTSkip("openssl CLI not on PATH")
    }
    // macOS's PEM-aggregate `SecItemImport` doesn't accept OpenSSL 3's
    // PKCS8 keys; bundle into a PKCS#12 instead.
    guard let p12Path = try pemToPKCS12(certPath: leafCertPath, keyPath: leafKeyPath) else {
      throw XCTSkip("openssl CLI not on PATH")
    }
    let p12Data = try Data(contentsOf: URL(fileURLWithPath: p12Path))

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    // Server credential is cert-only; no PSK loaded on the security manager.
    let endpoint = try await Ocp1NWSecureTCPDeviceEndpoint(
      port: 0,
      credential: .pkcs12(data: p12Data, password: testPKCS12Password),
      device: device
    )
    let task = Task { try await endpoint.run() }
    defer { task.cancel() }
    let port = try await endpoint.awaitBoundPort()

    let caData = try Data(contentsOf: URL(fileURLWithPath: caCertPath))
    let connection = try await makePSKClientWithTrustRoots(
      port: port,
      hostname: "ocp1-test",
      caData: caData
    )
    // The PSK reject-cert verify block must trip during the handshake,
    // surfaced as a thrown error from connectDevice().
    do {
      try await connection.connect()
      XCTFail("PSK client should reject server's cert-only handshake")
      try? await connection.disconnect()
    } catch {
      // expected
    }
  }

  /// HIGH-1 regression: an mTLS server MUST validate client certs with
  /// the *client-auth* SSL policy. `generateCASignedCert` mints a leaf
  /// with `extendedKeyUsage=serverAuth` only — using it as the *client's*
  /// cert in an mTLS handshake should be rejected by the server. Without
  /// the policy-role fix the server would have accepted it.
  func testMTLSServerRejectsServerAuthEKUCert() async throws {
    guard let (caCertPath, leafCertPath, leafKeyPath) = try generateCASignedCert(
      leafCommonName: "ocp1-test",
      leafSubjectAltNames: "DNS:ocp1-test,IP:127.0.0.1"
    ) else {
      throw XCTSkip("openssl CLI not on PATH")
    }
    guard let p12Path = try pemToPKCS12(certPath: leafCertPath, keyPath: leafKeyPath) else {
      throw XCTSkip("openssl CLI not on PATH")
    }
    let p12Data = try Data(contentsOf: URL(fileURLWithPath: p12Path))
    let caData = try Data(contentsOf: URL(fileURLWithPath: caCertPath))

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await Ocp1NWSecureTCPDeviceEndpoint(
      port: 0,
      credential: .pkcs12(data: p12Data, password: testPKCS12Password),
      clientCertificateTrustRoots: .caData(caData), // mTLS on
      device: device
    )
    let task = Task { try await endpoint.run() }
    defer { task.cancel() }
    let port = try await endpoint.awaitBoundPort()

    // Client presents the *same* leaf — same CA, serverAuth-only EKU.
    let connection = try await makeMTLSClient(
      port: port,
      hostname: "ocp1-test",
      p12Data: p12Data,
      caData: caData
    )
    do {
      try await connection.connect()
      // TLS 1.3 mTLS: server validates the client cert *after* its Finished,
      // so the client's `.ready` can win the race with the rejection alert
      // and `connect()` returns successfully. Wait for the alert to land
      // and the connection to tear down; on backends that validate during
      // the handshake (OpenSSL) `connect()` throws and the catch fires.
      try await Task.sleep(for: .seconds(1))
      let stillConnected = await connection.isConnected
      try? await connection.disconnect()
      XCTAssertFalse(
        stillConnected,
        "server should reject client cert that has only serverAuth EKU"
      )
    } catch {
      // expected
    }
  }

  /// HIGH-2 DTLS regression: PSK DTLS client rejects cert-only server.
  /// Mirror of `testPSKClientRefusesCertOnlyServer` for `Ocp1NWSecureUDP*`.
  func testPSKDTLSClientRefusesCertOnlyServer() async throws {
    guard let (caCertPath, leafCertPath, leafKeyPath) = try generateCASignedCert(
      leafCommonName: "ocp1-test",
      leafSubjectAltNames: "DNS:ocp1-test,IP:127.0.0.1"
    ) else {
      throw XCTSkip("openssl CLI not on PATH")
    }
    guard let p12Path = try pemToPKCS12(certPath: leafCertPath, keyPath: leafKeyPath) else {
      throw XCTSkip("openssl CLI not on PATH")
    }
    let p12Data = try Data(contentsOf: URL(fileURLWithPath: p12Path))
    let caData = try Data(contentsOf: URL(fileURLWithPath: caCertPath))

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await Ocp1NWSecureUDPDeviceEndpoint(
      port: 0,
      credential: .pkcs12(data: p12Data, password: testPKCS12Password),
      device: device
    )
    let task = Task { try await endpoint.run() }
    defer { task.cancel() }
    let port = try await endpoint.awaitBoundPort()

    let connection = try await makePSKDTLSClientWithTrustRoots(
      port: port,
      hostname: "ocp1-test",
      caData: caData
    )
    do {
      try await connection.connect()
      XCTFail("DTLS PSK client should reject server's cert-only handshake")
      try? await connection.disconnect()
    } catch {
      // expected
    }
  }

  /// HIGH-1 DTLS regression: mirror of the TCP test for the UDP endpoint.
  /// The verify helper is shared, but explicit coverage guards against a
  /// future refactor that diverges the two.
  func testMTLSServerRejectsServerAuthEKUCertOnDTLS() async throws {
    guard let (caCertPath, leafCertPath, leafKeyPath) = try generateCASignedCert(
      leafCommonName: "ocp1-test",
      leafSubjectAltNames: "DNS:ocp1-test,IP:127.0.0.1"
    ) else {
      throw XCTSkip("openssl CLI not on PATH")
    }
    guard let p12Path = try pemToPKCS12(certPath: leafCertPath, keyPath: leafKeyPath) else {
      throw XCTSkip("openssl CLI not on PATH")
    }
    let p12Data = try Data(contentsOf: URL(fileURLWithPath: p12Path))
    let caData = try Data(contentsOf: URL(fileURLWithPath: caCertPath))

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await Ocp1NWSecureUDPDeviceEndpoint(
      port: 0,
      credential: .pkcs12(data: p12Data, password: testPKCS12Password),
      clientCertificateTrustRoots: .caData(caData),
      device: device
    )
    let task = Task { try await endpoint.run() }
    defer { task.cancel() }
    let port = try await endpoint.awaitBoundPort()

    let connection = try await makeMTLSDTLSClient(
      port: port,
      hostname: "ocp1-test",
      p12Data: p12Data,
      caData: caData
    )
    do {
      try await connection.connect()
      try await Task.sleep(for: .seconds(1))
      let stillConnected = await connection.isConnected
      try? await connection.disconnect()
      XCTAssertFalse(
        stillConnected,
        "DTLS server should reject client cert with only serverAuth EKU"
      )
    } catch {
      // expected
    }
  }

  /// MEDIUM-4 regression: a wrong-PSK client must throw promptly from
  /// `connectDevice()` (via the `.waiting(error)` hook) rather than hang.
  func testWrongPSKConnectFailsFast() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    try await device.securityManager.loadPreSharedKey(
      identity: OcaPreSharedKeyIdentityHint,
      key: Data(repeating: 0x42, count: 32)
    )

    let endpoint = try await Ocp1NWSecureTCPDeviceEndpoint(
      port: 0,
      device: device
    )
    let task = Task { try await endpoint.run() }
    defer { task.cancel() }
    let port = try await endpoint.awaitBoundPort()

    let connection = try await makePSKClient(
      port: port,
      identity: OcaPreSharedKeyIdentityHint,
      key: Data(repeating: 0xCD, count: 32) // wrong key
    )
    // Fail-fast: ≤5 s is generous; before the `.waiting(error)` fix the
    // call would hang until the (much larger) connection timeout.
    let start = ContinuousClock.now
    do {
      try await connection.connect()
      XCTFail("wrong PSK should fail the handshake")
      try? await connection.disconnect()
    } catch {
      let elapsed = ContinuousClock.now - start
      XCTAssertLessThan(
        elapsed, .seconds(5),
        "wrong-PSK should fail fast via .waiting(error), not hang"
      )
    }
  }
}

#endif
