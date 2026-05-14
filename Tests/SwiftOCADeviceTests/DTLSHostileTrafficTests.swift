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

// Hostile-network regressions for the Linux DTLS endpoint (HIGH-3 review):
// drive the listener with raw UDP datagrams (no DTLS client engine) and
// assert the pre-cookie defenses contain the per-peer allocation surface.
// We craft just enough of a ClientHello to engage cookie exchange — the
// byte-counting in this file is the kind of thing we deliberately keep
// out of production code, so this test parser is intentionally minimal
// and fails loudly when it doesn't recognize what it received.

#if os(Linux) && canImport(COpenSSL) && canImport(IORing) && NonEmbeddedBuild

import Foundation
import Glibc
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
import SwiftOCASecure
import SwiftOCASecureDevice
@preconcurrency import XCTest

private let loopbackAFamily = sa_family_t(AF_INET)

/// `127.x.0.1` is in the loopback /8 — the kernel routes traffic on every
/// 127.0.0.0/8 address to lo, so distinct `x` values give us distinct
/// source IPs without configuring the interface.
private func loopback(_ thirdOctet: UInt8) -> in_addr {
  in_addr(s_addr: UInt32(0x7F00_0001 | (UInt32(thirdOctet) << 8)).bigEndian)
}

private func sockaddr(ip: in_addr, port: UInt16) -> sockaddr_in {
  var sin = sockaddr_in()
  sin.sin_family = loopbackAFamily
  sin.sin_port = port.bigEndian
  sin.sin_addr = ip
  return sin
}

