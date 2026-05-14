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

#if canImport(Network)

import CryptoKit
import Foundation
import Network
#if canImport(Security)
@preconcurrency import Security
#endif
import SocketAddress
@_spi(SwiftOCAPrivate)
import SwiftOCA

/// OCP.1 TLS-secured TCP connection via Apple's Network.framework. PSK uses
/// TLS 1.3 external PSK + AEAD; the AES70-mandated TLS_DHE_PSK_WITH_AES_128_
/// CBC_SHA is appended via raw IANA value (acceptance is best-effort).
public final class Ocp1NWSecureTCPConnection: Ocp1NWConnection {
  private let credential: Ocp1TLSCredential
  /// Pre-loaded at init so a bad CA bundle fails construction rather than
  /// silently disabling cert verification.
  private let preloadedAnchors: [SecCertificate]?
  private let revocation: Ocp1TLSRevocationOptions

  override public var connectionPrefix: String {
    "\(OcaSecureTcpConnectionPrefix)/\(presentationAddress)"
  }

  override public var isDatagram: Bool { false }

  override public var hasTransportLayerSecurity: Bool { true }

  override public var parameters: NWParameters {
    let tls = NWProtocolTLS.Options()
    let sec = tls.securityProtocolOptions
    Ocp1TLSCredential.enforceMinimumTLSProtocol(sec)
    // Pre-validated in init, so apply can't fail here.
    try? credential.apply(to: sec)
    // SNI without rewriting the NWEndpoint; the transport destination stays
    // at `_deviceAddress` for parity with the OpenSSL backend.
    if let serverHostname {
      serverHostname.withCString { _ = sec_protocol_options_set_tls_server_name(sec, $0) }
    }
    // Gate the permissive verify block to cert credentials: in PSK mode
    // it would only fire on a cert-downgrade attempt, and we'd rather fail
    // closed there.
    if options.flags.contains(.disableCertificateVerification),
       Self.credentialIsCert(credential)
    {
      Self.installPermissiveVerifyBlock(sec)
    } else if Self.credentialIsCert(credential) {
      Self.installVerifyBlock(
        sec,
        role: .client,
        anchors: preloadedAnchors,
        hostname: serverHostname,
        revocation: revocation
      )
    } else {
      // PSK client: install a fail-closed verify block so a server that
      // declines PSK and presents a cert cannot silently downgrade us to
      // cert auth. Mirrors OpenSSL's `_pskClientRejectCertCallback`.
      Self.installPSKClientRejectCertBlock(sec)
    }
    return NWParameters(tls: tls, tcp: makeTCPOptions())
  }

  /// Verify block that accepts everything. Only used when the caller opts
  /// into `disableCertificateVerification`.
  fileprivate nonisolated static func installPermissiveVerifyBlock(_ sec: sec_protocol_options_t) {
    let queue = DispatchQueue.global(qos: .userInitiated)
    sec_protocol_options_set_verify_block(sec, { _, _, complete in
      complete(true)
    }, queue)
  }

  /// Runs after chain validation; returning `false` rejects the handshake
  /// (e.g. for an mTLS allow-list). Called on the verify-block dispatch
  /// queue — keep work bounded and synchronous.
  public typealias PeerCertificateValidator = @Sendable (OcaPeerIdentity) -> Bool

  /// `SecPolicyCreateSSL(server:hostname:)` takes a single `Bool` direction.
  /// Mixing it (e.g. validating client certs with the server policy) lets
  /// `serverAuth`-only certs satisfy a client-cert check.
  package enum PeerRole: Sendable {
    case client
    case server
  }

