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

import Dispatch
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SocketAddress
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif

/// `getaddrinfo` is a blocking syscall with no portable async form, so run it on
/// a dedicated queue — never on the `OcaConnection` global actor — and present an
/// `async` interface. This keeps name resolution asynchronous from the caller's
/// perspective: the actor (and the Swift cooperative pool) is never blocked.
private let _resolverQueue = DispatchQueue(
  label: "com.padl.SwiftOCA.hostname-resolver",
  attributes: .concurrent
)

package func _resolveDeviceAddresses(
  host: String,
  port: UInt16,
  isDatagram: Bool
) async -> [AnySocketAddress] {
  await withCheckedContinuation { continuation in
    _resolverQueue.async {
      continuation.resume(returning: _resolveDeviceAddressesBlocking(
        host: host,
        port: port,
        isDatagram: isDatagram
      ))
    }
  }
}

/// Resolve `host`:`port` to `sockaddr` candidates in the system's preferred order
/// (RFC 6724 on a modern resolver). Returns an empty array when the name does not
/// resolve — the caller treats that as "not reachable yet" and retries.
private func _resolveDeviceAddressesBlocking(
  host: String,
  port: UInt16,
  isDatagram: Bool
) -> [AnySocketAddress] {
  var hints = addrinfo()
  hints.ai_family = AF_UNSPEC // both IPv4 and IPv6
  hints.ai_socktype = isDatagram ? SOCK_DGRAM : SOCK_STREAM
  hints.ai_flags = AI_ADDRCONFIG // only families with a configured local address

  var result: UnsafeMutablePointer<addrinfo>?
  guard getaddrinfo(host, String(port), &hints, &result) == 0, let result else {
    return []
  }
  defer { freeaddrinfo(result) }

  var addresses: [AnySocketAddress] = []
  var candidate: UnsafeMutablePointer<addrinfo>? = result
  while let info = candidate {
    if let sa = info.pointee.ai_addr {
      let bytes = UnsafeRawBufferPointer(start: sa, count: Int(info.pointee.ai_addrlen))
      if let address = try? AnySocketAddress(bytes: Array(bytes)) {
        addresses.append(address)
      }
    }
    candidate = info.pointee.ai_next
  }
  return addresses
}
