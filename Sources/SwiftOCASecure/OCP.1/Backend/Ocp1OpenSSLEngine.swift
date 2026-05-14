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

#if canImport(COpenSSL)

import COpenSSL
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@_spi(SwiftOCAPrivate)
import SwiftOCA
import Synchronization

/// PSK state reached from the OpenSSL C callbacks via `SSL_set_ex_data`.
/// Server-side holds a reference to a provider queried on each callback;
/// client-side holds a single identity/key pair. A class so we can pass
/// an unretained pointer through the C boundary.
package final class Ocp1OpenSSLPSKStore: @unchecked Sendable {
  let serverProvider: (any OcaPreSharedKeyProvider)?

  /// When set, PSK callbacks read key bytes on-demand from the provider
  /// instead of from `clientKey`, so the secret only lives in the caller's
  /// storage.
  let clientProvider: (any OcaPreSharedKeyProvider)?

  let clientIdentity: String?

  /// `var` only so `deinit` can zero the bytes; never reassigned.
  private(set) var clientKey: Data?

  /// Stable storage for the client identity's UTF-8 bytes — OpenSSL's TLS
  /// 1.3 `use_session_cb` keeps the pointer past the callback return.
  fileprivate let clientIdentityBytes: UnsafeMutableBufferPointer<UInt8>?

  /// Bound to the HelloVerifyRequest cookie by the DTLS cookie callbacks.
  let peerAddressBytes: Data

  /// Server-side: the PSK identity that produced a successful lookup.
  /// Written by the synchronous C callback, read by the engine actor.
  private let authenticatedPSKIdentity = Mutex<String?>(nil)

  fileprivate func setAuthenticatedPSKIdentity(_ identity: String) {
    authenticatedPSKIdentity.withLock { $0 = identity }
  }

  package func capturedPSKIdentity() -> String? {
    authenticatedPSKIdentity.withLock { $0 }
  }

  package func clearAuthenticatedPSKIdentity() {
    authenticatedPSKIdentity.withLock { $0 = nil }
  }

  init(
    serverProvider: (any OcaPreSharedKeyProvider)?,
    peerAddressBytes: Data = Data()
  ) {
    self.serverProvider = serverProvider
    clientProvider = nil
    clientIdentity = nil
    clientKey = nil
    clientIdentityBytes = nil
    self.peerAddressBytes = peerAddressBytes
  }

  init(clientIdentity: String, clientKey: Data) {
    serverProvider = nil
    clientProvider = nil
    self.clientIdentity = clientIdentity
    // Force a refcount-1 private copy so `deinit`'s `resetBytes` zeros the
    // actually-stored bytes rather than COW-allocating a fresh copy.
    var owned = Data(count: clientKey.count)
    owned.withUnsafeMutableBytes { dst in
      clientKey.withUnsafeBytes { src in
        if let dp = dst.baseAddress, let sp = src.baseAddress {
          dp.copyMemory(from: sp, byteCount: clientKey.count)
        }
      }
    }
    self.clientKey = owned
    let utf8 = Array(clientIdentity.utf8)
    let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: utf8.count)
    _ = buf.initialize(from: utf8)
    clientIdentityBytes = buf
    peerAddressBytes = Data()
  }

  /// Provider-backed client variant. Key bytes live in the provider's
  /// storage; no copy is kept on this store.
  init(clientIdentity: String, clientProvider: any OcaPreSharedKeyProvider) {
    serverProvider = nil
    self.clientProvider = clientProvider
    self.clientIdentity = clientIdentity
    clientKey = nil
    let utf8 = Array(clientIdentity.utf8)
    let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: utf8.count)
    _ = buf.initialize(from: utf8)
    clientIdentityBytes = buf
    peerAddressBytes = Data()
  }

  deinit {
    if let count = clientKey?.count {
      clientKey?.resetBytes(in: 0..<count)
    }
    if let clientIdentityBytes {
      clientIdentityBytes.deinitialize()
      clientIdentityBytes.deallocate()
    }
  }
}

/// PSK-mode client verify callback. Returns 0 so any cert presented by the
/// server fails the handshake — PSK handshakes don't carry one, and a cert
/// appearing here means the server is silently downgrading to cert auth.
private let _pskClientRejectCertCallback: @convention(c) (
  _ preverifyOK: CInt,
  _ ctx: OpaquePointer?
) -> CInt = { _, _ in
  0
}

/// Ex-data slot used to attach an `Ocp1OpenSSLPSKStore` to each `SSL`.
private let _sslPSKStoreExIndex: Mutex<CInt> = Mutex(-1)

private func _getOrAllocateExIndex() -> CInt {
  _sslPSKStoreExIndex.withLock { slot in
    if slot < 0 {
      slot = COpenSSL_SSL_get_ex_new_index(0, nil, nil, nil, nil)
    }
    return slot
  }
}

private func _pskStore(from ssl: OpaquePointer?) -> Ocp1OpenSSLPSKStore? {
  guard let ssl else { return nil }
  let idx = _getOrAllocateExIndex()
  guard let raw = SSL_get_ex_data(ssl, idx) else { return nil }
  return Unmanaged<Ocp1OpenSSLPSKStore>.fromOpaque(raw).takeUnretainedValue()
}

/// TLS 1.2 server PSK callback. Looks up the identity and copies the key
/// into the supplied buffer; returns 0 on unknown identity or oversized key.
private let _pskServerCallback: @convention(c) (
  _ ssl: OpaquePointer?,
  _ identity: UnsafePointer<CChar>?,
  _ psk: UnsafeMutablePointer<UInt8>?,
  _ maxLen: CUnsignedInt
) -> CUnsignedInt = { ssl, identityPtr, psk, maxLen in
  guard let ssl, let identityPtr, let psk, let store = _pskStore(from: ssl) else { return 0 }
  let maxIdentityBytes = Int(PSK_MAX_IDENTITY_LEN)
  var identityLen = 0
  while identityLen < maxIdentityBytes, identityPtr[identityLen] != 0 {
    identityLen += 1
  }
  guard identityLen < maxIdentityBytes else { return 0 }
  let identityBytes = UnsafeBufferPointer(
    start: UnsafeRawPointer(identityPtr).assumingMemoryBound(to: UInt8.self),
    count: identityLen
  )
  let identity = String(decoding: identityBytes, as: UTF8.self)
  guard let provider = store.serverProvider else { return 0 }
  let written: CUnsignedInt = provider.withPreSharedKey(forIdentity: identity) { src in
    guard src.count <= Int(maxLen), let base = src.baseAddress else { return CUnsignedInt(0) }
    psk.update(from: base, count: src.count)
    return CUnsignedInt(src.count)
  } ?? 0
  guard written > 0 else { return 0 }
  store.setAuthenticatedPSKIdentity(identity)
  // PSK authenticates the client on its own; if the SSL_CTX was also wired
  // up for mTLS, don't also demand a client cert that won't be exchanged.
  SSL_set_verify(ssl, SSL_VERIFY_NONE, nil)
  return written
}

