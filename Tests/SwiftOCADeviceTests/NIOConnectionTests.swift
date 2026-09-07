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

// Tests for the opt-in SwiftNIO + NIOSSL TLS backend. Gated on the
// `SwiftNIOBackend` package trait so default builds don't compile these and
// don't pull NIO into the test image. The cert-only scope of the backend
// shapes coverage: PSK + SecIdentity + revocation are construction-time
// rejects, so they're checked with `XCTAssertThrowsError`; the rest of the
// suite drives real end-to-end handshakes against the platform-native
// backend (OpenSSL on Linux, Network.framework on Apple).

#if SwiftNIOBackend && NonEmbeddedBuild

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
import SwiftOCASecure
@testable import SwiftOCASecureDevice
@preconcurrency import XCTest

// MARK: - Helpers

private func loopbackAddressData(port: UInt16) -> Data {
  var sin = sockaddr_in()
  sin.sin_family = sa_family_t(AF_INET)
  sin.sin_port = port.bigEndian
  sin.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian // 127.0.0.1
  #if canImport(Darwin)
  sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  #endif
  return withUnsafeBytes(of: sin) { Data($0) }
}

/// `Ocp1Connection`-derived initialisers expect `@OcaConnection` isolation
/// to match the convention the existing per-backend tests use. Wrapping
/// keeps the failure mode obvious (isolation mismatch) versus letting the
/// compiler infer a default executor.
@OcaConnection
private func makeNIOClient(
  port: UInt16,
  credential: Ocp1TLSCredential,
  hostname: String? = nil,
  trustRoots: Ocp1TLSTrustRoots? = nil,
  revocation: Ocp1TLSRevocationOptions = .disabled,
  flags: Ocp1ConnectionFlags = [.refreshDeviceTreeOnConnection, .disableCertificateVerification]
) throws -> Ocp1NIOSecureTCPConnection {
  try Ocp1NIOSecureTCPConnection(
    deviceAddress: loopbackAddressData(port: port),
    credential: credential,
    hostname: hostname,
    trustRoots: trustRoots,
    revocation: revocation,
    options: Ocp1ConnectionOptions(flags: flags)
  )
}

@OcaDevice
private func makeNIOServer(
  credential: Ocp1TLSCredential,
  clientCertificateTrustRoots: Ocp1TLSTrustRoots? = nil,
  timeout: Duration = .seconds(5)
) async throws -> Ocp1NIOSecureTCPDeviceEndpoint {
  let device = OcaDevice()
  try await device.initializeDefaultObjects()
  return try await Ocp1NIOSecureTCPDeviceEndpoint(
    port: 0,
    credential: credential,
    clientCertificateTrustRoots: clientCertificateTrustRoots,
    timeout: timeout,
    device: device
  )
}

/// Spin up an endpoint and wait until its accept-loop has bound a port.
/// The endpoint binds eagerly inside `run()`, so we poll `port` rather
/// than racing with the background task on a fixed-duration sleep.
private func startServer(
  _ endpoint: Ocp1NIOSecureTCPDeviceEndpoint
) async throws -> (port: UInt16, task: Task<Void, Error>) {
  let task = Task { try await endpoint.run() }
  for _ in 0..<50 {
    let p = endpoint.port
    if p != 0 { return (p, task) }
    try await Task.sleep(for: .milliseconds(20))
  }
  task.cancel()
  XCTFail("endpoint did not bind within 1s")
  throw Ocp1Error.notConnected
}

private func awaitTeardown(_ task: Task<Void, Error>) async {
  task.cancel()
  _ = try? await task.value
}

// MARK: - Tests

