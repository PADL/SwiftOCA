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

import Crypto
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOSSL
import SwiftOCA

/// Compute `OcaPeerIdentity` from the leaf cert NIOSSL exposes after handshake.
/// `subject` mirrors NIOSSL's debug description (which embeds the CN and SANs);
/// `fingerprint` is the canonical lower-case hex SHA-256 of the DER, matching
/// the Network.framework and OpenSSL backends.
func Ocp1NIOExtractPeerIdentity(from certificate: NIOSSLCertificate?) -> OcaPeerIdentity {
  guard let certificate else { return .anonymous }
  do {
    let der = try certificate.toDERBytes()
    let fingerprint = SHA256.hash(data: der)
      .map { String(format: "%02x", $0) }
      .joined()
    let subject = String(describing: certificate)
    return .certificate(subject: subject, fingerprint: fingerprint)
  } catch {
    return .anonymous
  }
}

#endif