  /// Re-roots trust at `anchors`, pins hostname only in client role,
  /// runs `peerValidator` against the leaf if supplied.
  fileprivate nonisolated static func installVerifyBlock(
    _ sec: sec_protocol_options_t,
    role: PeerRole,
    anchors: [SecCertificate]?,
    hostname: String?,
    revocation: Ocp1TLSRevocationOptions = .disabled,
    peerValidator: PeerCertificateValidator? = nil
  ) {
    let queue = DispatchQueue.global(qos: .userInitiated)
    let cfAnchors = anchors.map { $0 as CFArray }
    let policyHostname = hostname.map { $0 as CFString }
    let revocationEnabled = revocation.flags.contains(.enabled)
    sec_protocol_options_set_verify_block(sec, { _, trustRef, complete in
      let secTrust = sec_trust_copy_ref(trustRef).takeRetainedValue()
      let sslPolicy: SecPolicy = switch role {
      case .client: SecPolicyCreateSSL(true, policyHostname)
      case .server: SecPolicyCreateSSL(false, nil)
      }
      // Soft-fail: missing `RequirePositiveResponse` lets unreachable
      // responders pass the chain.
      var policies: [SecPolicy] = [sslPolicy]
      if revocationEnabled {
        if let rev = SecPolicyCreateRevocation(kSecRevocationUseAnyAvailableMethod) {
          policies.append(rev)
        }
      }
      SecTrustSetPolicies(secTrust, policies as CFArray)
      if let cfAnchors {
        SecTrustSetAnchorCertificates(secTrust, cfAnchors)
        SecTrustSetAnchorCertificatesOnly(secTrust, true)
      }
      var trustError: CFError?
      let trusted = SecTrustEvaluateWithError(secTrust, &trustError)
      guard trusted else {
        complete(false)
        return
      }
      if let peerValidator {
        let identity = extractPeerCertificateIdentity(from: secTrust)
        complete(peerValidator(identity))
        return
      }
      complete(true)
    }, queue)
  }