final class NIOConnectionTests: XCTestCase {
  /// Self-signed PEM round trip: client trusts the server cert via
  /// `.disableCertificateVerification` so the test stays self-contained.
  /// Asserts the handshake succeeds, the connection reports TLS, and
  /// the `rootBlock` round-trips a full OCP.1 query.
  func testCertPEMRoundTrip() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available; cannot generate self-signed cert")
    }
    defer { try? FileManager.default.removeItem(
      atPath: (cert.certPath as NSString).deletingLastPathComponent
    ) }

    let endpoint = try await makeNIOServer(
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath)
    )
    let (port, task) = try await startServer(endpoint)

    let conn = try await makeNIOClient(
      port: port,
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath)
    )
    try await conn.connect()
    let isUp = await conn.isConnected
    XCTAssertTrue(isUp)
    let hasTLS = await conn.hasTransportLayerSecurity
    XCTAssertTrue(hasTLS, "Ocp1NIOSecureTCPConnection should report hasTransportLayerSecurity")

    let members = try await conn.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty)

    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 1)
    if let c = controllers.first {
      XCTAssertTrue(c.flags.contains(.hasTransportLayerSecurity))
    }
    try await conn.disconnect()
    await awaitTeardown(task)
  }

  /// PKCS#12 credential path. Generates a self-signed PEM via openssl,
  /// converts to a P12 with `pemToPKCS12`, and round-trips through both
  /// sides. Verifies `NIOSSLPKCS12Bundle` consumption against the same
  /// `testPKCS12Password` the Network.framework tests use.
  func testPKCS12RoundTrip() async throws {
    guard let cert = try generateSelfSignedCert(),
          let p12Path = try pemToPKCS12(certPath: cert.certPath, keyPath: cert.keyPath)
    else {
      throw XCTSkip("openssl CLI not available; cannot generate PKCS#12 bundle")
    }
    defer { try? FileManager.default.removeItem(
      atPath: (cert.certPath as NSString).deletingLastPathComponent
    ) }

    let p12Data = try Data(contentsOf: URL(fileURLWithPath: p12Path))
    let credential = Ocp1TLSCredential.pkcs12(data: p12Data, password: testPKCS12Password)

    let endpoint = try await makeNIOServer(credential: credential)
    let (port, task) = try await startServer(endpoint)

    let conn = try await makeNIOClient(port: port, credential: credential)
    try await conn.connect()
    let isConnected = await conn.isConnected
    XCTAssertTrue(isConnected)
    let members = try await conn.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty)
    try await conn.disconnect()
    await awaitTeardown(task)
  }

  /// mTLS: same self-signed cert serves as the trust anchor for both
  /// directions. After handshake, the server-side controller's
  /// `peerIdentity` must reflect the client leaf as `.certificate(...)`
  /// with a non-empty SHA-256 fingerprint — that's the ACL hook.
  func testMutualTLSWithPeerIdentity() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available; cannot generate self-signed cert")
    }
    defer { try? FileManager.default.removeItem(
      atPath: (cert.certPath as NSString).deletingLastPathComponent
    ) }

    let endpoint = try await makeNIOServer(
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
      clientCertificateTrustRoots: .caFile(cert.certPath)
    )
    let (port, task) = try await startServer(endpoint)

    let conn = try await makeNIOClient(
      port: port,
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
      hostname: "ocp1-test",
      trustRoots: .caFile(cert.certPath),
      // Verify the server cert against the supplied trust root, not the
      // system store — this is the realistic mTLS deployment posture.
      flags: [.refreshDeviceTreeOnConnection]
    )
    try await conn.connect()
    let isConnected = await conn.isConnected
    XCTAssertTrue(isConnected)

    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 1)
    if let c = controllers.first {
      switch c.peerIdentity {
      case let .certificate(subject, fingerprint):
        XCTAssertFalse(fingerprint.isEmpty, "fingerprint must be set for mTLS peer")
        XCTAssertEqual(fingerprint.count, 64, "SHA-256 fingerprint is 64 hex chars")
        XCTAssertTrue(
          subject.contains("ocp1-test"),
          "subject string should embed the cert CN; got: \(subject)"
        )
      default:
        XCTFail("expected .certificate peer identity, got \(c.peerIdentity)")
      }
    }
    try await conn.disconnect()
    await awaitTeardown(task)
  }

  // MARK: - Negative construction (cert-only scope contract)

  /// PSK credential is rejected synchronously at client construction —
  /// BoringSSL doesn't ship the AES70 §11.2.4 cipher and we don't
  /// substitute TLS 1.3 external PSK on this backend.
  func testPSKCredentialThrowsAtConnect() async throws {
    let conn = try await makeNIOClient(
      port: 1, // bind target irrelevant — must fail before connect()
      credential: .preSharedKey(
        identity: OcaPreSharedKeyIdentityHint,
        key: Data(repeating: 0x42, count: 32)
      )
    )
    do {
      try await conn.connect()
      try? await conn.disconnect()
      XCTFail("PSK credential must be rejected on the NIO backend")
    } catch Ocp1Error.notImplemented {
      // Expected — Ocp1NIOTLSConfiguration throws on PSK.
    } catch {
      XCTFail("expected Ocp1Error.notImplemented, got \(error)")
    }
  }

  /// Non-empty revocation flags throw rather than being silently
  /// honoured-without-CRLs (NIOSSL doesn't expose CRL/OCSP config).
  func testRevocationFlagsThrowAtConnect() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available")
    }
    defer { try? FileManager.default.removeItem(
      atPath: (cert.certPath as NSString).deletingLastPathComponent
    ) }
    let conn = try await makeNIOClient(
      port: 1,
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
      revocation: .init(flags: .strict)
    )
    do {
      try await conn.connect()
      try? await conn.disconnect()
      XCTFail("revocation flags must be rejected on the NIO backend")
    } catch Ocp1Error.notImplemented {
      // Expected.
    } catch {
      XCTFail("expected Ocp1Error.notImplemented, got \(error)")
    }
  }

  /// Hostname-mismatch: cert SAN is `ocp1-test` only (deliberately no
  /// IP SAN — otherwise NIOSSL's identity check would match the
  /// loopback IP we connect on and the test would be moot). Client
  /// passes `wrong-host` with full verification. NIOSSL's verifier
  /// should reject before the OCP.1 layer sees any bytes.
  func testHostnameMismatchRejected() async throws {
    guard let cert = try generateSelfSignedCert(
      subjectAltNames: "DNS:ocp1-test"
    ) else {
      throw XCTSkip("openssl CLI not available")
    }
    defer { try? FileManager.default.removeItem(
      atPath: (cert.certPath as NSString).deletingLastPathComponent
    ) }

    let endpoint = try await makeNIOServer(
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath)
    )
    let (port, task) = try await startServer(endpoint)

    let conn = try await makeNIOClient(
      port: port,
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
      hostname: "wrong-host",
      trustRoots: .caFile(cert.certPath),
      flags: [.refreshDeviceTreeOnConnection]
    )
    do {
      try await conn.connect()
      try? await conn.disconnect()
      XCTFail("hostname mismatch should be rejected")
    } catch {
      // Expected — exact error varies; .notConnected after handshake fail.
    }
    await awaitTeardown(task)
  }

  // MARK: - Cross-backend interop (Linux ↔ OpenSSL)

  #if os(Linux) && canImport(COpenSSL) && canImport(IORing)

  /// NIO client connecting to an OpenSSL-engine server. Validates the
  /// on-wire OCP.1 framing + NIO's NIOSSL handshake against the existing
  /// Linux server stack. mTLS so the server-side peer identity capture
  /// gets exercised against a NIO client cert.
  func testNIOClientAgainstOpenSSLServer() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available")
    }
    defer { try? FileManager.default.removeItem(
      atPath: (cert.certPath as NSString).deletingLastPathComponent
    ) }

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await Ocp1OpenSSLStreamDeviceEndpoint(
      address: loopbackSockaddrIn(port: 0),
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
      clientCertificateTrustRoots: .caFile(cert.certPath),
      timeout: .seconds(5),
      device: device
    )
    let port = endpoint.port
    let task = Task { try await endpoint.run() }
    defer { task.cancel() }
    try await Task.sleep(for: .milliseconds(100))

    let conn = try await makeNIOClient(
      port: port,
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
      hostname: "ocp1-test",
      trustRoots: .caFile(cert.certPath),
      flags: [.refreshDeviceTreeOnConnection]
    )
    try await conn.connect()
    let isConnected = await conn.isConnected
    XCTAssertTrue(isConnected)
    let members = try await conn.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty)
    try await conn.disconnect()
    await awaitTeardown(task)
  }

  /// OpenSSL client connecting to a NIO server. Symmetric to the above —
  /// confirms the NIO server's `NIOSSLServerHandler` + handshake-handoff
  /// loop interoperates with the existing OpenSSL client engine.
  func testOpenSSLClientAgainstNIOServer() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available")
    }
    defer { try? FileManager.default.removeItem(
      atPath: (cert.certPath as NSString).deletingLastPathComponent
    ) }

    let endpoint = try await makeNIOServer(
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
      clientCertificateTrustRoots: .caFile(cert.certPath)
    )
    let (port, task) = try await startServer(endpoint)

    let conn = try await makeOpenSSLClient(
      port: port,
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
      hostname: "ocp1-test",
      trustRoots: .caFile(cert.certPath)
    )
    try await conn.connect()
    let isConnected = await conn.isConnected
    XCTAssertTrue(isConnected)
    let members = try await conn.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty)
    try await conn.disconnect()
    await awaitTeardown(task)
  }

  #endif // Linux / OpenSSL cross-tests

  // MARK: - Cross-backend interop (Apple ↔ Network.framework)

  #if canImport(Network)

  /// NIO client connecting to an Apple Network.framework server. The NW
  /// server runs without mTLS so the test stays self-contained on
  /// `disableCertificateVerification`; the cross-backend axis under test
  /// is the SSL stack, not the auth model.
  func testNIOClientAgainstNetworkFrameworkServer() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available")
    }
    defer { try? FileManager.default.removeItem(
      atPath: (cert.certPath as NSString).deletingLastPathComponent
    ) }
    guard let p12Path = try pemToPKCS12(certPath: cert.certPath, keyPath: cert.keyPath) else {
      throw XCTSkip("PKCS#12 export failed")
    }
    let p12Data = try Data(contentsOf: URL(fileURLWithPath: p12Path))

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await Ocp1NWSecureTCPDeviceEndpoint(
      port: 0,
      credential: .pkcs12(data: p12Data, password: testPKCS12Password),
      timeout: .seconds(5),
      device: device
    )
    let task = Task { try await endpoint.run() }
    defer { task.cancel() }
    let port = try await endpoint.awaitBoundPort()

    let conn = try await makeNIOClient(
      port: port,
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath)
    )
    try await conn.connect()
    let isConnected = await conn.isConnected
    XCTAssertTrue(isConnected)
    let members = try await conn.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty)
    try await conn.disconnect()
    await awaitTeardown(task)
  }

  /// Apple Network.framework client connecting to a NIO server.
  func testNetworkFrameworkClientAgainstNIOServer() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available")
    }
    defer { try? FileManager.default.removeItem(
      atPath: (cert.certPath as NSString).deletingLastPathComponent
    ) }
    guard let p12Path = try pemToPKCS12(certPath: cert.certPath, keyPath: cert.keyPath) else {
      throw XCTSkip("PKCS#12 export failed")
    }
    let p12Data = try Data(contentsOf: URL(fileURLWithPath: p12Path))

    let endpoint = try await makeNIOServer(
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath)
    )
    let (port, task) = try await startServer(endpoint)

    let conn = try await makeNWClient(
      port: port,
      credential: .pkcs12(data: p12Data, password: testPKCS12Password)
    )
    try await conn.connect()
    let isConnected = await conn.isConnected
    XCTAssertTrue(isConnected)
    let members = try await conn.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty)
    try await conn.disconnect()
    await awaitTeardown(task)
  }

  #endif // Network.framework cross-tests
}

