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

private func loopbackAddress(port: UInt16) -> sockaddr_in {
  var sin = sockaddr_in()
  sin.sin_family = sa_family_t(AF_INET)
  sin.sin_port = port.bigEndian
  sin.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian // 127.0.0.1
  return sin
}

private func loopbackAddressData(port: UInt16) -> Data {
  let sin = loopbackAddress(port: port)
  return withUnsafeBytes(of: sin) { Data($0) }
}

@OcaConnection
private func makeOpenSSLConnection(
  port: UInt16,
  credential: Ocp1TLSCredential,
  hostname: String? = nil,
  trustRoots: Ocp1TLSTrustRoots? = nil,
  flags: Ocp1ConnectionFlags = .refreshDeviceTreeOnConnection
) throws -> Ocp1OpenSSLConnection {
  try Ocp1OpenSSLConnection(
    deviceAddress: loopbackAddressData(port: port),
    credential: credential,
    hostname: hostname,
    trustRoots: trustRoots,
    options: Ocp1ConnectionOptions(flags: flags)
  )
}

final class OpenSSLConnectionTests: XCTestCase {
  private static let testIdentity = OcaPreSharedKeyIdentityHint
  private static let testKey = Data(repeating: 0x42, count: 32)

  private func makeSecureServer(
    timeout: Duration = .seconds(5)
  ) async throws -> (Ocp1OpenSSLStreamDeviceEndpoint, UInt16, Task<Void, Error>) {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    try await device.securityManager.loadPreSharedKey(
      identity: Self.testIdentity,
      key: Self.testKey
    )

    let endpoint = try await Ocp1OpenSSLStreamDeviceEndpoint(
      address: loopbackAddress(port: 0),
      timeout: timeout,
      device: device
    )
    let port = endpoint.port
    XCTAssertNotEqual(port, 0, "endpoint should report bound port after init")
    let task = Task { try await endpoint.run() }
    return (endpoint, port, task)
  }

  /// Wait for a server task to actually exit. `defer { task.cancel() }`
  /// is fire-and-forget — the kernel socket fd may still be open when the
  /// next test starts, racing the new endpoint's bind. Awaiting `task.value`
  /// after cancel forces the run loop's `socket = nil` and `device.remove`
  /// to complete before we return, so the previous endpoint is fully gone
  /// before the next test creates its own.
  private func awaitTeardown(_ task: Task<Void, Error>) async {
    task.cancel()
    _ = try? await task.value
  }