  /// Extract a `.certificate(...)` snapshot from the trust's leaf cert.
  /// Mirrors the `.ready`-time `Ocp1NWExtractPeerIdentity(from:)` path.
  private nonisolated static func extractPeerCertificateIdentity(
    from secTrust: SecTrust
  ) -> OcaPeerIdentity {
    let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate] ?? []
    guard let leaf = chain.first else { return .anonymous }
    let subject = (SecCertificateCopySubjectSummary(leaf) as String?) ?? ""
    let der = SecCertificateCopyData(leaf) as Data
    let fp = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    if subject.isEmpty, fp.isEmpty { return .anonymous }
    return .certificate(subject: subject, fingerprint: fp)
  }

  /// Server-side mTLS verify block: pins the client-auth SSL policy.
  package nonisolated static func installCustomTrustVerifyBlock(
    _ sec: sec_protocol_options_t,
    anchors: [SecCertificate],
    revocation: Ocp1TLSRevocationOptions = .disabled,
    peerValidator: PeerCertificateValidator? = nil
  ) {
    installVerifyBlock(
      sec,
      role: .server,
      anchors: anchors,
      hostname: nil,
      revocation: revocation,
      peerValidator: peerValidator
    )
  }

  /// PSK client fail-closed: any cert at the verify hook means the peer
  /// tried to downgrade us off PSK. Mirrors OpenSSL's reject callback.
  fileprivate nonisolated static func installPSKClientRejectCertBlock(
    _ sec: sec_protocol_options_t
  ) {
    let queue = DispatchQueue.global(qos: .userInitiated)
    sec_protocol_options_set_verify_block(sec, { _, _, complete in
      complete(false)
    }, queue)
  }

  /// Parse a PEM blob into `SecCertificate` values. `nil` only when
  /// `trustRoots == nil`; supplied-but-unreadable / empty throws — a CA
  /// path typo must not silently fall back to the system trust store.
  package nonisolated static func loadAnchorCertificates(
    from trustRoots: Ocp1TLSTrustRoots?
  ) throws -> [SecCertificate]? {
    guard let trustRoots else { return nil }
    let pemData: Data?
    switch trustRoots {
    case let .caFile(path):
      pemData = try? Data(contentsOf: URL(fileURLWithPath: path))
    case let .caData(data):
      pemData = data
    }
    guard let raw = pemData, let text = String(data: raw, encoding: .utf8) else {
      throw Ocp1Error.status(.parameterError)
    }
    let begin = "-----BEGIN CERTIFICATE-----"
    let end = "-----END CERTIFICATE-----"
    var anchors: [SecCertificate] = []
    var cursor = text.startIndex
    while let beginRange = text.range(of: begin, range: cursor..<text.endIndex),
          let endRange = text.range(of: end, range: beginRange.upperBound..<text.endIndex)
    {
      let body = text[beginRange.upperBound..<endRange.lowerBound]
        .replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\n", with: "")
        .replacingOccurrences(of: " ", with: "")
      if let der = Data(base64Encoded: body),
         let cert = SecCertificateCreateWithData(nil, der as CFData)
      {
        anchors.append(cert)
      }
      cursor = endRange.upperBound
    }
    guard !anchors.isEmpty else {
      throw Ocp1Error.status(.parameterError)
    }
    return anchors
  }

  /// `true` when the credential is certificate-based (i.e. anything except PSK).
  package nonisolated static func credentialIsCert(_ credential: Ocp1TLSCredential) -> Bool {
    switch credential {
    case .preSharedKey, .preSharedKeyProvider: return false
    default: return true
    }
  }

  /// Used for SNI and as the `SecPolicyCreateSSL` hostname in the verify
  /// block; the `NWEndpoint` is left at the IP from `deviceAddress`.
  private let serverHostname: String?

  private let trustRoots: Ocp1TLSTrustRoots?

  private init(
    deviceAddress: AnySocketAddress,
    credential: Ocp1TLSCredential,
    hostname: String?,
    trustRoots: Ocp1TLSTrustRoots?,
    revocation: Ocp1TLSRevocationOptions,
    options: Ocp1ConnectionOptions
  ) throws {
    try credential.validate()
    let verifyPeer = !options.flags.contains(.disableCertificateVerification)
    if verifyPeer, Self.credentialIsCert(credential), hostname == nil {
      // Cert + verifyPeer needs a hostname; chain-only would accept any
      // cert from the configured CA.
      throw Ocp1Error.status(.parameterError)
    }
    try credential.validateAppleLoad()
    let preloaded = try Self.loadAnchorCertificates(from: trustRoots)

    self.credential = credential
    serverHostname = hostname
    self.trustRoots = trustRoots
    preloadedAnchors = preloaded
    self.revocation = revocation
    try super.init(deviceAddress: deviceAddress, options: options)
  }

  public convenience init(
    deviceAddress: Data,
    credential: Ocp1TLSCredential,
    hostname: String? = nil,
    trustRoots: Ocp1TLSTrustRoots? = nil,
    revocation: Ocp1TLSRevocationOptions = .disabled,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    let address = try AnySocketAddress(bytes: Array(deviceAddress))
    try self.init(
      deviceAddress: address,
      credential: credential,
      hostname: hostname,
      trustRoots: trustRoots,
      revocation: revocation,
      options: options
    )
  }

  public convenience init(
    path: String,
    credential: Ocp1TLSCredential,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    let address = try AnySocketAddress(
      family: sa_family_t(AF_LOCAL),
      presentationAddress: path
    )
    try self.init(
      deviceAddress: address,
      credential: credential,
      hostname: nil,
      trustRoots: nil,
      revocation: .disabled,
      options: options
    )
  }
}

/// OCP.1 DTLS-secured UDP connection via Apple's Network.framework. Mirrors
/// `Ocp1NWSecureTCPConnection`; Network.framework reuses the TLS
/// `sec_protocol_options_t` configuration for DTLS.
public final class Ocp1NWSecureUDPConnection: Ocp1NWConnection {
  private let credential: Ocp1TLSCredential
  private let serverHostname: String?
  private let trustRoots: Ocp1TLSTrustRoots?
  private let preloadedAnchors: [SecCertificate]?
  private let revocation: Ocp1TLSRevocationOptions

  override public var heartbeatTime: Duration {
    .seconds(1)
  }

  override public var connectionPrefix: String {
    "\(OcaSecureUdpConnectionPrefix)/\(presentationAddress)"
  }

  override public var isDatagram: Bool { true }

  override public var hasTransportLayerSecurity: Bool { true }