// MARK: - Cross-backend client helpers (only compiled where the partner exists)

#if os(Linux) && canImport(COpenSSL) && canImport(IORing)
private func loopbackSockaddrIn(port: UInt16) -> sockaddr_in {
  var sin = sockaddr_in()
  sin.sin_family = sa_family_t(AF_INET)
  sin.sin_port = port.bigEndian
  sin.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
  return sin
}

@OcaConnection
private func makeOpenSSLClient(
  port: UInt16,
  credential: Ocp1TLSCredential,
  hostname: String? = nil,
  trustRoots: Ocp1TLSTrustRoots? = nil
) throws -> Ocp1OpenSSLConnection {
  try Ocp1OpenSSLConnection(
    deviceAddress: loopbackAddressData(port: port),
    credential: credential,
    hostname: hostname,
    trustRoots: trustRoots,
    options: Ocp1ConnectionOptions(flags: .refreshDeviceTreeOnConnection)
  )
}
#endif

#if canImport(Network)
@OcaConnection
private func makeNWClient(
  port: UInt16,
  credential: Ocp1TLSCredential
) throws -> Ocp1NWSecureTCPConnection {
  try Ocp1NWSecureTCPConnection(
    deviceAddress: loopbackAddressData(port: port),
    credential: credential,
    options: Ocp1ConnectionOptions(flags: [
      .refreshDeviceTreeOnConnection,
      .disableCertificateVerification,
    ])
  )
}
#endif

#endif // SwiftNIOBackend && NonEmbeddedBuild