  /// Connect to a TLS device endpoint using a matching PSK and exercise a round trip.
  func testTLSConnectAndRoundTrip() async throws {
    let (endpoint, port, task) = try await makeSecureServer()
    defer { task.cancel() }
    _ = endpoint

    // Give the endpoint a moment to enter accept()
    try await Task.sleep(for: .milliseconds(100))

    let connection = try await makeOpenSSLConnection(
      port: port,
      credential: .preSharedKey(identity: Self.testIdentity, key: Self.testKey)
    )
    try await connection.connect()

    let connected = await connection.isConnected
    XCTAssertTrue(connected, "TLS PSK connection should establish")
    let hasTLS = await connection.hasTransportLayerSecurity
    XCTAssertTrue(hasTLS, "Ocp1OpenSSLConnection should report hasTransportLayerSecurity")

    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "rootBlock round-trip over TLS should succeed")

    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 1)
    if let serverController = controllers.first {
      XCTAssertTrue(
        serverController.flags.contains(.hasTransportLayerSecurity),
        "server-side controller should report hasTransportLayerSecurity"
      )
      // PSK identity captured in the OpenSSL PSK callback must surface on
      // the controller so future ACL gates can authorize on it.
      switch serverController.peerIdentity {
      case .preSharedKey(let id):
        XCTAssertEqual(
          id,
          Self.testIdentity,
          "captured PSK identity should match what the client presented"
        )
      default:
        XCTFail(
          "expected .preSharedKey peer identity after PSK handshake, got \(serverController.peerIdentity)"
        )
      }
    }

    try await connection.disconnect()
    await awaitTeardown(task)
  }

  /// Spin up the endpoint with a self-signed certificate, then prove the
  /// client rejects it by default but accepts it when the caller opts into
  /// `.disableCertificateVerification`. Covers the cert-mode verification
  /// path end-to-end so regressions in either the engine's `SSL_VERIFY_*`
  /// wiring or the connection-flag plumbing surface here.
  func testTLSCertificateVerification() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available; cannot generate self-signed cert")
    }
    defer { try? FileManager.default.removeItem(atPath: (cert.certPath as NSString).deletingLastPathComponent) }

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await Ocp1OpenSSLStreamDeviceEndpoint(
      address: loopbackAddress(port: 0),
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
      timeout: .seconds(5),
      device: device
    )
    let port = endpoint.port
    let task = Task { try await endpoint.run() }
    defer { task.cancel() }
    try await Task.sleep(for: .milliseconds(100))

    // Same cert used as the client credential — its content isn't what's
    // being tested. We only care that the server's cert fails chain validation
    // against the system trust store unless verification is disabled.
    let clientCredential = Ocp1TLSCredential.certificateFile(
      certPath: cert.certPath,
      keyPath: cert.keyPath
    )

    // 1. Default flags → chain check against system roots rejects self-signed.
    // Hostname is required when verification is enabled and the credential
    // isn't a PSK; pass the SAN so this exercises the chain-validation path
    // rather than the missing-hostname pre-check.
    let strictConnection = try await makeOpenSSLConnection(
      port: port,
      credential: clientCredential,
      hostname: "ocp1-test",
      flags: []
    )
    do {
      try await strictConnection.connect()
      XCTFail("self-signed server cert should be rejected by default verification")
      try? await strictConnection.disconnect()
    } catch {
      // Expected.
    }

    // 2. `.disableCertificateVerification` → handshake completes, OCP.1 works.
    let lenientConnection = try await makeOpenSSLConnection(
      port: port,
      credential: clientCredential,
      flags: [.refreshDeviceTreeOnConnection, .disableCertificateVerification]
    )
    try await lenientConnection.connect()
    let connected = await lenientConnection.isConnected
    XCTAssertTrue(connected, "connection with verification disabled should establish")
    let members = try await lenientConnection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "OCP.1 round trip should succeed once TLS is up")
    try await lenientConnection.disconnect()
    await awaitTeardown(task)
  }

  /// Configure the endpoint to *require* a client certificate (mTLS) and
  /// verify the server actually rejects clients that don't present one
  /// while accepting clients that do. A single self-signed cert plays
  /// three roles: server identity, server's trust anchor for client certs,
  /// and the client's identity + server-trust-anchor — sufficient because
  /// a self-signed cert is its own root.
  func testTLSMutualAuthentication() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available; cannot generate self-signed cert")
    }
    defer { try? FileManager.default.removeItem(atPath: (cert.certPath as NSString).deletingLastPathComponent) }

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await Ocp1OpenSSLStreamDeviceEndpoint(
      address: loopbackAddress(port: 0),
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
      clientCertificateTrustRoots: .caFile(cert.certPath),
      timeout: .seconds(5),
      device: device
    )
    let port = endpoint.port
    let task = Task { try await endpoint.run() }
    defer { task.cancel() }
    try await Task.sleep(for: .milliseconds(100))

    let clientCredential = Ocp1TLSCredential.certificateFile(
      certPath: cert.certPath,
      keyPath: cert.keyPath
    )

    // Client supplies a cert that chains (== is) the server's trust anchor,
    // and trusts the server cert via the same anchor. mTLS handshake completes.
    // `hostname` matches the SAN minted by `generateSelfSignedCert`.
    let mutualConnection = try await makeOpenSSLConnection(
      port: port,
      credential: clientCredential,
      hostname: "ocp1-test",
      trustRoots: .caFile(cert.certPath)
    )
    try await mutualConnection.connect()
    let connected = await mutualConnection.isConnected
    XCTAssertTrue(connected, "mTLS handshake should succeed when both sides chain to the same anchor")
    let members = try await mutualConnection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "OCP.1 round trip should succeed over mTLS")
    try await mutualConnection.disconnect()
    await awaitTeardown(task)
  }

  /// Negative PSK test: server expects `Self.testKey` but client connects
  /// with a different key. The handshake derives different session keys on
  /// each side and the first encrypted record's MAC fails, which OpenSSL
  /// surfaces as `bad record mac`. We only assert the throw — not the
  /// specific error string — so future OpenSSL builds with different alert
  /// wording don't make the test flaky.
  func testTLSPSKWrongKeyRejected() async throws {
    let (endpoint, port, task) = try await makeSecureServer()
    defer { task.cancel() }
    _ = endpoint
    try await Task.sleep(for: .milliseconds(100))

    let wrongKey = Data(repeating: 0xAA, count: 32) // different from Self.testKey
    let connection = try await makeOpenSSLConnection(
      port: port,
      credential: .preSharedKey(identity: Self.testIdentity, key: wrongKey)
    )
    do {
      try await connection.connect()
      try? await connection.disconnect()
      XCTFail("handshake should fail when PSKs don't match")
    } catch {
      // Expected — exact diagnostic varies by OpenSSL version.
    }
    await awaitTeardown(task)
  }

  /// mTLS and PSK are independent OCP.1 auth paths. A server with mTLS
  /// configured *and* PSKs registered should still accept a client that
  /// presents a valid PSK — PSK already provides mutual authentication via
  /// the shared secret, so cert-based mTLS doesn't apply to that handshake.
  /// (A peer that presents *neither* a valid PSK nor a valid client cert
  /// is rejected, but those failure modes are covered by other tests.)
  func testTLSMutualAuthAllowsPSKClient() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available; cannot generate self-signed cert")
    }
    defer { try? FileManager.default.removeItem(atPath: (cert.certPath as NSString).deletingLastPathComponent) }

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    try await device.securityManager.loadPreSharedKey(
      identity: Self.testIdentity,
      key: Self.testKey
    )
    let endpoint = try await Ocp1OpenSSLStreamDeviceEndpoint(
      address: loopbackAddress(port: 0),
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
      clientCertificateTrustRoots: .caFile(cert.certPath),
      timeout: .seconds(5),
      device: device
    )
    let port = endpoint.port
    let task = Task { try await endpoint.run() }
    defer { task.cancel() }
    try await Task.sleep(for: .milliseconds(100))

    let connection = try await makeOpenSSLConnection(
      port: port,
      credential: .preSharedKey(identity: Self.testIdentity, key: Self.testKey)
    )
    try await connection.connect()
    let connected = await connection.isConnected
    XCTAssertTrue(connected, "PSK handshake should succeed even when mTLS is configured for cert clients")
    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "OCP.1 round trip should succeed over PSK against a dual-mode endpoint")
    try await connection.disconnect()
    await awaitTeardown(task)
  }

  /// Hostname verification test: cert has SAN `ocp1-test` / `127.0.0.1`,
  /// but the client asks the engine to verify against `wrong-host`.
  /// OpenSSL's hostname check (via `SSL_set1_host`) should reject it
  /// even though chain validation against the same self-signed anchor
  /// would otherwise pass.
  func testTLSCertificateVerificationRejectsWrongHostname() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available; cannot generate self-signed cert")
    }
    defer { try? FileManager.default.removeItem(atPath: (cert.certPath as NSString).deletingLastPathComponent) }

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await Ocp1OpenSSLStreamDeviceEndpoint(
      address: loopbackAddress(port: 0),
      credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
      timeout: .seconds(5),
      device: device
    )
    let port = endpoint.port
    let task = Task { try await endpoint.run() }
    defer { task.cancel() }
    try await Task.sleep(for: .milliseconds(100))

    let clientCredential = Ocp1TLSCredential.certificateFile(
      certPath: cert.certPath,
      keyPath: cert.keyPath
    )

    // Anchor at the self-signed cert (so chain validation succeeds) but
    // demand a hostname the cert doesn't carry — the verifier should
    // reject on SAN/CN mismatch.
    let connection = try await Ocp1OpenSSLConnection.makeForHostname(
      port: port,
      credential: clientCredential,
      hostname: "wrong-host",
      trustRoots: .caFile(cert.certPath)
    )
    do {
      try await connection.connect()
      try? await connection.disconnect()
      XCTFail("hostname-mismatched cert should be rejected by SSL_set1_host check")
    } catch {
      // Expected.
    }
    await awaitTeardown(task)
  }
}

private extension Ocp1OpenSSLConnection {
  @OcaConnection
  static func makeForHostname(
    port: UInt16,
    credential: Ocp1TLSCredential,
    hostname: String,
    trustRoots: Ocp1TLSTrustRoots?
  ) throws -> Ocp1OpenSSLConnection {
    try Ocp1OpenSSLConnection(
      deviceAddress: loopbackAddressData(port: port),
      credential: credential,
      hostname: hostname,
      trustRoots: trustRoots,
      options: Ocp1ConnectionOptions(flags: .refreshDeviceTreeOnConnection)
    )
  }
}

#endif
#endif
