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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Security)
@preconcurrency import Security
#endif
import SwiftOCA

/// Connection-prefix shown in logging for TLS-secured TCP transports.
public let OcaSecureTcpConnectionPrefix = "ocasec/tcp"
/// Connection-prefix shown in logging for DTLS-secured UDP transports.
public let OcaSecureUdpConnectionPrefix = "ocasec/udp"

/// Credential for OCP.1 TLS authentication. AES70-2024 mandates
/// `TLS_DHE_PSK_WITH_AES_128_CBC_SHA` with PSK identity hint `OCA-PSK`; the
/// cert-based variants are for future / non-spec deployments.
public enum Ocp1TLSCredential: Sendable {
  /// Raw PSK bytes embedded in the credential. Prefer
  /// `.preSharedKeyProvider` when the key lives in secure storage —
  /// otherwise the bytes sit in caller-visible heap for the whole
  /// connection lifetime (and, on Apple, are copied into `DispatchData`).
  case preSharedKey(identity: String, key: Data)

  /// PSK fetched on-demand via an `OcaPreSharedKeyProvider`, so the bytes
  /// stay in caller-controlled storage. The TLS backend may still make its
  /// own internal copy.
  case preSharedKeyProvider(identity: String, provider: any OcaPreSharedKeyProvider)

  #if canImport(Security)
  /// TLS certificate identity from Security.framework (Apple platforms).
  case identity(SecIdentity)
  #endif

  /// PEM-encoded certificate and private key file paths.
  case certificateFile(certPath: String, keyPath: String)

  /// PEM-encoded certificate and private key in memory.
  case certificatePEM(certificate: Data, privateKey: Data)

  /// PKCS#12-encoded certificate and private key.
  case pkcs12(data: Data, password: String?)
}

/// Well-known PSK identity hint advertised by AES70 devices (`OCA-PSK`).
public let OcaPreSharedKeyIdentityHint: String = "OCA-PSK"

/// Minimum acceptable PSK length, in bytes (RFC 9257 §6's 128-bit floor).
public let OcaMinimumPreSharedKeyLength: Int = 16

public extension Ocp1TLSCredential {
  /// Reject weak PSK configuration up front; cert variants surface their
  /// parse / load failures separately at the backend layer.
  func validate() throws {
    switch self {
    case let .preSharedKey(identity, key):
      guard !identity.isEmpty else {
        throw Ocp1Error.status(.parameterError)
      }
      guard key.count >= OcaMinimumPreSharedKeyLength else {
        throw Ocp1Error.status(.parameterError)
      }
    case let .preSharedKeyProvider(identity, provider):
      guard !identity.isEmpty else {
        throw Ocp1Error.status(.parameterError)
      }
      // Length-check via the provider without keeping a copy.
      let ok = provider.withPreSharedKey(forIdentity: identity) { keyBuf in
        keyBuf.count >= OcaMinimumPreSharedKeyLength
      }
      guard ok == true else {
        throw Ocp1Error.status(.parameterError)
      }
    default:
      break
    }
  }
}

/// Source of TLS trust anchors. `nil` on a connection means "use the
/// platform default"; supply a value to re-root trust at a private CA.
public enum Ocp1TLSTrustRoots: Sendable {
  /// PEM CA bundle on disk.
  case caFile(String)
  /// PEM CA bundle held in memory.
  case caData(Data)
}

/// CRL bundle for OpenSSL revocation checking. Apple ignores this — its
/// Security.framework fetches CRL/OCSP responses itself.
public enum Ocp1TLSCRLBundle: Sendable {
  /// PEM-encoded CRL(s) on disk.
  case crlFile(String)
  /// PEM-encoded CRL(s) in memory.
  case crlData(Data)
}

/// Opt-in revocation checking. Empty flags = disabled.
public struct Ocp1TLSRevocationOptions: Sendable {
  public struct Flags: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    /// Master switch. Apple: soft-fail `SecPolicyCreateRevocation`.
    /// OpenSSL: arms `CRL_CHECK` when `crls` are supplied.
    public static let enabled = Flags(rawValue: 1 << 0)

    /// CRL-check intermediates too (OpenSSL `X509_V_FLAG_CRL_CHECK_ALL`).
    /// Requires every intermediate's CRL in the bundle. Ignored on Apple.
    public static let checkChain = Flags(rawValue: 1 << 1)

    /// Strictest opt-in: enable + chain-wide check. Preferred for new code.
    public static let strict: Flags = [.enabled, .checkChain]
  }

  public var flags: Flags

  /// CRLs to load into the OpenSSL trust store. Ignored on Apple
  /// (Security.framework fetches CRL/OCSP itself).
  public var crls: Ocp1TLSCRLBundle?

  public static let disabled = Self(flags: [], crls: nil)

  public init(flags: Flags = [], crls: Ocp1TLSCRLBundle? = nil) {
    self.flags = flags
    self.crls = crls
  }
}

#if canImport(Network)
public typealias Ocp1TLSStreamConnection = Ocp1NWSecureTCPConnection
public typealias Ocp1TLSDatagramConnection = Ocp1NWSecureUDPConnection
#elseif canImport(COpenSSL) && canImport(IORing)
public typealias Ocp1TLSStreamConnection = Ocp1OpenSSLConnection
public typealias Ocp1TLSDatagramConnection = Ocp1OpenSSLDTLSConnection
#endif