  override public var parameters: NWParameters {
    // Network.framework spells DTLS as TLS options over UDP — no separate
    // NWProtocolDTLS class.
    let tls = NWProtocolTLS.Options()
    let sec = tls.securityProtocolOptions
    Ocp1TLSCredential.enforceMinimumTLSProtocol(sec)
    try? credential.apply(to: sec)
    if let serverHostname {
      serverHostname.withCString { _ = sec_protocol_options_set_tls_server_name(sec, $0) }
    }
    if options.flags.contains(.disableCertificateVerification),
       Ocp1NWSecureTCPConnection.credentialIsCert(credential)
    {
      Ocp1NWSecureTCPConnection.installPermissiveVerifyBlock(sec)
    } else if Ocp1NWSecureTCPConnection.credentialIsCert(credential) {
      Ocp1NWSecureTCPConnection.installVerifyBlock(
        sec,
        role: .client,
        anchors: preloadedAnchors,
        hostname: serverHostname,
        revocation: revocation
      )
    } else {
      // PSK DTLS client: see TCP variant. Fail closed on cert downgrade.
      Ocp1NWSecureTCPConnection.installPSKClientRejectCertBlock(sec)
    }
    return NWParameters(dtls: tls, udp: NWProtocolUDP.Options())
  }

  private init(
    deviceAddress: AnySocketAddress,
    credential: Ocp1TLSCredential,
    hostname: String?,
    trustRoots: Ocp1TLSTrustRoots?,
    revocation: Ocp1TLSRevocationOptions,
    options: Ocp1ConnectionOptions
  ) throws {
    try credential.validate()
    let verifyPeer = !options.flags.contains(.disableCertificateVerification)
    if verifyPeer, Ocp1NWSecureTCPConnection.credentialIsCert(credential), hostname == nil {
      throw Ocp1Error.status(.parameterError)
    }
    try credential.validateAppleLoad()
    let preloaded = try Ocp1NWSecureTCPConnection.loadAnchorCertificates(from: trustRoots)

    self.credential = credential
    serverHostname = hostname
    self.trustRoots = trustRoots
    preloadedAnchors = preloaded
    self.revocation = revocation
    try super.init(deviceAddress: deviceAddress, options: options)
  }

  public convenience init(
    deviceAddress: Data,
    credential: Ocp1TLSCredential,
    hostname: String? = nil,
    trustRoots: Ocp1TLSTrustRoots? = nil,
    revocation: Ocp1TLSRevocationOptions = .disabled,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    let address = try AnySocketAddress(bytes: Array(deviceAddress))
    try self.init(
      deviceAddress: address,
      credential: credential,
      hostname: hostname,
      trustRoots: trustRoots,
      revocation: revocation,
      options: options
    )
  }
}

extension Ocp1TLSCredential {
  /// Install this credential on a `sec_protocol_options_t`. Throws on
  /// malformed material — use `validateAppleLoad()` at construction time
  /// to surface import failures before handshake.
  package func apply(to sec: sec_protocol_options_t) throws {
    try _loadAndApply(to: sec)
  }

  /// Exercise the load path without applying. Shares the loader with
  /// `apply(to:)` so a new credential variant is exercised by both.
  package func validateAppleLoad() throws {
    try _loadAndApply(to: nil)
  }

  /// Parse the credential's cert/PKCS#12/PEM material; install on `sec`
  /// when non-nil. With `sec == nil` the parse still runs and throws on
  /// malformed input (what `validateAppleLoad()` needs).
  private func _loadAndApply(to sec: sec_protocol_options_t?) throws {
    switch self {
    case let .preSharedKey(identity, key):
      if let sec { Self.configurePSK(sec, identity: identity, key: key) }
    case let .preSharedKeyProvider(identity, provider):
      if let sec { Self.configurePSK(sec, identity: identity, provider: provider) }
    #if canImport(Security)
    case let .identity(secIdentity):
      if let sec { try Self._configureLocalIdentity(sec, secIdentity: secIdentity) }
    #endif
    case let .pkcs12(data, password):
      #if canImport(Security)
      let identity = try Self._parsePKCS12(data: data, password: password)
      if let sec { try Self._configureLocalIdentity(sec, secIdentity: identity) }
      #else
      throw Ocp1Error.status(.notImplemented)
      #endif
    case let .certificatePEM(certificate, privateKey):
      #if os(macOS)
      let (identity, chain) = try Self._parsePEM(
        certificate: certificate,
        privateKey: privateKey
      )
      if let sec { try Self._applyPEMIdentity(sec, identity: identity, chain: chain) }
      #else
      // SecItemImport (PEM aggregate import) is macOS-only; other Apple
      // platforms must pre-package as PKCS#12.
      throw Ocp1Error.status(.notImplemented)
      #endif
    case let .certificateFile(certPath, keyPath):
      #if os(macOS)
      let certData = try Data(contentsOf: URL(fileURLWithPath: certPath))
      var keyData = try Data(contentsOf: URL(fileURLWithPath: keyPath))
      // Zero our buffer once Security.framework has the bytes; the OS may
      // retain its own copy inside the imported identity.
      defer { keyData.resetBytes(in: 0..<keyData.count) }
      let (identity, chain) = try Self._parsePEM(certificate: certData, privateKey: keyData)
      if let sec { try Self._applyPEMIdentity(sec, identity: identity, chain: chain) }
      #else
      throw Ocp1Error.status(.notImplemented)
      #endif
    }
  }