/// TLS 1.2 client PSK callback. Key bytes come from `clientKey` (the
/// `.preSharedKey` variant) or `clientProvider` (`.preSharedKeyProvider`).
private let _pskClientCallback: @convention(c) (
  _ ssl: OpaquePointer?,
  _ hint: UnsafePointer<CChar>?,
  _ identity: UnsafeMutablePointer<CChar>?,
  _ maxIdentityLen: CUnsignedInt,
  _ psk: UnsafeMutablePointer<UInt8>?,
  _ maxPSKLen: CUnsignedInt
) -> CUnsignedInt = { ssl, _, identityBuf, maxIdentityLen, psk, maxPSKLen in
  guard let identityBuf, let psk, let store = _pskStore(from: ssl),
        let id = store.clientIdentity
  else { return 0 }
  let idBytes = Data(id.utf8)
  guard idBytes.count + 1 <= Int(maxIdentityLen) else { return 0 }
  idBytes.withUnsafeBytes { src in
    identityBuf.withMemoryRebound(to: UInt8.self, capacity: idBytes.count + 1) { dest in
      dest.update(from: src.bindMemory(to: UInt8.self).baseAddress!, count: idBytes.count)
      dest[idBytes.count] = 0
    }
  }
  if let provider = store.clientProvider {
    return provider.withPreSharedKey(forIdentity: id) { keyBuf -> CUnsignedInt in
      guard keyBuf.count <= Int(maxPSKLen), let base = keyBuf.baseAddress else { return 0 }
      psk.update(from: base, count: keyBuf.count)
      return CUnsignedInt(keyBuf.count)
    } ?? 0
  }
  guard let key = store.clientKey, key.count <= Int(maxPSKLen) else { return 0 }
  key.withUnsafeBytes { src in
    psk.update(from: src.bindMemory(to: UInt8.self).baseAddress!, count: key.count)
  }
  return CUnsignedInt(key.count)
}

/// IANA ID for `TLS_AES_128_GCM_SHA256` — matches the suite Apple's
/// Network.framework selects when negotiating TLS 1.3 PSK.
private let _tls13PSKCipherID: [UInt8] = [0x13, 0x01]

/// Build an `SSL_SESSION` carrying `key` as the resumption secret with the
/// TLS 1.3 cipher installed. Caller transfers ownership to OpenSSL via the
/// `**sess` out-parameter. Takes a raw buffer so server callers can invoke
/// this inside the provider's `withPreSharedKey` closure without copying.
private func _makeTLS13PSKSession(
  ssl: OpaquePointer,
  key: UnsafeBufferPointer<UInt8>
) -> OpaquePointer? {
  guard let cipher = _tls13PSKCipherID.withUnsafeBufferPointer({ buf in
    SSL_CIPHER_find(ssl, buf.baseAddress)
  }) else { return nil }
  guard let session = SSL_SESSION_new() else { return nil }
  guard SSL_SESSION_set1_master_key(session, key.baseAddress, key.count) == 1,
        SSL_SESSION_set_cipher(session, cipher) == 1,
        SSL_SESSION_set_protocol_version(session, Int32(TLS1_3_VERSION)) == 1
  else {
    SSL_SESSION_free(session)
    return nil
  }
  return session
}

/// TLS 1.3 server-side PSK callback (RFC 8446 §4.2.11 external PSK). Fires
/// only for externally configured PSKs; session-ticket resumption goes
/// through OpenSSL's own machinery. Returning `1` with `*sess = nil` means
/// "no external PSK matched" — handshake falls through to cert auth.
private let _pskFindSessionCallback: @convention(c) (
  _ ssl: OpaquePointer?,
  _ identity: UnsafePointer<UInt8>?,
  _ identityLen: Int,
  _ session: UnsafeMutablePointer<OpaquePointer?>?
) -> CInt = { ssl, identityPtr, identityLen, sessionOut in
  guard let ssl, let sessionOut else { return 0 }
  sessionOut.pointee = nil
  guard let identityPtr, let store = _pskStore(from: ssl) else { return 1 }
  guard identityLen >= 0, identityLen <= Int(PSK_MAX_IDENTITY_LEN) else { return 1 }
  let identityBytes = UnsafeBufferPointer(start: identityPtr, count: identityLen)
  let identity = String(decoding: identityBytes, as: UTF8.self)
  guard let provider = store.serverProvider else { return 1 }
  let session: OpaquePointer? = provider.withPreSharedKey(forIdentity: identity) { src in
    _makeTLS13PSKSession(ssl: ssl, key: src)
  } ?? nil
  guard let session else { return 1 }
  store.setAuthenticatedPSKIdentity(identity)
  // PSK authenticates the client; clear verify on this SSL so an mTLS
  // CTX doesn't also demand a client cert that won't be exchanged.
  SSL_set_verify(ssl, SSL_VERIFY_NONE, nil)
  sessionOut.pointee = session
  return 1
}

/// TLS 1.3 client-side PSK callback. `md != nil` means HelloRetryRequest
/// asked for a specific digest; we only support SHA-256, so skip PSK if a
/// different digest was requested.
private let _pskUseSessionCallback: @convention(c) (
  _ ssl: OpaquePointer?,
  _ md: OpaquePointer?,
  _ id: UnsafeMutablePointer<UnsafePointer<UInt8>?>?,
  _ idLen: UnsafeMutablePointer<Int>?,
  _ session: UnsafeMutablePointer<OpaquePointer?>?
) -> CInt = { ssl, md, idOut, idLenOut, sessionOut in
  guard let ssl, let idOut, let idLenOut, let sessionOut else { return 0 }
  idOut.pointee = nil
  idLenOut.pointee = 0
  sessionOut.pointee = nil

  if md != nil, md != EVP_sha256() {
    return 1
  }

  guard let store = _pskStore(from: ssl),
        let identityBytes = store.clientIdentityBytes
  else { return 1 }

  let session: OpaquePointer?
  if let provider = store.clientProvider, let id = store.clientIdentity {
    session = provider.withPreSharedKey(forIdentity: id) { keyBuf in
      _makeTLS13PSKSession(ssl: ssl, key: keyBuf)
    } ?? nil
  } else if let key = store.clientKey {
    session = key.withUnsafeBytes { raw in
      _makeTLS13PSKSession(ssl: ssl, key: raw.bindMemory(to: UInt8.self))
    }
  } else {
    return 1
  }
  guard let session else { return 0 }
  idOut.pointee = UnsafePointer(identityBytes.baseAddress)
  idLenOut.pointee = identityBytes.count
  sessionOut.pointee = session
  return 1
}

