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
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Network
@preconcurrency import Security
import SwiftOCA

/// Peer identity from a `.ready` `NWConnection`'s TLS metadata. Returns
/// `.anonymous` for PSK handshakes — Network.framework's public API doesn't
/// expose the negotiated PSK identity (only the locally-configured list).
func Ocp1NWExtractPeerIdentity(from connection: NWConnection) -> OcaPeerIdentity {
  guard
    let raw = connection.metadata(definition: NWProtocolTLS.definition),
    let tlsMeta = raw as? NWProtocolTLS.Metadata
  else {
    return .anonymous
  }
  let sec = tlsMeta.securityProtocolMetadata

  var leaf: SecCertificate?
  sec_protocol_metadata_access_peer_certificate_chain(sec, { cert in
    if leaf == nil { leaf = sec_certificate_copy_ref(cert).takeRetainedValue() }
  })
  guard let leaf else { return .anonymous }
  let subject = (SecCertificateCopySubjectSummary(leaf) as String?) ?? ""
  let der = SecCertificateCopyData(leaf) as Data
  let fp = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
  if subject.isEmpty, fp.isEmpty { return .anonymous }
  return .certificate(subject: subject, fingerprint: fp)
}

#endif