  package static func configurePSK(
    _ sec: sec_protocol_options_t,
    identity: String,
    key: Data
  ) {
    key.withUnsafeBytes { _configurePSK(sec, identity: identity, keyBytes: $0) }
  }

  /// Install the PSK for `identity` from `provider` without copying the
  /// key into our heap. Silently does nothing if the provider has no key.
  package static func configurePSK(
    _ sec: sec_protocol_options_t,
    identity: String,
    provider: any OcaPreSharedKeyProvider
  ) {
    _ = provider.withPreSharedKey(forIdentity: identity) { buf in
      _configurePSK(sec, identity: identity, keyBytes: UnsafeRawBufferPointer(buf))
    }
  }

  private static func _configurePSK(
    _ sec: sec_protocol_options_t,
    identity: String,
    keyBytes: UnsafeRawBufferPointer
  ) {
    // Hand Network.framework a `bytesNoCopy` DispatchData over an owned
    // heap buffer with a zero-on-release deallocator so the PSK bytes
    // are wiped when NW drops its retained reference, not just freed.
    let keyBuf = UnsafeMutableRawBufferPointer.allocate(byteCount: keyBytes.count, alignment: 1)
    if let dst = keyBuf.baseAddress, let src = keyBytes.baseAddress {
      dst.copyMemory(from: src, byteCount: keyBytes.count)
    }
    let keyDispatch = DispatchData(
      bytesNoCopy: UnsafeRawBufferPointer(keyBuf),
      deallocator: .custom(nil, {
        keyBuf.initializeMemory(as: UInt8.self, repeating: 0)
        keyBuf.deallocate()
      })
    )
    let identityDispatch = Data(identity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
    sec_protocol_options_add_pre_shared_key(
      sec,
      keyDispatch as __DispatchData,
      identityDispatch as __DispatchData
    )
    // AES70 mandates TLS_DHE_PSK_WITH_AES_128_CBC_SHA (IANA 0x0090); not
    // in the public `tls_ciphersuite_t` enum so we attempt it raw, with
    // the TLS 1.3 AEAD suite as fallback.
    if let mandated = tls_ciphersuite_t(rawValue: 0x0090) {
      sec_protocol_options_append_tls_ciphersuite(sec, mandated)
    }
    sec_protocol_options_append_tls_ciphersuite(sec, .AES_128_GCM_SHA256)
  }

  /// Pin every TLS/DTLS handshake to 1.2+ and disable resumption /
  /// false-start / 0-RTT. Control-plane mTLS re-auths every connection,
  /// and OCP.1 has no idempotent commands so replayable early data is
  /// unsafe.
  package static func enforceMinimumTLSProtocol(_ sec: sec_protocol_options_t) {
    sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
    sec_protocol_options_set_tls_resumption_enabled(sec, false)
    sec_protocol_options_set_tls_false_start_enabled(sec, false)
    sec_protocol_options_set_tls_tickets_enabled(sec, false)
  }

  #if canImport(Security)
  private static func _configureLocalIdentity(
    _ sec: sec_protocol_options_t,
    secIdentity: SecIdentity
  ) throws {
    guard let identity = sec_identity_create(secIdentity) else {
      throw Ocp1Error.status(.parameterError)
    }
    sec_protocol_options_set_local_identity(sec, identity)
  }

  private static func _parsePKCS12(data: Data, password: String?) throws -> SecIdentity {
    var options: [String: Any] = [:]
    // Copy the password into an owned byte buffer and hand a CFString
    // built from it to `SecPKCS12Import`. The buffer is wiped on exit;
    // CF's internal copy lives transiently in CF heap (out of our reach,
    // but bounded by the call).
    var pwBuf: UnsafeMutableBufferPointer<UInt8>?
    defer {
      if let buf = pwBuf {
        UnsafeMutableRawBufferPointer(buf).initializeMemory(as: UInt8.self, repeating: 0)
        buf.deallocate()
      }
    }
    if let password {
      let utf8 = Array(password.utf8)
      let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: utf8.count)
      _ = buf.initialize(from: utf8)
      pwBuf = buf
      if let cfstr = CFStringCreateWithBytes(
        kCFAllocatorDefault,
        buf.baseAddress,
        buf.count,
        CFStringBuiltInEncodings.UTF8.rawValue,
        false
      ) {
        options[kSecImportExportPassphrase as String] = cfstr
      }
    }
    var rawItems: CFArray?
    let status = SecPKCS12Import(data as CFData, options as CFDictionary, &rawItems)
    guard status == errSecSuccess else {
      // Surface the OSStatus — without it, "parameterError" hides the
      // common causes (wrong/empty passphrase, modern PBE the platform
      // refuses, malformed bag).
      throw NSError(
        domain: NSOSStatusErrorDomain,
        code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: "SecPKCS12Import failed: OSStatus \(status)"]
      )
    }
    guard let items = rawItems as? [[String: Any]],
          let item = items.first,
          let identityRef = item[kSecImportItemIdentity as String]
    else {
      throw Ocp1Error.status(.parameterError)
    }
    return identityRef as! SecIdentity
  }
  #endif

  #if os(macOS)
  /// Import PEM cert (+ optional chain) and private key into a `SecIdentity`.
  /// macOS only — `SecItemImport` is unavailable elsewhere.
  private static func _parsePEM(
    certificate: Data,
    privateKey: Data
  ) throws -> (SecIdentity, [SecCertificate]) {
    var combined = certificate
    if combined.last != UInt8(ascii: "\n") {
      combined.append(UInt8(ascii: "\n"))
    }
    combined.append(privateKey)
    defer { combined.resetBytes(in: 0..<combined.count) }

    var inputFormat = SecExternalFormat.formatPEMSequence
    var itemType = SecExternalItemType.itemTypeAggregate
    var outItems: CFArray?

    let status = SecItemImport(
      combined as CFData,
      nil,
      &inputFormat,
      &itemType,
      SecItemImportExportFlags(rawValue: 0),
      nil,
      nil,
      &outItems
    )
    guard status == errSecSuccess, let items = outItems as? [AnyObject] else {
      throw Ocp1Error.status(.parameterError)
    }

    var identity: SecIdentity?
    var chain: [SecCertificate] = []
    for item in items {
      switch CFGetTypeID(item) {
      case SecIdentityGetTypeID():
        identity = (item as! SecIdentity)
      case SecCertificateGetTypeID():
        chain.append(item as! SecCertificate)
      default:
        break
      }
    }
    guard let identity else {
      throw Ocp1Error.status(.parameterError)
    }
    return (identity, chain)
  }

  /// Plug a parsed identity (+ optional chain) in as the local identity.
  private static func _applyPEMIdentity(
    _ sec: sec_protocol_options_t,
    identity: SecIdentity,
    chain: [SecCertificate]
  ) throws {
    let secIdentity: sec_identity_t? = chain.isEmpty
      ? sec_identity_create(identity)
      : sec_identity_create_with_certificates(identity, chain as CFArray)
    guard let secIdentity else {
      throw Ocp1Error.status(.parameterError)
    }
    sec_protocol_options_set_local_identity(sec, secIdentity)
  }
  #endif
}

#endif
