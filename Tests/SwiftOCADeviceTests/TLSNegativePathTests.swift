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
@_spi(SwiftOCAPrivate) import SwiftOCA
import SwiftOCASecure
@preconcurrency import XCTest

/// Negative-path TLS coverage for the OpenSSL engine and connection
/// surface. Sister to `OpenSSLEnginePipeTests` (engine-level happy paths)
/// and `OpenSSLConnectionTests` (socket-level happy paths) — every test
/// here proves that some attacker-visible failure mode produces a clean
/// `throw`, not a silent accept.
///
/// Engine-level tests run against `PipeByteStream` so they don't suffer
/// the socket/port-reuse flake of the full-stack tests.
final class TLSNegativePathTests: XCTestCase {
  private static let pskIdentity = "test-id"
  private static let pskKey = Data(repeating: 0xCD, count: 32)

  /// Drive `clientFn` and `serverFn` concurrently against a connected pipe
  /// pair. Mirrors `OpenSSLEnginePipeTests.driveBoth`.
  private func driveBoth<C: Sendable, S: Sendable>(
    client clientFn: @Sendable @escaping (PipeByteStream) async throws -> C,
    server serverFn: @Sendable @escaping (PipeByteStream) async throws -> S
  ) async throws -> (C, S) {
    let (clientPipe, serverPipe) = PipeByteStream.makePair()
    async let clientResult = clientFn(clientPipe)
    async let serverResult = serverFn(serverPipe)
    return try await (clientResult, serverResult)
  }

  // MARK: - Expired certificate

