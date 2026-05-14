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

#if canImport(COpenSSL) && canImport(IORing)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SocketAddress
@_spi(SwiftOCAPrivate)
import SwiftOCA
import Synchronization

/// Routes outbound datagrams to a fixed peer through the DTLS endpoint's
/// shared UDP socket. Holds `endpoint` weakly so endpoint shutdown surfaces
/// as `.notConnected` instead of pinning lifetime.
final class _EndpointDatagramChannel: Ocp1DatagramChannel, @unchecked Sendable {
  private weak var endpoint: Ocp1OpenSSLDTLSDeviceEndpoint?
  private let peer: AnySocketAddress
  private let closed = Mutex(false)

  init(endpoint: Ocp1OpenSSLDTLSDeviceEndpoint, peer: AnySocketAddress) {
    self.endpoint = endpoint
    self.peer = peer
  }

  func send(_ data: Data) async throws {
    if closed.withLock({ $0 }) { throw Ocp1Error.notConnected }
    guard let endpoint else { throw Ocp1Error.notConnected }
    try await endpoint.sendDatagram(data, to: peer)
  }

  func close() async {
    closed.withLock { $0 = true }
  }
}

#endif
