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

/// Authenticated identity of an OCP.1 peer. Snapshotted at handshake
/// completion as plain values — holds no credential material, no retained
/// X509/SecCertificate refs, safe to use as a Hashable ACL key.
public enum OcaPeerIdentity: Sendable, Hashable {
  /// Identity the peer sent in the ClientHello PSK identity field; cleartext
  /// on the wire, so callers MUST NOT use secret material here.
  case preSharedKey(identity: String)

  /// X.509 leaf, already chain-validated. `fingerprint` is the lower-case
  /// hex SHA-256 of the DER and is the recommended ACL key — DN equality
  /// can be defeated by reissue against an unchanged public key.
  case certificate(subject: String, fingerprint: String)

  /// Non-TLS, or TLS with `disableCertificateVerification`. MUST NOT be
  /// eligible for privileged operations.
  case anonymous

  public var isAuthenticated: Bool {
    if case .anonymous = self { return false }
    return true
  }
}

extension OcaPeerIdentity: CustomStringConvertible {
  public var description: String {
    switch self {
    case .preSharedKey(let id):
      return "psk:\(id)"
    case .certificate(let subject, let fp):
      let short = fp.count > 16 ? String(fp.prefix(16)) + "…" : fp
      return "x509:\(subject) fp=\(short)"
    case .anonymous:
      return "anonymous"
    }
  }
}