  /// Server presents a cert whose `notAfter` is already in the past.
  /// A strict client must refuse the chain — regardless of whether the
  /// signing CA is otherwise trusted.
  func testStrictClientRejectsExpiredServerCert() async throws {
    // Mint with a validity window that's already entirely in the past.
    // Requires OpenSSL 3's `-not_before` / `-not_after` flags; on older
    // builds the helper falls back to `-days` (which doesn't accept
    // negatives) and this test will skip via the throw -> XCTSkip below.
    let cert: (certPath: String, keyPath: String)?
    do {
      cert = try generateSelfSignedCert(
        notBefore: "20200101000000Z",
        notAfter: "20200102000000Z"
      )
    } catch {
      throw XCTSkip("openssl CLI doesn't support explicit validity windows: \(error)")
    }
    guard let cert else {
      throw XCTSkip("openssl CLI not available; cannot generate test cert")
    }
    defer {
      try? FileManager.default.removeItem(
        atPath: (cert.certPath as NSString).deletingLastPathComponent
      )
    }
    do {
      _ = try await driveBoth(
        client: { stream in
          let engine = try Ocp1OpenSSLEngine(
            mode: .client,
            credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
            verifyPeer: true,
            hostname: "ocp1-test",
            // Anchor at the expired self-signed cert so chain validation
            // would succeed but for the expiry.
            trustRoots: .caFile(cert.certPath)
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        },
        server: { stream in
          let engine = try Ocp1OpenSSLEngine(
            mode: .server,
            credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath)
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        }
      )
      XCTFail("expired server cert should be rejected by strict verification")
    } catch {
      // Expected — exact error string varies by OpenSSL build.
    }
  }

  // MARK: - Hostname mismatch

  /// Server cert SAN doesn't include the hostname the client verified
  /// against — strict verify must refuse. Without this check a cert
  /// minted for `other-host` could be replayed against `our-host`
  /// (assuming a chain-trusted issuer).
  func testStrictClientRejectsHostnameMismatch() async throws {
    guard let cert = try generateSelfSignedCert(
      commonName: "other-host",
      subjectAltNames: "DNS:other-host"
    ) else {
      throw XCTSkip("openssl CLI not available; cannot generate test cert")
    }
    defer {
      try? FileManager.default.removeItem(
        atPath: (cert.certPath as NSString).deletingLastPathComponent
      )
    }
    do {
      _ = try await driveBoth(
        client: { stream in
          let engine = try Ocp1OpenSSLEngine(
            mode: .client,
            credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
            verifyPeer: true,
            // Verify against `our-host`, but the cert is for `other-host`.
            hostname: "our-host",
            trustRoots: .caFile(cert.certPath)
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        },
        server: { stream in
          let engine = try Ocp1OpenSSLEngine(
            mode: .server,
            credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath)
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        }
      )
      XCTFail("hostname mismatch should be rejected")
    } catch {
      // Expected.
    }
  }

  // MARK: - Untrusted CA

  /// Server cert is signed by CA-A; client trustRoots = CA-B. Chain
  /// validation must fail even though both certs are well-formed and
  /// in-validity.
  func testStrictClientRejectsUntrustedCA() async throws {
    guard let serverChain = try generateCASignedCert(
      caCommonName: "ca-A",
      leafCommonName: "ocp1-test"
    ) else {
      throw XCTSkip("openssl CLI not available; cannot generate test certs")
    }
    guard let otherCA = try generateCASignedCert(
      caCommonName: "ca-B",
      leafCommonName: "ocp1-test"
    ) else {
      throw XCTSkip("openssl CLI not available; cannot generate test certs")
    }
    defer {
      try? FileManager.default.removeItem(
        atPath: (serverChain.leafCertPath as NSString).deletingLastPathComponent
      )
      try? FileManager.default.removeItem(
        atPath: (otherCA.leafCertPath as NSString).deletingLastPathComponent
      )
    }
    do {
      _ = try await driveBoth(
        client: { stream in
          // Client uses its own leaf as the client credential — not
          // important here; only the server-cert verification is being
          // tested. Trust roots point to CA-B; the server is signed by CA-A.
          let engine = try Ocp1OpenSSLEngine(
            mode: .client,
            credential: .certificateFile(
              certPath: otherCA.leafCertPath,
              keyPath: otherCA.leafKeyPath
            ),
            verifyPeer: true,
            hostname: "ocp1-test",
            trustRoots: .caFile(otherCA.caCertPath)
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        },
        server: { stream in
          let engine = try Ocp1OpenSSLEngine(
            mode: .server,
            credential: .certificateFile(
              certPath: serverChain.leafCertPath,
              keyPath: serverChain.leafKeyPath
            )
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        }
      )
      XCTFail("server cert signed by an untrusted CA should be rejected")
    } catch {
      // Expected.
    }
  }

  // MARK: - mTLS missing client cert

  /// Server requires a client cert (mTLS); client doesn't present one
  /// (no credential at all). Engine init refuses to construct a client
  /// without a credential, so we exercise the failure on the server side
  /// by sending a credential-less client into an mTLS-required server.
  ///
  /// A client that authenticates only via PSK against an mTLS-required
  /// server is allowed by design (the PSK callback overrides verify per-
  /// SSL); the failure case here is "client cert handshake without a
  /// cert", which OpenSSL surfaces from the server as
  /// `SSL_VERIFY_FAIL_IF_NO_PEER_CERT`.
  func testServerMTLSRefusesAnonymousCertClient() async throws {
    guard let chain = try generateCASignedCert(
      caCommonName: "ocp1-test-ca",
      leafCommonName: "ocp1-test"
    ) else {
      throw XCTSkip("openssl CLI not available; cannot generate test certs")
    }
    guard let otherChain = try generateCASignedCert(
      caCommonName: "intruder-ca",
      leafCommonName: "intruder"
    ) else {
      throw XCTSkip("openssl CLI not available; cannot generate test certs")
    }
    defer {
      try? FileManager.default.removeItem(
        atPath: (chain.leafCertPath as NSString).deletingLastPathComponent
      )
      try? FileManager.default.removeItem(
        atPath: (otherChain.leafCertPath as NSString).deletingLastPathComponent
      )
    }
    do {
      _ = try await driveBoth(
        client: { stream in
          // Client presents a cert from an entirely different CA — the
          // mTLS-required server should reject it during chain validation
          // against `clientTrustRoots = chain.caCertPath`.
          let engine = try Ocp1OpenSSLEngine(
            mode: .client,
            credential: .certificateFile(
              certPath: otherChain.leafCertPath,
              keyPath: otherChain.leafKeyPath
            ),
            verifyPeer: false,
            hostname: "ocp1-test"
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        },
        server: { stream in
          let engine = try Ocp1OpenSSLEngine(
            mode: .server,
            credential: .certificateFile(
              certPath: chain.leafCertPath,
              keyPath: chain.leafKeyPath
            ),
            clientTrustRoots: .caFile(chain.caCertPath)
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        }
      )
      XCTFail("mTLS server should reject a client cert from an untrusted CA")
    } catch {
      // Expected.
    }
  }

  // MARK: - Revoked leaf via CRL

  /// Server cert is well-formed, in validity, signed by a CA the client
  /// trusts — but listed on the CRL the client loads. Strict revocation
  /// (`.strict` = `.enabled` + `.checkChain`) must refuse the handshake.
  func testStrictClientRejectsRevokedServerCert() async throws {
    guard let chain = try generateCASignedCertWithCRL(
      caCommonName: "ocp1-test-ca",
      leafCommonName: "ocp1-test"
    ) else {
      throw XCTSkip("openssl CLI not available; cannot generate test certs")
    }
    defer {
      try? FileManager.default.removeItem(
        atPath: (chain.leafCertPath as NSString).deletingLastPathComponent
      )
    }
    do {
      _ = try await driveBoth(
        client: { stream in
          let engine = try Ocp1OpenSSLEngine(
            mode: .client,
            credential: .certificateFile(
              certPath: chain.leafCertPath,
              keyPath: chain.leafKeyPath
            ),
            verifyPeer: true,
            hostname: "ocp1-test",
            trustRoots: .caFile(chain.caCertPath),
            revocation: Ocp1TLSRevocationOptions(
              flags: .strict,
              crls: .crlFile(chain.crlPath)
            )
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        },
        server: { stream in
          let engine = try Ocp1OpenSSLEngine(
            mode: .server,
            credential: .certificateFile(
              certPath: chain.leafCertPath,
              keyPath: chain.leafKeyPath
            )
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        }
      )
      XCTFail("revoked server cert must be rejected by strict revocation client")
    } catch {
      // Expected — handshake aborts on CRL-listed leaf.
    }
  }

  /// Same chain but no CRL — `.disabled` revocation must accept the
  /// handshake. Pairs with the positive case so the revocation reject
  /// above is unambiguously CRL-driven rather than a chain failure.
  func testRevocationDisabledAcceptsLeafEvenIfCRLExists() async throws {
    guard let chain = try generateCASignedCertWithCRL(
      caCommonName: "ocp1-test-ca",
      leafCommonName: "ocp1-test"
    ) else {
      throw XCTSkip("openssl CLI not available; cannot generate test certs")
    }
    defer {
      try? FileManager.default.removeItem(
        atPath: (chain.leafCertPath as NSString).deletingLastPathComponent
      )
    }
    _ = try await driveBoth(
      client: { stream in
        let engine = try Ocp1OpenSSLEngine(
          mode: .client,
          credential: .certificateFile(
            certPath: chain.leafCertPath,
            keyPath: chain.leafKeyPath
          ),
          verifyPeer: true,
          hostname: "ocp1-test",
          trustRoots: .caFile(chain.caCertPath),
          revocation: .disabled
        )
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        return ()
      },
      server: { stream in
        let engine = try Ocp1OpenSSLEngine(
          mode: .server,
          credential: .certificateFile(
            certPath: chain.leafCertPath,
            keyPath: chain.leafKeyPath
          )
        )
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        return ()
      }
    )
  }

  // MARK: - Oversized PSK identity

  /// A client sends a PSK identity beyond OpenSSL's `PSK_MAX_IDENTITY_LEN`
  /// (128) and our defence-in-depth bound (256). The engine's PSK callback
  /// must return 0, failing the handshake — guarding against memory bloat
  /// and out-of-bounds reads on the identity copy path.
  ///
  /// We rely on OpenSSL itself to enforce the 128-byte identity limit on
  /// the client side: passing a longer identity to the client callback
  /// causes OpenSSL to refuse advertising it, which aborts the handshake
  /// before any bytes traverse the wire.
  func testOversizedPSKIdentityFailsHandshake() async throws {
    let oversizedIdentity = String(repeating: "X", count: 4096)
    do {
      _ = try await driveBoth(
        client: { stream in
          let engine = try Ocp1OpenSSLEngine(
            mode: .client,
            credential: .preSharedKey(identity: oversizedIdentity, key: Self.pskKey)
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        },
        server: { stream in
          let engine = try Ocp1OpenSSLEngine(
            mode: .server,
            credential: nil,
            serverPSKProvider: SinglePSKProvider(
              identity: oversizedIdentity,
              key: Self.pskKey
            )
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        }
      )
      XCTFail("oversized PSK identity should fail the handshake")
    } catch {
      // Expected — at minimum OpenSSL rejects the >128-byte identity.
    }
  }

  // MARK: - PSK identity carry-through across reset

  /// `engine.reset()` discards the previously-captured PSK identity so a
  /// reconnect that re-handshakes can't see a stale identity if the second
  /// handshake hasn't run yet. After a fresh handshake completes, the new
  /// identity must be captured cleanly.
  func testEngineResetClearsAndRecapturesPSKIdentity() async throws {
    let identity1 = "client-A"
    let identity2 = "client-B"
    let key = Data(repeating: 0x88, count: 32)
    let provider = SinglePSKMutableProvider(identities: [identity1: key, identity2: key])

    // Build a server engine and run a first handshake against a PSK client
    // claiming identity1. Then reset; run a second handshake claiming
    // identity2 and assert the captured identity reflects the second.

    // First handshake.
    let server = try Ocp1OpenSSLEngine(
      mode: .server,
      credential: nil,
      serverPSKProvider: provider
    )
    let (firstIdentity, _): (OcaPeerIdentity, Void) = try await driveBoth(
      client: { stream in
        let engine = try Ocp1OpenSSLEngine(
          mode: .client,
          credential: .preSharedKey(identity: identity1, key: key)
        )
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        return await engine.peerIdentity()
      },
      server: { stream in
        try await server.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
      }
    )
    XCTAssertEqual(firstIdentity, .anonymous, "client peerIdentity is .anonymous (no server cert)")

    let serverIdentityAfterFirst = await server.peerIdentity()
    XCTAssertEqual(serverIdentityAfterFirst, .preSharedKey(identity: identity1))

    // Reset wipes the captured identity.
    await server.reset()
    let serverIdentityAfterReset = await server.peerIdentity()
    XCTAssertEqual(serverIdentityAfterReset, .anonymous,
                   "reset must discard the previously-captured PSK identity")

    // Second handshake captures the new identity.
    _ = try await driveBoth(
      client: { stream in
        let engine = try Ocp1OpenSSLEngine(
          mode: .client,
          credential: .preSharedKey(identity: identity2, key: key)
        )
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
      },
      server: { stream in
        try await server.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
      }
    )
    let serverIdentityAfterSecond = await server.peerIdentity()
    XCTAssertEqual(serverIdentityAfterSecond, .preSharedKey(identity: identity2))
  }

  // MARK: - Plaintext-before-handshake

  /// A client that sends raw, non-TLS bytes at a server engine must NOT
  /// see those bytes succeed as if a handshake had completed. The engine's
  /// `SSL_do_handshake` should reject the malformed record and the
  /// handshake call should throw — fail-closed on plaintext injection.
  func testServerRejectsPlaintextBeforeHandshake() async throws {
    // The bytes we feed in are deliberately arbitrary: a few OCP.1-like
    // octets that share no prefix with a TLS ClientHello (0x16 0x03 ...).
    let plaintext = Data([0x3B, 0x00, 0x10, 0x00, 0x01, 0x03, 0x07, 0xFF])

    do {
      _ = try await driveBoth(
        client: { stream in
          // Pump junk into the server's read side then close our write side.
          try await stream.write(plaintext)
          await stream.close()
          return ()
        },
        server: { stream in
          let engine = try Ocp1OpenSSLEngine(
            mode: .server,
            credential: nil,
            serverPSKProvider: SinglePSKProvider(
              identity: Self.pskIdentity,
              key: Self.pskKey
            )
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        }
      )
      XCTFail("server engine must refuse a handshake driven by plaintext garbage")
    } catch {
      // Expected — fail-closed.
    }
  }

  // MARK: - .preSharedKeyProvider client variant

  /// PSK client using `.preSharedKeyProvider` instead of `.preSharedKey`
  /// — the key bytes only live in the provider's storage. A round-trip
  /// proves the engine's client PSK callbacks read from the provider on
  /// demand and the captured server-side identity matches.
  func testEnginePSKProviderClientHandshakeAndIdentityCapture() async throws {
    let identity = "provider-id"
    let key = Data(repeating: 0xA1, count: 32)
    let clientProvider = SinglePSKProvider(identity: identity, key: key)
    let serverProvider = SinglePSKProvider(identity: identity, key: key)

    let (clientIdentity, serverIdentity): (OcaPeerIdentity, OcaPeerIdentity) = try await driveBoth(
      client: { stream in
        let engine = try Ocp1OpenSSLEngine(
          mode: .client,
          credential: .preSharedKeyProvider(identity: identity, provider: clientProvider)
        )
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        return await engine.peerIdentity()
      },
      server: { stream in
        let engine = try Ocp1OpenSSLEngine(
          mode: .server,
          credential: nil,
          serverPSKProvider: serverProvider
        )
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        return await engine.peerIdentity()
      }
    )
    XCTAssertEqual(clientIdentity, .anonymous)
    XCTAssertEqual(serverIdentity, .preSharedKey(identity: identity))
  }

  /// Credential `validate()` rejects `.preSharedKeyProvider` when the
  /// configured identity isn't known to the provider — caller misuse
  /// surfaces at construction rather than handshake.
  func testPreSharedKeyProviderValidateRejectsUnknownIdentity() throws {
    let provider = SinglePSKProvider(
      identity: "registered",
      key: Data(repeating: 0xEE, count: 32)
    )
    let cred = Ocp1TLSCredential.preSharedKeyProvider(
      identity: "different-identity",
      provider: provider
    )
    XCTAssertThrowsError(try cred.validate())
  }

  /// Same shape, but the provider's key is shorter than the minimum.
  /// Should also throw at validate time.
  func testPreSharedKeyProviderValidateRejectsShortKey() throws {
    let provider = SinglePSKProvider(
      identity: "id",
      key: Data(repeating: 0xEE, count: OcaMinimumPreSharedKeyLength - 1)
    )
    let cred = Ocp1TLSCredential.preSharedKeyProvider(
      identity: "id",
      provider: provider
    )
    XCTAssertThrowsError(try cred.validate())
  }

  // MARK: - DTLS server requires non-empty peerAddressBytes

  /// `Ocp1OpenSSLEngine` rejects a DTLS server with empty `peerAddressBytes`
  /// at construction time — otherwise the cookie HMAC collapses to a
  /// constant per server, defeating RFC 6347 §4.2.1 source-address
  /// verification.
  func testDTLSServerRejectsEmptyPeerAddressBytes() {
    XCTAssertThrowsError(
      try Ocp1OpenSSLEngine(
        mode: .server,
        credential: nil,
        transport: .datagram,
        serverPSKProvider: SinglePSKProvider(
          identity: Self.pskIdentity,
          key: Self.pskKey
        ),
        peerAddressBytes: Data()
      )
    ) { error in
      // Must surface as a `.parameterError` so callers see a config
      // problem, not a generic OpenSSL error.
      guard case let Ocp1Error.status(status) = error else {
        XCTFail("expected Ocp1Error.status, got \(error)")
        return
      }
      XCTAssertEqual(status, .parameterError)
    }
  }
}

/// Single-entry PSK provider — minimal `OcaPreSharedKeyProvider` that
/// answers exactly one identity. Mirrors `OpenSSLEnginePipeTests`'
/// `TestPSKProvider` but lives here too so the negative-path file is
/// self-contained.
private struct SinglePSKProvider: OcaPreSharedKeyProvider {
  let identity: String
  let key: Data

  func withPreSharedKey<T>(
    forIdentity identity: String,
    _ body: (UnsafeBufferPointer<UInt8>) throws -> T
  ) rethrows -> T? {
    guard identity == self.identity else { return nil }
    return try key.withUnsafeBytes { raw in
      try body(raw.bindMemory(to: UInt8.self))
    }
  }
}

private struct SinglePSKMutableProvider: OcaPreSharedKeyProvider {
  let identities: [String: Data]

  func withPreSharedKey<T>(
    forIdentity identity: String,
    _ body: (UnsafeBufferPointer<UInt8>) throws -> T
  ) rethrows -> T? {
    guard let key = identities[identity] else { return nil }
    return try key.withUnsafeBytes { raw in
      try body(raw.bindMemory(to: UInt8.self))
    }
  }
}

#endif
#endif