/// DTLS HelloVerifyRequest cookie machinery (RFC 6347 §4.2.1):
/// HMAC-SHA256 the peer's source address with a per-process secret. The
/// secret lives for the process lifetime — rotating would invalidate
/// in-flight HelloVerifyRequests.
package enum Ocp1OpenSSLDTLSCookie {
  /// 32-byte HMAC key, generated once via OpenSSL's CSPRNG.
  static let secret: Data = {
    var data = Data(count: 32)
    let ok = data.withUnsafeMutableBytes { raw -> Int32 in
      RAND_bytes(raw.bindMemory(to: UInt8.self).baseAddress, Int32(raw.count))
    }
    precondition(ok == 1, "RAND_bytes failed seeding the DTLS cookie secret")
    return data
  }()

  /// HMAC-SHA256(secret, peerAddress). 32 bytes, well under the 255-byte
  /// DTLS cookie field limit.
  static func compute(over peerAddress: Data) -> Data {
    var output = [UInt8](repeating: 0, count: 32)
    var outLen: UInt32 = 32
    secret.withUnsafeBytes { secretBytes in
      peerAddress.withUnsafeBytes { peerBytes in
        output.withUnsafeMutableBufferPointer { outBuf in
          _ = HMAC(
            EVP_sha256(),
            secretBytes.baseAddress,
            Int32(secretBytes.count),
            peerBytes.bindMemory(to: UInt8.self).baseAddress,
            peerBytes.count,
            outBuf.baseAddress,
            &outLen
          )
        }
      }
    }
    return Data(output.prefix(Int(outLen)))
  }
}

/// DTLS cookie generate callback. Fires when the server is about to emit
/// a HelloVerifyRequest.
private let _cookieGenerateCallback: @convention(c) (
  _ ssl: OpaquePointer?,
  _ cookieOut: UnsafeMutablePointer<UInt8>?,
  _ cookieLenOut: UnsafeMutablePointer<CUnsignedInt>?
) -> CInt = { ssl, cookieOut, cookieLenOut in
  guard let ssl, let cookieOut, let cookieLenOut,
        let store = _pskStore(from: ssl)
  else { return 0 }
  let mac = Ocp1OpenSSLDTLSCookie.compute(over: store.peerAddressBytes)
  guard mac.count <= 255 else { return 0 }
  mac.withUnsafeBytes { src in
    cookieOut.update(
      from: src.bindMemory(to: UInt8.self).baseAddress!,
      count: mac.count
    )
  }
  cookieLenOut.pointee = CUnsignedInt(mac.count)
  return 1
}

/// DTLS cookie verify callback. Recomputes the expected cookie and
/// constant-time-compares. Cookie verification closes the amplification
/// path, not the state-allocation path.
private let _cookieVerifyCallback: @convention(c) (
  _ ssl: OpaquePointer?,
  _ cookieIn: UnsafePointer<UInt8>?,
  _ cookieLen: CUnsignedInt
) -> CInt = { ssl, cookieIn, cookieLen in
  guard let ssl, let cookieIn,
        let store = _pskStore(from: ssl)
  else { return 0 }
  let expected = Ocp1OpenSSLDTLSCookie.compute(over: store.peerAddressBytes)
  guard expected.count == Int(cookieLen) else { return 0 }
  let match: Int32 = expected.withUnsafeBytes { expBytes in
    CRYPTO_memcmp(expBytes.baseAddress, cookieIn, expected.count)
  }
  return match == 0 ? 1 : 0
}

/// TLS 1.2 PSK suites, strongest first. PFS-only: non-PFS PSK-AES-GCM was
/// dropped (PSK leak under those would decrypt all past traffic).
package let Ocp1OpenSSLPSKCipherList = [
  "ECDHE-PSK-CHACHA20-POLY1305", // RFC 7905, ECDHE PFS + AEAD
  "DHE-PSK-CHACHA20-POLY1305",   // RFC 7905, DHE PFS + AEAD
  "DHE-PSK-AES256-GCM-SHA384",   // RFC 5487, DHE PFS + AEAD-256
  "DHE-PSK-AES128-GCM-SHA256",   // RFC 5487, DHE PFS + AEAD-128
  "DHE-PSK-AES128-CBC-SHA",      // RFC 4279, AES70-2024 mandated PFS baseline
].joined(separator: ":")

/// TLS 1.2 cert-mode suites — explicit PFS + AEAD list so a permissive
/// OpenSSL build policy can't silently weaken the channel.
package let Ocp1OpenSSLCertCipherList = [
  "ECDHE-ECDSA-AES256-GCM-SHA384",
  "ECDHE-RSA-AES256-GCM-SHA384",
  "ECDHE-ECDSA-CHACHA20-POLY1305",
  "ECDHE-RSA-CHACHA20-POLY1305",
  "ECDHE-ECDSA-AES128-GCM-SHA256",
  "ECDHE-RSA-AES128-GCM-SHA256",
  "DHE-RSA-AES256-GCM-SHA384",
  "DHE-RSA-CHACHA20-POLY1305",
  "DHE-RSA-AES128-GCM-SHA256",
].joined(separator: ":")

