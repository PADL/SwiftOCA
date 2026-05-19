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

#if SwiftNIOBackend

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore
import NIOSSL
import SwiftOCA

/// Maps `SwiftOCASecure`'s platform-neutral TLS types onto `NIOSSL`.
/// PSK, `SecIdentity` and revocation are rejected at construction so callers
/// that need them stay on `Ocp1OpenSSLConnection` / `Ocp1NWSecureTCPConnection`.
package enum Ocp1NIOTLSConfiguration {
  /// Build an SSL context for a NIO TLS client connection.
  package static func makeClientContext(
    credential: Ocp1TLSCredential,
    trustRoots: Ocp1TLSTrustRoots?,
    revocation: Ocp1TLSRevocationOptions,
    hostname: String?,
    verifyPeer: Bool
  ) throws -> NIOSSLContext {
    var config = TLSConfiguration.makeClientConfiguration()
    try applyClientCredential(credential, to: &config)
    try applyTrustRoots(trustRoots, to: &config)
    try rejectRevocation(revocation)
    if !verifyPeer {
      config.certificateVerification = .none
    } else if hostname == nil {
      config.certificateVerification = .noHostnameVerification
    } else {
      config.certificateVerification = .fullVerification
    }
    applyCipherPinning(&config)
    return try NIOSSLContext(configuration: config)
  }

  /// Build an SSL context for a NIO TLS server endpoint. `clientTrustRoots`
  /// non-nil enables mTLS.
  package static func makeServerContext(
    credential: Ocp1TLSCredential,
    clientCertificateTrustRoots: Ocp1TLSTrustRoots?,
    revocation: Ocp1TLSRevocationOptions
  ) throws -> NIOSSLContext {
    let (chain, key) = try parseServerCredential(credential)
    var config = TLSConfiguration.makeServerConfiguration(
      certificateChain: chain,
      privateKey: key
    )
    if let clientCertificateTrustRoots {
      try applyTrustRoots(clientCertificateTrustRoots, to: &config)
      config.certificateVerification = .noHostnameVerification
    } else {
      config.certificateVerification = .none
    }
    try rejectRevocation(revocation)
    applyCipherPinning(&config)
    return try NIOSSLContext(configuration: config)
  }

  // MARK: - Internal helpers

  private static func applyClientCredential(
    _ credential: Ocp1TLSCredential,
    to config: inout TLSConfiguration
  ) throws {
    let (chain, key) = try parseServerCredential(credential)
    config.certificateChain = chain
    config.privateKey = key
  }

  /// Reuses the client path: NIOSSL `TLSConfiguration` takes the same shape
  /// for both directions. Returns an empty chain + sentinel key when the
  /// caller hasn't supplied a credential (server may legitimately omit one
  /// while waiting for `OcaSecurityManager` to mint one).
  private static func parseServerCredential(
    _ credential: Ocp1TLSCredential
  ) throws -> (chain: [NIOSSLCertificateSource], key: NIOSSLPrivateKeySource) {
    switch credential {
    case let .certificateFile(certPath, keyPath):
      let certs = try NIOSSLCertificate.fromPEMFile(certPath)
      let key = try NIOSSLPrivateKey(file: keyPath, format: .pem)
      return (certs.map { .certificate($0) }, .privateKey(key))
    case let .certificatePEM(certData, keyData):
      let certs = try NIOSSLCertificate.fromPEMBytes(Array(certData))
      let key = try NIOSSLPrivateKey(bytes: Array(keyData), format: .pem)
      return (certs.map { .certificate($0) }, .privateKey(key))
    case let .pkcs12(data, password):
      let bytes = Array(data)
      let bundle: NIOSSLPKCS12Bundle
      if let password {
        bundle = try NIOSSLPKCS12Bundle(buffer: bytes, passphrase: password.utf8)
      } else {
        bundle = try NIOSSLPKCS12Bundle(buffer: bytes)
      }
      return (
        bundle.certificateChain.map { .certificate($0) },
        .privateKey(bundle.privateKey)
      )
    #if canImport(Security)
    case .identity:
      // SecIdentity carries an `SecCertificate` + `SecKey` reference that
      // NIOSSL can't consume directly; callers must export to PEM/PKCS#12.
      throw Ocp1Error.notImplemented
    #endif
    case .preSharedKey, .preSharedKeyProvider:
      // BoringSSL underneath NIOSSL doesn't ship the AES70-mandated
      // DHE-PSK cipher; we deliberately don't substitute TLS 1.3 external PSK.
      throw Ocp1Error.notImplemented
    }
  }

  private static func applyTrustRoots(
    _ trustRoots: Ocp1TLSTrustRoots?,
    to config: inout TLSConfiguration
  ) throws {
    guard let trustRoots else { return }
    switch trustRoots {
    case let .caFile(path):
      config.trustRoots = .file(path)
    case let .caData(data):
      let certs = try NIOSSLCertificate.fromPEMBytes(Array(data))
      config.trustRoots = .certificates(certs)
    }
  }

  /// CRL/OCSP isn't exposed by `NIOSSL`'s public surface; rather than
  /// silently honour the empty-flag case while ignoring CRLs, we throw if
  /// the caller asked for anything other than `.disabled`.
  private static func rejectRevocation(_ options: Ocp1TLSRevocationOptions) throws {
    guard options.flags.isEmpty else {
      throw Ocp1Error.notImplemented
    }
  }

  /// AES70-2024 §11.2.4 mandates `TLS_DHE_PSK_WITH_AES_128_CBC_SHA`, which
  /// requires PSK and isn't in BoringSSL's cipher set. With PSK out of
  /// scope for this backend, advertise the AEAD ciphers the OpenSSL engine
  /// already uses on the cert path.
  private static func applyCipherPinning(_ config: inout TLSConfiguration) {
    config.minimumTLSVersion = .tlsv12
  }
}

#endif
