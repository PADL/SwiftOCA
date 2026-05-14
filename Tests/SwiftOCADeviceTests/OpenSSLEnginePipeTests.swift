//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//

#if os(Linux)
#if canImport(COpenSSL) && canImport(IORing)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@_spi(SwiftOCAPrivate)
import SwiftOCA
import SwiftOCASecure
@preconcurrency import XCTest

/// Engine-level round-trip tests that drive `Ocp1OpenSSLEngine` against an
/// in-memory `PipeByteStream` pair — no real socket, no kernel state, no
/// port reuse, no flake from accept-loop overlap. Validates the engine's
/// handshake and read/write paths in isolation from the IORing transport.
final class OpenSSLEnginePipeTests: XCTestCase {
  private static let pskIdentity = "test-id"
  private static let pskKey = Data(repeating: 0xCD, count: 32)

  /// Drive `clientFn` and `serverFn` concurrently against a connected pipe
  /// pair, returning the `(client, server)` results once both finish.
  private func driveBoth<C: Sendable, S: Sendable>(
    client clientFn: @Sendable @escaping (PipeByteStream) async throws -> C,
    server serverFn: @Sendable @escaping (PipeByteStream) async throws -> S
  ) async throws -> (C, S) {
    let (clientPipe, serverPipe) = PipeByteStream.makePair()
    async let clientResult = clientFn(clientPipe)
    async let serverResult = serverFn(serverPipe)
    return try await (clientResult, serverResult)
  }

  // MARK: - PSK round-trip