/// Transport-agnostic OpenSSL TLS engine. Owns the `SSL_CTX`/`SSL` and a
/// pair of memory BIOs; callers drive bytes through `read`/`write` closures
/// bound to whatever byte stream they hold. All `SSL_*` calls run on the
/// engine actor against non-blocking memory BIOs.
package actor Ocp1OpenSSLEngine {
  package enum Mode: Sendable {
    case client
    case server
  }

  /// `.stream` selects TLS over TCP/Unix; `.datagram` selects DTLS over UDP.
  package enum Transport: Sendable {
    case stream
    case datagram
  }

  private let transport: Transport
  private let mode: Mode
  private var ctx: OpaquePointer?
  private var ssl: OpaquePointer?
  /// Network → TLS (we BIO_write inbound ciphertext here).
  private var rbio: OpaquePointer?
  /// TLS → Network (we BIO_read outbound ciphertext from here).
  private var wbio: OpaquePointer?
  private let pskStore: Ocp1OpenSSLPSKStore
  private var handshakeComplete = false
  private var closed = false

  /// Must comfortably exceed the per-record DTLS MTU.
  private static let readBufferSize = 16 * 1024

  /// DTLS record header layout (RFC 6347 §4.1):
  ///   byte 0:     content type
  ///   bytes 1-2:  protocol version
  ///   bytes 3-10: epoch (2) + sequence number (6)
  ///   bytes 11-12: length (big-endian)
  /// Payload follows at byte 13.
  private static let dtlsRecordHeaderSize = 13
  private static let dtlsRecordLengthOffset = 11

  /// RFC 6347 §4.1.1 recommended fallback that survives most paths without
  /// IP-level fragmentation. OpenSSL refuses to send oversized records.
  private static let DefaultDTLSMtu: Int32 = 1200

  package init(
    mode: Mode,
    credential: Ocp1TLSCredential?,
    transport: Transport = .stream,
    serverPSKProvider: (any OcaPreSharedKeyProvider)? = nil,
    verifyPeer: Bool = false,
    hostname: String? = nil,
    trustRoots: Ocp1TLSTrustRoots? = nil,
    clientTrustRoots: Ocp1TLSTrustRoots? = nil,
    revocation: Ocp1TLSRevocationOptions = .disabled,
    peerAddressBytes: Data = Data()
  ) throws {
    try credential?.validate()

    // Cert-mode DTLS handshakes produce multi-record flights that don't
    // survive the current `drainOutbound` coalescing — refuse until a
    // packet-preserving outbound path lands. PSK stays within one record.
    if transport == .datagram, let credential, !Self.credentialIsPSK(credential) {
      throw Ocp1Error.status(.notImplemented)
    }
    // Empty `peerAddressBytes` would collapse the cookie HMAC to a
    // server-wide constant, defeating source-address verification.
    if transport == .datagram, mode == .server, peerAddressBytes.isEmpty {
      throw Ocp1Error.status(.parameterError)
    }
    // Cert-mode clients with verifyPeer need a hostname to verify against;
    // chain-only validation accepts any cert from the configured CA.
    if mode == .client, verifyPeer, !Self.credentialIsPSK(credential), hostname == nil {
      throw Ocp1Error.status(.parameterError)
    }
    // `.preSharedKey*` is a client-side shape; server PSKs come from the
    // injected provider.
    if mode == .server, Self.credentialIsPSK(credential) {
      throw Ocp1Error.status(.parameterError)
    }

    self.transport = transport
    self.mode = mode
    pskStore = switch (mode, credential) {
    case let (.client, .preSharedKey(identity, key)?):
      Ocp1OpenSSLPSKStore(clientIdentity: identity, clientKey: key)
    case let (.client, .preSharedKeyProvider(identity, provider)?):
      Ocp1OpenSSLPSKStore(clientIdentity: identity, clientProvider: provider)
    case (.client, _):
      Ocp1OpenSSLPSKStore(serverProvider: nil)
    case (.server, _):
      Ocp1OpenSSLPSKStore(
        serverProvider: serverPSKProvider,
        peerAddressBytes: peerAddressBytes
      )
    }

    let method: OpaquePointer? = switch (transport, mode) {
    case (.stream, .server): TLS_server_method()
    case (.stream, .client): TLS_client_method()
    case (.datagram, .server): DTLS_server_method()
    case (.datagram, .client): DTLS_client_method()
    }
    guard let method, let ctx = SSL_CTX_new(method) else {
      throw Ocp1Error.unknownServiceType
    }
    self.ctx = ctx

    // MOVING_WRITE_BUFFER: `Data.withUnsafeBytes` can hand out a different
    // pointer between async hops, which would trip OpenSSL's retry-with-
    // the-same-pointer contract (SSL_R_BAD_WRITE_RETRY).
    // ENABLE_PARTIAL_WRITE lets `SSL_write` return after a partial write
    // so we can yield between records.
    _ = COpenSSL_SSL_CTX_set_mode(
      ctx,
      COpenSSL_SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER | COpenSSL_SSL_MODE_ENABLE_PARTIAL_WRITE
    )

    // TLS/DTLS 1.2+. The AES70-mandated PSK suite is TLS 1.2-only and
    // DTLS 1.0 is RFC 8996 deprecated.
    let minVersion: Int32 = transport == .datagram ? Int32(DTLS1_2_VERSION) : Int32(TLS1_2_VERSION)
    guard COpenSSL_SSL_CTX_set_min_proto_version(ctx, minVersion) == 1 else {
      SSL_CTX_free(ctx)
      self.ctx = nil
      throw Ocp1OpenSSLError(code: 0, detail: Self.collectErrorMessages())
    }

    // Restrict TLS 1.3 to SHA-256 suites. `_makeTLS13PSKSession` pins the
    // PSK to TLS_AES_128_GCM_SHA256, and RFC 8446 §4.2.11 requires the
    // session's hash to match the negotiated cipher's — letting the server
    // pick TLS_AES_256_GCM_SHA384 would silently fall through to cert mode.
    guard SSL_CTX_set_ciphersuites(ctx, "TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256") == 1 else {
      SSL_CTX_free(ctx)
      self.ctx = nil
      throw Ocp1OpenSSLError(code: 0, detail: Self.collectErrorMessages())
    }

    if let credential {
      try Self.configureCredential(ctx: ctx, credential: credential)
    } else {
      // No per-engine credential: assume PSK-only and force the PSK suites.
      // Default cipher list = cert-only, which would silently deny PSK.
      guard SSL_CTX_set_cipher_list(ctx, Ocp1OpenSSLPSKCipherList) == 1 else {
        SSL_CTX_free(ctx)
        self.ctx = nil
        throw Ocp1OpenSSLError(code: 0, detail: Self.collectErrorMessages())
      }
    }

    // Arm PSK callbacks regardless of mTLS config: PSK and cert auth are
    // independent OCP.1 paths and OpenSSL picks the right one. Both TLS 1.2
    // (raw byte) and TLS 1.3 (RFC 8773 external PSK) callbacks are wired so
    // the negotiated protocol version determines which fires.
    if mode == .server {
      SSL_CTX_set_psk_server_callback(ctx, _pskServerCallback)
      SSL_CTX_set_psk_find_session_callback(ctx, _pskFindSessionCallback)
    } else {
      SSL_CTX_set_psk_client_callback(ctx, _pskClientCallback)
      SSL_CTX_set_psk_use_session_callback(ctx, _pskUseSessionCallback)
    }

    // DTLS HelloVerifyRequest cookie exchange (RFC 6347 §4.2.1): blocks the
    // amplification DoS by forcing the peer to echo back a source-bound
    // cookie before the server emits the full ServerHello flight.
    if mode == .server, transport == .datagram {
      _ = SSL_CTX_set_options(ctx, COpenSSL_SSL_OP_COOKIE_EXCHANGE)
      SSL_CTX_set_cookie_generate_cb(ctx, _cookieGenerateCallback)
      SSL_CTX_set_cookie_verify_cb(ctx, _cookieVerifyCallback)
    }

    // Refuse renegotiation both ways — a hostile TLS 1.2 server can drive
    // PSK clients into CPU-burning renegotiation loops. TLS 1.3 has no
    // renegotiation, so this is a no-op there.
    _ = SSL_CTX_set_options(ctx, COpenSSL_SSL_OP_NO_RENEGOTIATION)
    // Disable session tickets so every connection re-authenticates from
    // scratch — control-plane mTLS should not replay credentials, and
    // resumption complicates revocation enforcement.
    _ = SSL_CTX_set_options(ctx, COpenSSL_SSL_OP_NO_TICKET)
    // Reject TLS 1.3 0-RTT / early data; the OCP.1 protocol has no
    // idempotent commands and 0-RTT is replayable.
    _ = COpenSSL_SSL_CTX_set_max_early_data(ctx, 0)
    if mode == .server {
      _ = SSL_CTX_set_options(ctx, COpenSSL_SSL_OP_CIPHER_SERVER_PREFERENCE)
    }

    // Server-cert verification: client mode, verifyPeer, cert credential.
    if mode == .client, verifyPeer, !Self.credentialIsPSK(credential) {
      do {
        try Self.configureTrustRoots(ctx: ctx, trustRoots: trustRoots)
        try Self.configureRevocation(ctx: ctx, revocation: revocation)
      } catch {
        SSL_CTX_free(ctx)
        self.ctx = nil
        throw error
      }
      SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, nil)
    } else if mode == .client, Self.credentialIsPSK(credential) {
      // PSK client: install a verify callback that hard-rejects any peer
      // cert, so a server claiming "no PSK matched" can't silently
      // downgrade us to cert auth.
      SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, _pskClientRejectCertCallback)
    } else if mode == .server, let clientTrustRoots {
      // mTLS: require a client cert that chains to `clientTrustRoots`.
      do {
        try Self.configureTrustRoots(ctx: ctx, trustRoots: clientTrustRoots)
        try Self.configureRevocation(ctx: ctx, revocation: revocation)
      } catch {
        SSL_CTX_free(ctx)
        self.ctx = nil
        throw error
      }
      SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT, nil)
    } else {
      SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, nil)
    }

    guard let ssl = SSL_new(ctx) else {
      SSL_CTX_free(ctx)
      self.ctx = nil
      throw Ocp1Error.unknownServiceType
    }
    self.ssl = ssl

    if transport == .datagram {
      // OpenSSL won't probe path MTU without a real BIO_dgram socket.
      _ = COpenSSL_SSL_set_mtu(ssl, Int(Self.DefaultDTLSMtu))
    }

    let exIdx = _getOrAllocateExIndex()
    SSL_set_ex_data(ssl, exIdx, Unmanaged.passUnretained(pskStore).toOpaque())

    // Set SNI whenever the caller supplies a hostname (servers route on
    // it even without verification); only bind hostname verification when
    // we're actually checking the cert.
    if let hostname, mode == .client {
      hostname.withCString { _ = COpenSSL_SSL_set_tlsext_host_name(ssl, $0) }
      if verifyPeer, !Self.credentialIsPSK(credential) {
        hostname.withCString { _ = SSL_set1_host(ssl, $0) }
      }
    }

    guard let rbio = BIO_new(BIO_s_mem()), let wbio = BIO_new(BIO_s_mem()) else {
      SSL_free(ssl)
      SSL_CTX_free(ctx)
      self.ssl = nil
      self.ctx = nil
      throw Ocp1Error.unknownServiceType
    }
    self.rbio = rbio
    self.wbio = wbio
    SSL_set_bio(ssl, rbio, wbio)

    switch mode {
    case .client:
      SSL_set_connect_state(ssl)
    case .server:
      SSL_set_accept_state(ssl)
    }
  }

  private static func credentialIsPSK(_ credential: Ocp1TLSCredential?) -> Bool {
    switch credential {
    case .preSharedKey, .preSharedKeyProvider: return true
    default: return false
    }
  }

  /// Pre-flight a trust-root configuration so device endpoints surface a
  /// CA-bundle typo at init time, not as per-peer handshake failures.
  package nonisolated static func validateTrustRoots(
    _ trustRoots: Ocp1TLSTrustRoots?
  ) throws {
    guard let trustRoots else { return } // platform-default is always loadable
    let ctx = SSL_CTX_new(TLS_method())
    guard let ctx else {
      throw Ocp1OpenSSLError(code: 0, detail: collectErrorMessages())
    }
    defer { SSL_CTX_free(ctx) }
    try configureTrustRoots(ctx: ctx, trustRoots: trustRoots)
  }

  /// Load CRLs into the SSL_CTX's X509_STORE and arm CRL checking. No-op
  /// when revocation is disabled or no CRLs are supplied — OpenSSL's
  /// CRL_CHECK without loaded CRLs would hard-fail every handshake, which
  /// is not "soft-fail."
  private static func configureRevocation(
    ctx: OpaquePointer,
    revocation: Ocp1TLSRevocationOptions
  ) throws {
    guard revocation.flags.contains(.enabled), let crls = revocation.crls else { return }
    guard let store = SSL_CTX_get_cert_store(ctx) else {
      throw Ocp1OpenSSLError(code: 0, detail: collectErrorMessages())
    }
    let pemData: Data
    switch crls {
    case let .crlFile(path):
      pemData = try Data(contentsOf: URL(fileURLWithPath: path))
    case let .crlData(data):
      pemData = data
    }
    try pemData.withUnsafeBytes { raw -> Void in
      let bio = BIO_new_mem_buf(raw.baseAddress, CInt(raw.count))
      defer { BIO_free(bio) }
      guard let bio else {
        throw Ocp1OpenSSLError(code: 0, detail: collectErrorMessages())
      }
      var added = 0
      while let crl = PEM_read_bio_X509_CRL(bio, nil, nil, nil) {
        if COpenSSL_X509_STORE_add_crl(store, crl) == 1 {
          added += 1
        }
        X509_CRL_free(crl)
      }
      guard added > 0 else {
        throw Ocp1OpenSSLError(code: 0, detail: collectErrorMessages())
      }
    }
    var flags = COpenSSL_X509_V_FLAG_CRL_CHECK
    if revocation.flags.contains(.checkChain) {
      flags |= COpenSSL_X509_V_FLAG_CRL_CHECK_ALL
    }
    _ = COpenSSL_X509_STORE_set_flags(store, flags)
  }

  /// Wire trust anchors into the `SSL_CTX`. `nil` → platform default;
  /// `.caFile` → OpenSSL's loader; `.caData` → push each PEM cert from the
  /// blob into the `X509_STORE`.
  private static func configureTrustRoots(
    ctx: OpaquePointer,
    trustRoots: Ocp1TLSTrustRoots?
  ) throws {
    switch trustRoots {
    case nil:
      _ = SSL_CTX_set_default_verify_paths(ctx)
    case let .caFile(path):
      guard path.withCString({ SSL_CTX_load_verify_locations(ctx, $0, nil) }) == 1 else {
        throw Ocp1OpenSSLError(code: 0, detail: collectErrorMessages())
      }
    case let .caData(data):
      guard let store = SSL_CTX_get_cert_store(ctx) else {
        throw Ocp1OpenSSLError(code: 0, detail: collectErrorMessages())
      }
      try data.withUnsafeBytes { raw -> Void in
        let bio = BIO_new_mem_buf(raw.baseAddress, CInt(raw.count))
        defer { BIO_free(bio) }
        guard let bio else {
          throw Ocp1OpenSSLError(code: 0, detail: collectErrorMessages())
        }
        var added = 0
        while let cert = PEM_read_bio_X509(bio, nil, nil, nil) {
          if X509_STORE_add_cert(store, cert) == 1 {
            added += 1
          }
          // X509_STORE_add_cert bumps the refcount; drop ours either way.
          X509_free(cert)
        }
        guard added > 0 else {
          throw Ocp1OpenSSLError(code: 0, detail: collectErrorMessages())
        }
      }
    }
  }

  isolated deinit {
    // SSL_free releases the BIOs attached via SSL_set_bio.
    if let ssl { SSL_free(ssl) }
    if let ctx { SSL_CTX_free(ctx) }
  }

  // MARK: - Public transport API

  /// Run `body` with a freshly-cleared OpenSSL thread-local error queue
  /// so anything `collectErrorMessages()` surfaces is attributable to this
  /// call — Swift's cooperative pool hops actor tasks across threads.
  private func clearingOpenSSLErrors<T>(
    _ body: () async throws -> T
  ) async rethrows -> T {
    ERR_clear_error()
    return try await body()
  }

  package func handshake(
    read networkRead: @Sendable (Int) async throws -> Data,
    write networkWrite: @Sendable (Data) async throws -> Void
  ) async throws {
    guard let ssl else { throw Ocp1Error.notConnected }
    try await clearingOpenSSLErrors {
      while !handshakeComplete {
        let ret = SSL_do_handshake(ssl)
        try await drainOutbound(write: networkWrite)
        if ret == 1 {
          handshakeComplete = true
          return
        }
        try await serviceWantSignal(ret: ret, read: networkRead, write: networkWrite)
      }
    }
  }

  package func read(
    _ count: Int,
    read networkRead: @Sendable (Int) async throws -> Data,
    write networkWrite: @Sendable (Data) async throws -> Void
  ) async throws -> Data {
    guard let ssl else { throw Ocp1Error.notConnected }
    if !handshakeComplete {
      try await handshake(read: networkRead, write: networkWrite)
    }
    return try await clearingOpenSSLErrors {
      var result = Data()
      result.reserveCapacity(count)
      var buffer = [UInt8](repeating: 0, count: count)
      while result.count < count {
        let want = count - result.count
        let ret = buffer.withUnsafeMutableBufferPointer { buf -> CInt in
          SSL_read(ssl, buf.baseAddress, CInt(want))
        }
        try await drainOutbound(write: networkWrite)
        if ret > 0 {
          result.append(contentsOf: buffer.prefix(Int(ret)))
          continue
        }
        try await serviceWantSignal(ret: ret, read: networkRead, write: networkWrite)
      }
      return result
    }
  }

  package func write(
    _ data: Data,
    read networkRead: @Sendable (Int) async throws -> Data,
    write networkWrite: @Sendable (Data) async throws -> Void
  ) async throws -> Int {
    guard let ssl else { throw Ocp1Error.notConnected }
    if !handshakeComplete {
      try await handshake(read: networkRead, write: networkWrite)
    }
    return try await clearingOpenSSLErrors {
      var written = 0
      while written < data.count {
        let remaining = data.count - written
        let ret = data.withUnsafeBytes { raw -> CInt in
          let base = raw.bindMemory(to: UInt8.self).baseAddress!.advanced(by: written)
          return SSL_write(ssl, base, CInt(remaining))
        }
        try await drainOutbound(write: networkWrite)
        if ret > 0 {
          written += Int(ret)
          continue
        }
        try await serviceWantSignal(ret: ret, read: networkRead, write: networkWrite)
      }
      return written
    }
  }

  package func shutdown(
    read networkRead: @Sendable (Int) async throws -> Data,
    write networkWrite: @Sendable (Data) async throws -> Void
  ) async throws {
    guard let ssl, !closed else { return }
    closed = true
    await clearingOpenSSLErrors {
      // Send close_notify; we don't currently surface SSL_shutdown's
      // 1 / 0 / <0 result to callers. Truncation-attack detection happens
      // on the read side via SSL_R_UNEXPECTED_EOF_WHILE_READING.
      _ = SSL_shutdown(ssl)
      try? await drainOutbound(write: networkWrite)
    }
  }

  /// Reset for a fresh handshake, reusing the existing `SSL_CTX`. Called
  /// at the start of every `connectDevice` (including reconnect retries)
  /// so an aborted handshake can't leak state into the next attempt.
  package func reset() {
    guard let ssl else { return }
    if let rbio { _ = COpenSSL_BIO_reset(rbio) }
    if let wbio { _ = COpenSSL_BIO_reset(wbio) }
    _ = SSL_clear(ssl)
    handshakeComplete = false
    closed = false
    // SSL_clear drops the connect/accept state set at init; restore it.
    switch mode {
    case .client: SSL_set_connect_state(ssl)
    case .server: SSL_set_accept_state(ssl)
    }
    pskStore.clearAuthenticatedPSKIdentity()
  }

  package var isHandshakeComplete: Bool { handshakeComplete }

  package var isDatagram: Bool { transport == .datagram }

  /// Peer's authenticated identity. Returns `.anonymous` before handshake
  /// completion or when neither PSK nor cert auth produced a binding.
  package func peerIdentity() -> OcaPeerIdentity {
    guard handshakeComplete else { return .anonymous }
    if let psk = pskStore.capturedPSKIdentity() {
      return .preSharedKey(identity: psk)
    }
    if let ssl, let cert = COpenSSL_SSL_get_peer_certificate(ssl) {
      defer { X509_free(cert) }
      let subject = Self.x509SubjectString(cert) ?? ""
      let fingerprint = Self.x509SHA256Fingerprint(cert) ?? ""
      if !subject.isEmpty || !fingerprint.isEmpty {
        return .certificate(subject: subject, fingerprint: fingerprint)
      }
    }
    return .anonymous
  }

  /// Legacy `/CN=alice/O=Acme` form via `X509_NAME_oneline` — good enough
  /// for ACL matching and log output.
  private static func x509SubjectString(_ cert: OpaquePointer) -> String? {
    guard let name = X509_get_subject_name(cert) else { return nil }
    guard let raw = X509_NAME_oneline(name, nil, 0) else { return nil }
    defer { CRYPTO_free(raw, #file, #line) }
    return String(cString: raw)
  }

  /// Lower-case hex SHA-256 fingerprint of the DER cert. Stable ACL key.
  private static func x509SHA256Fingerprint(_ cert: OpaquePointer) -> String? {
    var buf = [UInt8](repeating: 0, count: 32)
    var len: CUnsignedInt = 32
    let ok = buf.withUnsafeMutableBufferPointer { p -> CInt in
      COpenSSL_X509_digest_sha256(cert, p.baseAddress, &len)
    }
    guard ok == 1, len > 0 else { return nil }
    return buf.prefix(Int(len)).map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - DTLS client-side datagram read

  /// Block until one decrypted DTLS record is available. Unlike the stream
  /// `read` we don't loop to a byte count — DTLS preserves record
  /// boundaries and OCP.1 PDUs are framed at that level.
  package func readDatagram(
    read networkRead: @Sendable (Int) async throws -> Data,
    write networkWrite: @Sendable (Data) async throws -> Void
  ) async throws -> Data {
    guard let ssl else { throw Ocp1Error.notConnected }
    if !handshakeComplete {
      try await handshake(read: networkRead, write: networkWrite)
    }
    return try await clearingOpenSSLErrors {
      var buffer = [UInt8](repeating: 0, count: Self.readBufferSize)
      while true {
        let ret = buffer.withUnsafeMutableBufferPointer { buf -> CInt in
          SSL_read(ssl, buf.baseAddress, CInt(buf.count))
        }
        try await drainOutbound(write: networkWrite)
        if ret > 0 {
          return Data(buffer.prefix(Int(ret)))
        }
        try await serviceWantSignal(ret: ret, read: networkRead, write: networkWrite)
      }
    }
  }

  // MARK: - DTLS server-side ingest

  /// Ingest one peer datagram (the endpoint demultiplexes by source).
  /// Returns the decrypted application payload, or `nil` if the datagram
  /// was purely handshake.
  package func ingestDatagram(
    _ data: Data,
    write networkWrite: @Sendable (Data) async throws -> Void
  ) async throws -> Data? {
    guard let ssl, let rbio else { throw Ocp1Error.notConnected }
    return try await clearingOpenSSLErrors {
      if !data.isEmpty {
        _ = data.withUnsafeBytes { raw -> CInt in
          BIO_write(rbio, raw.baseAddress, CInt(data.count))
        }
      }
      if !handshakeComplete {
        let ret = SSL_do_handshake(ssl)
        try await drainOutbound(write: networkWrite)
        if ret == 1 {
          handshakeComplete = true
        } else {
          let err = SSL_get_error(ssl, ret)
          switch err {
          case SSL_ERROR_WANT_READ, SSL_ERROR_WANT_WRITE:
            return nil
          default:
            throw Ocp1OpenSSLError(code: err, detail: Self.collectErrorMessages())
          }
        }
      }
      // One DTLS record == one application datagram, so the first non-zero
      // SSL_read returns the whole payload.
      var buffer = [UInt8](repeating: 0, count: Self.readBufferSize)
      let n = buffer.withUnsafeMutableBufferPointer { buf -> CInt in
        SSL_read(ssl, buf.baseAddress, CInt(buf.count))
      }
      try await drainOutbound(write: networkWrite)
      if n > 0 {
        return Data(buffer.prefix(Int(n)))
      }
      let err = SSL_get_error(ssl, n)
      switch err {
      case SSL_ERROR_WANT_READ, SSL_ERROR_WANT_WRITE:
        return nil
      case SSL_ERROR_ZERO_RETURN:
        throw Ocp1Error.notConnected
      default:
        throw Ocp1OpenSSLError(code: err, detail: Self.collectErrorMessages())
      }
    }
  }

  /// Drive any pending DTLS retransmit. Returns the underlying
  /// `DTLSv1_handle_timeout` result (1 = retransmitted, 0 = no timeout, < 0 = error).
  @discardableResult
  package func handleDatagramTimeout(
    write networkWrite: @Sendable (Data) async throws -> Void
  ) async throws -> Int32 {
    guard let ssl else { return -1 }
    let r = COpenSSL_DTLSv1_handle_timeout(ssl)
    try await drainOutbound(write: networkWrite)
    return Int32(r)
  }

  // MARK: - Transport internals

  /// Copy pending outbound ciphertext from `wbio` to the transport. For
  /// DTLS, one drain cycle can hold several back-to-back records; we split
  /// at the 13-byte DTLS record header so each ships in its own datagram.
  private func drainOutbound(
    write networkWrite: @Sendable (Data) async throws -> Void
  ) async throws {
    guard let wbio else { return }
    while COpenSSL_BIO_pending(wbio) > 0 {
      var buffer = [UInt8](repeating: 0, count: Self.readBufferSize)
      let n = buffer.withUnsafeMutableBufferPointer { buf -> CInt in
        BIO_read(wbio, buf.baseAddress, CInt(buf.count))
      }
      if n <= 0 { break }
      let drained = Data(buffer.prefix(Int(n)))
      if transport == .datagram {
        try await sendDTLSRecords(drained, write: networkWrite)
      } else {
        try await networkWrite(drained)
      }
    }
  }

  /// Walk a drained `wbio` buffer as DTLS records, sending each as its own
  /// datagram. A truncated trailing record falls back to a single send.
  private func sendDTLSRecords(
    _ buffer: Data,
    write networkWrite: @Sendable (Data) async throws -> Void
  ) async throws {
    let headerSize = Self.dtlsRecordHeaderSize
    let lengthOffset = Self.dtlsRecordLengthOffset
    var offset = buffer.startIndex
    while offset < buffer.endIndex {
      let remaining = buffer.endIndex - offset
      guard remaining >= headerSize else {
        try await networkWrite(buffer.subdata(in: offset..<buffer.endIndex))
        return
      }
      let lenHigh = Int(buffer[offset + lengthOffset])
      let lenLow = Int(buffer[offset + lengthOffset + 1])
      let recordLength = headerSize + ((lenHigh << 8) | lenLow)
      guard remaining >= recordLength else {
        try await networkWrite(buffer.subdata(in: offset..<buffer.endIndex))
        return
      }
      try await networkWrite(buffer.subdata(in: offset..<offset + recordLength))
      offset += recordLength
    }
  }

  /// Advance the transport in whichever direction OpenSSL last signaled;
  /// throw on terminal errors. WANT_READ pulls from the network and feeds
  /// `rbio`; WANT_WRITE drains `wbio`; ZERO_RETURN is close_notify.
  private func serviceWantSignal(
    ret: CInt,
    read networkRead: @Sendable (Int) async throws -> Data,
    write networkWrite: @Sendable (Data) async throws -> Void
  ) async throws {
    guard let ssl else { throw Ocp1Error.notConnected }
    let err = SSL_get_error(ssl, ret)
    switch err {
    case SSL_ERROR_WANT_READ:
      let chunk = try await networkRead(Self.readBufferSize)
      if chunk.isEmpty {
        throw Ocp1Error.notConnected
      }
      _ = chunk.withUnsafeBytes { raw -> CInt in
        BIO_write(rbio, raw.baseAddress, CInt(chunk.count))
      }
    case SSL_ERROR_WANT_WRITE:
      try await drainOutbound(write: networkWrite)
    case SSL_ERROR_ZERO_RETURN:
      throw Ocp1Error.notConnected
    default:
      throw Ocp1OpenSSLError(code: err, detail: Self.collectErrorMessages())
    }
  }

  // MARK: - One-time setup helpers

  private static func configureCredential(
    ctx: OpaquePointer,
    credential: Ocp1TLSCredential
  ) throws {
    switch credential {
    case .preSharedKey, .preSharedKeyProvider:
      // Restrict TLS 1.2 to PSK suites — without a configured cert, cert
      // suites would just fail. TLS 1.3 PSK uses its own session pinning.
      _ = SSL_CTX_set_cipher_list(ctx, Ocp1OpenSSLPSKCipherList)
    case let .certificateFile(certPath, keyPath):
      try certPath.withCString { cert in
        try throwingOpenSSLError { SSL_CTX_use_certificate_chain_file(ctx, cert) }
      }
      try keyPath.withCString { key in
        try throwingOpenSSLError { SSL_CTX_use_PrivateKey_file(ctx, key, SSL_FILETYPE_PEM) }
      }
      try throwingOpenSSLError { SSL_CTX_check_private_key(ctx) }
      try throwingOpenSSLError { SSL_CTX_set_cipher_list(ctx, Ocp1OpenSSLCertCipherList) }
    case let .certificatePEM(certificate, privateKey):
      try configurePEMInMemory(ctx: ctx, certificate: certificate, privateKey: privateKey)
      try throwingOpenSSLError { SSL_CTX_set_cipher_list(ctx, Ocp1OpenSSLCertCipherList) }
    case let .pkcs12(data, password):
      try configurePKCS12(ctx: ctx, data: data, password: password)
      try throwingOpenSSLError { SSL_CTX_set_cipher_list(ctx, Ocp1OpenSSLCertCipherList) }
    #if canImport(Security)
    case .identity:
      throw Ocp1Error.unknownServiceType
    #endif
    }
  }

  private static func configurePEMInMemory(
    ctx: OpaquePointer,
    certificate: Data,
    privateKey: Data
  ) throws {
    try certificate.withUnsafeBytes { certBytes in
      let certBio = try throwingOpenSSLError {
        BIO_new_mem_buf(certBytes.baseAddress, CInt(certBytes.count))
      }
      defer { BIO_free(certBio) }
      let cert = try throwingOpenSSLError { PEM_read_bio_X509(certBio, nil, nil, nil) }
      defer { X509_free(cert) }
      try throwingOpenSSLError { SSL_CTX_use_certificate(ctx, cert) }
      // Pick up any intermediate certs appended to the same PEM blob.
      // `add_extra_chain_cert` takes ownership on success; we free on failure.
      while let extra = PEM_read_bio_X509(certBio, nil, nil, nil) {
        do {
          try throwingOpenSSLError { COpenSSL_SSL_CTX_add_extra_chain_cert(ctx, extra) }
        } catch {
          X509_free(extra)
          throw error
        }
      }
    }
    try privateKey.withUnsafeBytes { keyBytes in
      let keyBio = try throwingOpenSSLError {
        BIO_new_mem_buf(keyBytes.baseAddress, CInt(keyBytes.count))
      }
      defer { BIO_free(keyBio) }
      let pkey = try throwingOpenSSLError { PEM_read_bio_PrivateKey(keyBio, nil, nil, nil) }
      defer { EVP_PKEY_free(pkey) }
      try throwingOpenSSLError { SSL_CTX_use_PrivateKey(ctx, pkey) }
    }
    try throwingOpenSSLError { SSL_CTX_check_private_key(ctx) }
  }

  private static func configurePKCS12(
    ctx: OpaquePointer,
    data: Data,
    password: String?
  ) throws {
    try data.withUnsafeBytes { raw in
      let bio = try throwingOpenSSLError { BIO_new_mem_buf(raw.baseAddress, CInt(raw.count)) }
      defer { BIO_free(bio) }
      let p12 = try throwingOpenSSLError { d2i_PKCS12_bio(bio, nil) }
      defer { PKCS12_free(p12) }

      var pkey: OpaquePointer?
      var cert: OpaquePointer?
      var chain: OpaquePointer?
      // Owned C buffer wipeable via OPENSSL_cleanse; no intermediate Swift
      // Array copy of the password survives parse.
      let pwUTF8 = (password ?? "").utf8
      let pwLen = pwUTF8.count
      let pwBuf = UnsafeMutableBufferPointer<CChar>.allocate(capacity: pwLen + 1)
      defer {
        OPENSSL_cleanse(UnsafeMutableRawPointer(pwBuf.baseAddress), pwLen + 1)
        pwBuf.deallocate()
      }
      pwBuf.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: pwLen + 1) { dest in
        var i = 0
        for byte in pwUTF8 {
          dest[i] = byte
          i += 1
        }
        dest[i] = 0
      }
      try throwingOpenSSLError { PKCS12_parse(p12, pwBuf.baseAddress, &pkey, &cert, &chain) }
      defer {
        if let pkey { EVP_PKEY_free(pkey) }
        if let cert { X509_free(cert) }
        if let chain { COpenSSL_sk_X509_pop_free(UnsafeMutableRawPointer(chain)) }
      }
      guard let pkey, let cert else {
        throw Ocp1OpenSSLError(code: 0, detail: collectErrorMessages())
      }
      try throwingOpenSSLError { SSL_CTX_use_certificate(ctx, cert) }
      try throwingOpenSSLError { SSL_CTX_use_PrivateKey(ctx, pkey) }
      try throwingOpenSSLError { SSL_CTX_check_private_key(ctx) }
      if let chain {
        let chainPtr = UnsafeMutableRawPointer(chain)
        let count = COpenSSL_sk_X509_num(chainPtr)
        for i in 0..<count {
          guard let intermediate = COpenSSL_sk_X509_value(chainPtr, i) else { continue }
          // Chain owns the original ref; SSL_CTX_add_extra_chain_cert takes
          // ownership of ours on success, otherwise we free it.
          _ = X509_up_ref(intermediate)
          do {
            try throwingOpenSSLError {
              COpenSSL_SSL_CTX_add_extra_chain_cert(ctx, intermediate)
            }
          } catch {
            X509_free(intermediate)
            throw error
          }
        }
      }
    }
  }

  /// Run an OpenSSL call returning the standard `1`-on-success integer and
  /// throw `Ocp1OpenSSLError` carrying the queued diagnostics otherwise.
  /// Generic over `FixedWidthInteger` so `int`-returning and the `long`-
  /// returning `SSL_CTX_ctrl` macros both flow through the same helper.
  ///
  /// Clears the thread-local error queue before `body()` so that on failure
  /// the surfaced diagnostics are only this call's — defends against
  /// stale entries left on the same cooperative-pool thread by other tasks.
  private static func throwingOpenSSLError(
    _ body: () throws -> some FixedWidthInteger
  ) throws {
    ERR_clear_error()
    guard try body() == 1 else {
      throw Ocp1OpenSSLError(code: 0, detail: collectErrorMessages())
    }
  }

  /// Run an OpenSSL call returning an optional pointer; unwrap on success
  /// or throw `Ocp1OpenSSLError`.
  private static func throwingOpenSSLError<T>(_ body: () throws -> T?) throws -> T {
    ERR_clear_error()
    guard let result = try body() else {
      throw Ocp1OpenSSLError(code: 0, detail: collectErrorMessages())
    }
    return result
  }

  fileprivate static func collectErrorMessages() -> String {
    var messages: [String] = []
    var buf = [CChar](repeating: 0, count: 256)
    while true {
      let code = ERR_get_error()
      if code == 0 { break }
      ERR_error_string_n(code, &buf, buf.count)
      let trimmed = buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
      messages.append(String(decoding: trimmed, as: UTF8.self))
    }
    if messages.isEmpty {
      return "(no detail in OpenSSL error queue)"
    }
    return messages.joined(separator: "; ")
  }
}

package struct Ocp1OpenSSLError: Error, CustomStringConvertible, Sendable {
  package let code: CInt
  package let detail: String

  package var description: String {
    detail.isEmpty ? "OpenSSL error (\(code))" : "OpenSSL error (\(code)): \(detail)"
  }
}

#endif
