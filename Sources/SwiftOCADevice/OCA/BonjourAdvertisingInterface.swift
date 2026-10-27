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

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
#endif
import SocketAddress

/// The address a device endpoint is bound to, as the SocketAddress package models it. An alias,
/// so that endpoints built on other socket libraries (FlyingSocks has a `SocketAddress` of its own)
/// can name it unambiguously.
public typealias OcaBonjourListenAddress = any SocketAddress

/// What an endpoint's bound address says about where its DNS-SD services may be announced.
package enum OcaBonjourListenAddressClass: Equatable {
  /// an unspecified (wildcard) address: every interface
  case wildcard
  /// a specific IPv4 or IPv6 address: only the interface holding it
  case specific
  /// a loopback address or a non-IP endpoint: nothing remote can reach it
  case unreachable
}

package extension OcaBonjourListenAddressClass {
  /// Classifies `address`, an IPv4, IPv6 or other socket address.
  init(_ address: OcaBonjourListenAddress) {
    guard let host = hostAddressBytes(of: address) else {
      self = .unreachable
      return
    }
    if host.count == 16, host[0..<10].allSatisfy({ $0 == 0 }), host[10] == 0xFF, host[11] == 0xFF {
      self.init(ipv4: Array(host[12..<16])) // IPv4-mapped (RFC 4291 section 2.5.5.2)
    } else if host.count == 4 {
      self.init(ipv4: host)
    } else if host.allSatisfy({ $0 == 0 }) {
      self = .wildcard
    } else if host[0..<15].allSatisfy({ $0 == 0 }), host[15] == 1 {
      self = .unreachable
    } else {
      self = .specific
    }
  }

  private init(ipv4 host: [UInt8]) {
    if host.allSatisfy({ $0 == 0 }) {
      self = .wildcard
    } else if host[0] == 127 {
      self = .unreachable
    } else {
      self = .specific
    }
  }
}

/// The DNS-SD interface index to announce a service bound to `address` on: 0
/// (`kDNSServiceInterfaceIndexAny`) for every interface, or nil to announce it nowhere.
/// `lookup` finds the interface holding a specific address; if none holds it,
/// the service is announced on every interface.
package func bonjourInterfaceIndex(
  for address: OcaBonjourListenAddress,
  lookup: (OcaBonjourListenAddress) -> UInt32? = interfaceIndex(holding:),
  onNoInterface: (OcaBonjourListenAddress) -> () = { _ in }
) -> UInt32? {
  switch OcaBonjourListenAddressClass(address) {
  case .wildcard:
    return 0
  case .unreachable:
    return nil
  case .specific:
    if let index = lookup(address) { return index }
    onNoInterface(address)
    return 0
  }
}

/// The index of the interface holding `address`, an IPv4 or IPv6 address, from
/// `getifaddrs()` and `if_nametoindex()`; nil if no interface holds it.
package func interfaceIndex(holding address: OcaBonjourListenAddress) -> UInt32? {
  #if canImport(WinSDK)
  return nil
  #else
  guard let host = hostAddressBytes(of: address) else { return nil }

  var ifaddrs: UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&ifaddrs) == 0 else { return nil }
  defer { freeifaddrs(ifaddrs) }

  for ifa in sequence(first: ifaddrs, next: { $0?.pointee.ifa_next }) {
    guard let ifa, let ifaAddr = ifa.pointee.ifa_addr, hostAddressBytes(of: ifaAddr) == host else { continue }
    let index = if_nametoindex(ifa.pointee.ifa_name)
    if index != 0 { return UInt32(index) }
  }
  return nil
  #endif
}

/// The host part of an IPv4 (4 bytes) or IPv6 (16 bytes) address in network order; nil for any
/// other family.
private func hostAddressBytes(of address: OcaBonjourListenAddress) -> [UInt8]? {
  address.withSockAddr { sa, _ in hostAddressBytes(of: sa) }
}

private func hostAddressBytes(of sa: UnsafePointer<sockaddr>) -> [UInt8]? {
  let raw = UnsafeRawPointer(sa)
  switch Int32(sa.pointee.sa_family) {
  case AF_INET:
    return withUnsafeBytes(of: raw.load(as: sockaddr_in.self).sin_addr) { Array($0) }
  case AF_INET6:
    return withUnsafeBytes(of: raw.load(as: sockaddr_in6.self).sin6_addr) { Array($0) }
  default:
    return nil
  }
}