  func testEnginePSKHandshakeAndRoundTrip() async throws {
    let payload = Data("hello tls".utf8)

    let (clientReceived, serverReceived): (Data, Data) = try await driveBoth(
      client: { stream in
        let engine = try Ocp1OpenSSLEngine(
          mode: .client,
          credential: .preSharedKey(identity: Self.pskIdentity, key: Self.pskKey)
        )
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        // Send our payload then read the server's reply.
        _ = try await engine.write(
          payload,
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        return try await engine.read(
          payload.count,
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
      },
      server: { stream in
        let engine = try Ocp1OpenSSLEngine(
          mode: .server,
          credential: nil,
          serverPSKProvider: TestPSKProvider(keys: [Self.pskIdentity: Self.pskKey])
        )
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        // Echo whatever we receive.
        let inbound = try await engine.read(
          payload.count,
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        _ = try await engine.write(
          inbound,
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        return inbound
      }
    )

    XCTAssertEqual(serverReceived, payload, "server should receive exact client payload")
    XCTAssertEqual(clientReceived, payload, "client should receive echoed payload")
  }

  // MARK: - PSK mismatch

  func testEnginePSKMismatchFailsHandshake() async throws {
    let wrongKey = Data(repeating: 0x11, count: 32)

    do {
      _ = try await driveBoth(
        client: { stream in
          let engine = try Ocp1OpenSSLEngine(
            mode: .client,
            credential: .preSharedKey(identity: Self.pskIdentity, key: wrongKey)
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
            serverPSKProvider: TestPSKProvider(keys: [Self.pskIdentity: Self.pskKey])
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        }
      )
      XCTFail("PSK mismatch should have failed the handshake")
    } catch {
      // Expected — either side may raise the failure first.
    }
  }

  // MARK: - Certificate verification

  /// Server presents a self-signed cert; a strict client (verifyPeer = true,
  /// no trust roots → defaults to system store) refuses the chain.
  /// Engine-level mirror of `OpenSSLConnectionTests.testTLSCertificateVerification`'s
  /// strict path — runs against an in-memory pipe so it can't suffer the
  /// suite-overlap accept-loop flake.
  func testEngineCertVerificationStrictRejectsSelfSigned() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available; cannot generate self-signed cert")
    }
    defer {
      try? FileManager.default.removeItem(
        atPath: (cert.certPath as NSString).deletingLastPathComponent
      )
    }

    do {
      _ = try await driveBoth(
        client: { stream in
          // Hostname matches the cert's SAN so we exercise the actual
          // chain-validation path (which fails because the self-signed
          // cert isn't in the system trust store), rather than tripping
          // the engine's hostname-required pre-check.
          let engine = try Ocp1OpenSSLEngine(
            mode: .client,
            credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
            verifyPeer: true,
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
            credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath)
          )
          try await engine.handshake(
            read: { c in try await stream.read(count: c, awaitingAllRead: false) },
            write: { d in try await stream.write(d) }
          )
          return ()
        }
      )
      XCTFail("strict client should reject self-signed server cert")
    } catch {
      // Expected — error wording varies by OpenSSL version; we only assert
      // the throw, mirroring the full-stack test's contract.
    }
  }

  /// Same self-signed server, but the client opts out of verification
  /// (`verifyPeer: false`) — handshake should succeed. Engine-level mirror
  /// of `OpenSSLConnectionTests.testTLSCertificateVerification`'s lenient path.
  func testEngineCertVerificationDisabledAcceptsSelfSigned() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available; cannot generate self-signed cert")
    }
    defer {
      try? FileManager.default.removeItem(
        atPath: (cert.certPath as NSString).deletingLastPathComponent
      )
    }

    let payload = Data("hello".utf8)
    let (clientReceived, serverReceived): (Data, Data) = try await driveBoth(
      client: { stream in
        let engine = try Ocp1OpenSSLEngine(
          mode: .client,
          credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
          verifyPeer: false
        )
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        _ = try await engine.write(
          payload,
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        return try await engine.read(
          payload.count,
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
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
        let inbound = try await engine.read(
          payload.count,
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        _ = try await engine.write(
          inbound,
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        return inbound
      }
    )
    XCTAssertEqual(serverReceived, payload)
    XCTAssertEqual(clientReceived, payload)
  }

  // MARK: - mTLS (mutual cert authentication)

  /// Both ends present the same self-signed cert and trust the same CA file
  /// (the cert is its own root). Mirror of
  /// `OpenSSLConnectionTests.testTLSMutualAuthentication`.
  func testEngineMutualAuthentication() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available; cannot generate self-signed cert")
    }
    defer {
      try? FileManager.default.removeItem(
        atPath: (cert.certPath as NSString).deletingLastPathComponent
      )
    }

    let payload = Data("mtls hello".utf8)
    let (_, serverReceived): (Data, Data) = try await driveBoth(
      client: { stream in
        // Hostname matches the cert's SAN so the verifier chain check
        // succeeds (the cert is its own anchor and bears the SAN).
        let engine = try Ocp1OpenSSLEngine(
          mode: .client,
          credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
          verifyPeer: true,
          hostname: "ocp1-test",
          trustRoots: .caFile(cert.certPath)
        )
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        _ = try await engine.write(
          payload,
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        return Data()
      },
      server: { stream in
        let engine = try Ocp1OpenSSLEngine(
          mode: .server,
          credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
          clientTrustRoots: .caFile(cert.certPath)
        )
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        return try await engine.read(
          payload.count,
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
      }
    )
    XCTAssertEqual(serverReceived, payload)
  }

  /// mTLS-configured server should still accept a PSK client — PSK provides
  /// mutual authentication via the shared secret, so cert-based mTLS doesn't
  /// apply to that handshake. Mirror of
  /// `OpenSSLConnectionTests.testTLSMutualAuthAllowsPSKClient`.
  func testEngineMutualAuthAllowsPSKClient() async throws {
    guard let cert = try generateSelfSignedCert() else {
      throw XCTSkip("openssl CLI not available; cannot generate self-signed cert")
    }
    defer {
      try? FileManager.default.removeItem(
        atPath: (cert.certPath as NSString).deletingLastPathComponent
      )
    }

    let payload = Data("psk over mtls server".utf8)
    let (_, serverReceived): (Data, Data) = try await driveBoth(
      client: { stream in
        let engine = try Ocp1OpenSSLEngine(
          mode: .client,
          credential: .preSharedKey(identity: Self.pskIdentity, key: Self.pskKey)
        )
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        _ = try await engine.write(
          payload,
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        return Data()
      },
      server: { stream in
        let engine = try Ocp1OpenSSLEngine(
          mode: .server,
          credential: .certificateFile(certPath: cert.certPath, keyPath: cert.keyPath),
          serverPSKProvider: TestPSKProvider(keys: [Self.pskIdentity: Self.pskKey]),
          clientTrustRoots: .caFile(cert.certPath)
        )
        try await engine.handshake(
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
        return try await engine.read(
          payload.count,
          read: { c in try await stream.read(count: c, awaitingAllRead: false) },
          write: { d in try await stream.write(d) }
        )
      }
    )
    XCTAssertEqual(serverReceived, payload)
  }
}

/// In-memory `OcaPreSharedKeyProvider` used by engine pipe tests. Stores a
/// dictionary of identity → key bytes; reads serve directly from that dict.
private struct TestPSKProvider: OcaPreSharedKeyProvider {
  let keys: [String: Data]

  func withPreSharedKey<T>(
    forIdentity identity: String,
    _ body: (UnsafeBufferPointer<UInt8>) throws -> T
  ) rethrows -> T? {
    guard let key = keys[identity] else { return nil }
    return try key.withUnsafeBytes { raw in
      try body(raw.bindMemory(to: UInt8.self))
    }
  }
}

#endif
#endif