/// Minimal UDP socket bound to `sourceIP` on an ephemeral port. Caller
/// closes via `close(fd)`. Returns -1 only on test infrastructure failure.
private func openUDPSocket(sourceIP: in_addr = in_addr(s_addr: UInt32(0x7F00_0001).bigEndian)) throws -> Int32 {
  let fd = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
  guard fd >= 0 else { throw POSIXError(.EIO) }
  var src = sockaddr(ip: sourceIP, port: 0)
  let rc = withUnsafePointer(to: &src) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sap in
      Glibc.bind(fd, sap, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  guard rc == 0 else {
    let err = errno
    close(fd)
    throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
  }
  // Receive timeout so a misbehaving test doesn't hang the suite.
  var tv = timeval(tv_sec: 1, tv_usec: 0)
  _ = withUnsafePointer(to: &tv) {
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
  }
  return fd
}

private func sendUDP(_ fd: Int32, bytes: [UInt8], to port: UInt16) throws {
  var dst = sockaddr(ip: in_addr(s_addr: UInt32(0x7F00_0001).bigEndian), port: port)
  let sent = bytes.withUnsafeBufferPointer { buf -> ssize_t in
    withUnsafePointer(to: &dst) { dstp in
      dstp.withMemoryRebound(to: sockaddr.self, capacity: 1) { sap in
        sendto(fd, buf.baseAddress, buf.count, 0, sap, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
  }
  guard sent == bytes.count else { throw POSIXError(.EIO) }
}

private func recvUDP(_ fd: Int32, capacity: Int = 1500) -> [UInt8]? {
  var buf = [UInt8](repeating: 0, count: capacity)
  let n = buf.withUnsafeMutableBufferPointer { Glibc.recv(fd, $0.baseAddress, $0.count, 0) }
  return n > 0 ? Array(buf.prefix(Int(n))) : nil
}

// MARK: - DTLS record assembly (test-only; production code stays free of
// this byte-counting). Layout per RFC 6347; we only emit ClientHello.

/// Build a DTLS 1.2 ClientHello record with the supplied `cookie` bytes.
/// Cipher suites list one PSK suite so the server's cookie exchange fires
/// before any cipher-mismatch rejection.
private func buildClientHello(cookie: [UInt8] = []) -> [UInt8] {
  let dtls12: [UInt8] = [0xFE, 0xFD]
  // Random bytes don't matter for what we test; static counter avoids
  // pulling in a generator.
  let random = [UInt8](repeating: 0xA5, count: 32)
  // Body: client_version(2) random(32) sid_len(1) cookie_len(1) cookie
  //       cipher_suites_len(2) cipher_suites(N) compression_len(1) compression(1)
  let cipherSuites: [UInt8] = [
    0x00, 0x8C, // TLS_PSK_WITH_AES_128_CBC_SHA — PSK suite, engages cookie path
    0x00, 0xFF, // TLS_EMPTY_RENEGOTIATION_INFO_SCSV
  ]
  var body: [UInt8] = []
  body.append(contentsOf: dtls12)
  body.append(contentsOf: random)
  body.append(0) // session_id length
  body.append(UInt8(cookie.count))
  body.append(contentsOf: cookie)
  body.append(UInt8((cipherSuites.count >> 8) & 0xFF))
  body.append(UInt8(cipherSuites.count & 0xFF))
  body.append(contentsOf: cipherSuites)
  body.append(1) // compression methods length
  body.append(0) // null compression
  // Handshake header: msg_type(1) length(3) message_seq(2) frag_offset(3) frag_length(3)
  let bodyLen = body.count
  var handshake: [UInt8] = []
  handshake.append(0x01) // client_hello
  handshake.append(UInt8((bodyLen >> 16) & 0xFF))
  handshake.append(UInt8((bodyLen >> 8) & 0xFF))
  handshake.append(UInt8(bodyLen & 0xFF))
  handshake.append(contentsOf: [0, 0]) // message_seq
  handshake.append(contentsOf: [0, 0, 0]) // fragment_offset
  handshake.append(UInt8((bodyLen >> 16) & 0xFF))
  handshake.append(UInt8((bodyLen >> 8) & 0xFF))
  handshake.append(UInt8(bodyLen & 0xFF))
  handshake.append(contentsOf: body)
  // Record header: type(1) version(2) epoch(2) seq(6) length(2)
  let recLen = handshake.count
  var record: [UInt8] = []
  record.append(22) // handshake
  record.append(contentsOf: dtls12)
  record.append(contentsOf: [0, 0]) // epoch
  record.append(contentsOf: [0, 0, 0, 0, 0, 0]) // sequence
  record.append(UInt8((recLen >> 8) & 0xFF))
  record.append(UInt8(recLen & 0xFF))
  record.append(contentsOf: handshake)
  return record
}

/// Extract the cookie field from a HelloVerifyRequest record at the
/// fixed offsets RFC 6347 §4.2.1 prescribes. Returns nil if the bytes
/// don't look like a HVR.
private func extractCookie(fromHelloVerifyRequest bytes: [UInt8]) -> [UInt8]? {
  guard bytes.count > 28 else { return nil }
  // Record header (13) + handshake header (12) + body version (2) +
  // cookie length (1). Cookie starts at offset 28.
  guard bytes[0] == 22, bytes[13] == 0x03 else { return nil } // type=handshake, msg_type=hello_verify_request
  let cookieLen = Int(bytes[27])
  guard bytes.count >= 28 + cookieLen else { return nil }
  return Array(bytes[28..<(28 + cookieLen)])
}

// MARK: - Endpoint factory

@OcaDevice
private func startEndpoint(
  options: Ocp1OpenSSLDTLSEndpointOptions = .init()
) async throws -> (Ocp1OpenSSLDTLSDeviceEndpoint, UInt16, Task<Void, Error>) {
  let device = OcaDevice()
  try await device.initializeDefaultObjects()
  try await device.securityManager.loadPreSharedKey(
    identity: OcaPreSharedKeyIdentityHint,
    key: Data(repeating: 0x42, count: 32)
  )
  var sin = sockaddr_in()
  sin.sin_family = loopbackAFamily
  sin.sin_port = UInt16(0).bigEndian
  sin.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
  let endpoint = try await Ocp1OpenSSLDTLSDeviceEndpoint(
    address: sin,
    device: device,
    options: options
  )
  let port = endpoint.port
  XCTAssertNotEqual(port, 0)
  let task = Task { try await endpoint.run() }
  // Give the listener a moment to enter its receive loop.
  try await Task.sleep(for: .milliseconds(100))
  return (endpoint, port, task)
}

// MARK: - Tests

final class DTLSHostileTrafficTests: XCTestCase {
  /// Pre-cookie filter must reject before any per-peer state is allocated.
  func testSourceFilterRejectsBeforeAllocation() async throws {
    let options = Ocp1OpenSSLDTLSEndpointOptions(
      sourceAddressFilter: { _ in false }
    )
    let (endpoint, port, task) = try await startEndpoint(options: options)
    defer { task.cancel() }

    let fd = try openUDPSocket()
    defer { close(fd) }
    try sendUDP(fd, bytes: buildClientHello(), to: port)
    try await Task.sleep(for: .milliseconds(300))

    let count = await endpoint.controllers.count
    XCTAssertEqual(count, 0, "sourceAddressFilter==false must drop pre-allocation")
  }

  /// `maxPeers` caps the per-peer table even under multi-source spray.
  /// Uses distinct loopback IPs so the per-source-IP throttle doesn't
  /// front-stop the cap.
  func testMaxPeersCapHoldsUnderMultiSourceSpray() async throws {
    let cap = 4
    let options = Ocp1OpenSSLDTLSEndpointOptions(
      handshakeDeadline: .seconds(30),
      maxPeers: cap
    )
    let (endpoint, port, task) = try await startEndpoint(options: options)
    defer { task.cancel() }

    var fds: [Int32] = []
    defer { for fd in fds { close(fd) } }
    // 10 distinct source IPs > cap of 4.
    for octet in 1...10 {
      let fd = try openUDPSocket(sourceIP: loopback(UInt8(octet)))
      fds.append(fd)
      try sendUDP(fd, bytes: buildClientHello(), to: port)
    }
    try await Task.sleep(for: .milliseconds(500))

    let count = await endpoint.controllers.count
    XCTAssertLessThanOrEqual(count, cap, "controllers must not exceed maxPeers")
  }

  /// One source IP can't allocate more than `maxAllocationsPerSourcePerWindow`
  /// fresh controllers within the window, even by rotating ports.
  func testPerSourceRateLimitRefusesExtras() async throws {
    let options = Ocp1OpenSSLDTLSEndpointOptions(
      // Long deadline so we observe the steady-state count, not a churn race.
      handshakeDeadline: .seconds(30)
    )
    let (endpoint, port, task) = try await startEndpoint(options: options)
    defer { task.cancel() }

    var fds: [Int32] = []
    defer { for fd in fds { close(fd) } }
    for _ in 0..<10 {
      let fd = try openUDPSocket() // same source IP (127.0.0.1), new port each time
      fds.append(fd)
      try sendUDP(fd, bytes: buildClientHello(), to: port)
    }
    try await Task.sleep(for: .milliseconds(500))

    // Per-source allocation cap defaults to 2 per 10 s window.
    let count = await endpoint.controllers.count
    XCTAssertLessThanOrEqual(count, 2, "per-source rate limit must front-stop port rotation")
  }

  /// A ClientHello carrying a bogus cookie can still trip the per-peer
  /// engine into allocation, but the handshake never completes and the
  /// GC sweep evicts the slot within ~handshakeDeadline + cadence.
  func testInvalidCookieClientHelloEvictedByDeadline() async throws {
    let options = Ocp1OpenSSLDTLSEndpointOptions(
      handshakeDeadline: .seconds(2)
    )
    let (endpoint, port, task) = try await startEndpoint(options: options)
    defer { task.cancel() }

    let fd = try openUDPSocket()
    defer { close(fd) }
    try sendUDP(fd, bytes: buildClientHello(cookie: [UInt8](repeating: 0xCC, count: 32)), to: port)

    // Handshake deadline + sweep cadence (max(deadline/2, 1s)) + slack.
    try await Task.sleep(for: .seconds(5))
    let count = await endpoint.controllers.count
    XCTAssertEqual(count, 0, "GC sweep must evict slots stuck on bad cookies")
  }

  /// HelloVerifyRequest cookies are bound to the source address; replaying
  /// a cookie minted for source A from source B must not satisfy the
  /// server's cookie callback.
  func testCookieFromOneSourceRejectedFromAnother() async throws {
    let options = Ocp1OpenSSLDTLSEndpointOptions(
      handshakeDeadline: .seconds(2)
    )
    let (endpoint, port, task) = try await startEndpoint(options: options)
    defer { task.cancel() }

    // Source A: send no-cookie ClientHello, expect HVR with a cookie.
    let fdA = try openUDPSocket(sourceIP: loopback(11))
    defer { close(fdA) }
    try sendUDP(fdA, bytes: buildClientHello(), to: port)
    guard let hvr = recvUDP(fdA), let cookieFromA = extractCookie(fromHelloVerifyRequest: hvr) else {
      throw XCTSkip("HelloVerifyRequest not received — kernel may have lost the packet")
    }
    XCTAssertFalse(cookieFromA.isEmpty)

    // Source B replays source A's cookie.
    let fdB = try openUDPSocket(sourceIP: loopback(12))
    defer { close(fdB) }
    try sendUDP(fdB, bytes: buildClientHello(cookie: cookieFromA), to: port)
    try await Task.sleep(for: .seconds(5)) // > handshakeDeadline + sweep

    // Source B's slot must have been evicted — the cookie HMAC didn't
    // match B's source address, so the engine never completed handshake.
    let count = await endpoint.controllers.count
    XCTAssertEqual(count, 0, "cross-source cookie replay must not authenticate")
  }
}

#endif
