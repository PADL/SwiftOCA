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
  init(_ address: any SocketAddress) {
    guard let host = hostAddressBytes(of: address) else {
      self = .unreachable
      return
    }
    if host.allSatisfy({ $0 == 0 }) {
      self = .wildcard
    } else if host.count == 4 ? host[0] == 127 : host[0..<15].allSatisfy({ $0 == 0 }) && host[15] == 1 {
      self = .unreachable
    } else {
      self = .specific
    }
  }
}

/// Where to announce the services of an endpoint bound to a given address.
package enum OcaBonjourAdvertisingScope: Equatable {
  /// any interface (`kDNSServiceInterfaceIndexAny`): a wildcard address
  case anyInterface
  /// the interface with this index, which holds the address
  case interface(UInt32)
  /// not advertised: a loopback or non-IP address, or a specific address no interface holds
  case noAddress

  /// The DNS-SD interface index to register on; nil for `noAddress`.
  package var interfaceIndex: UInt32? {
    switch self {
    case .anyInterface: 0
    case let .interface(index): index
    case .noAddress: nil
    }
  }
}

/// Where to announce the services of an endpoint bound to `address`. A link-local IPv6
/// address with a scope is announced on that scope's interface; `lookup` finds the
/// interface holding any other specific address.
package func bonjourAdvertisingScope(
  for address: any SocketAddress,
  lookup: (any SocketAddress) -> UInt32? = interfaceIndex(holding:)
) -> OcaBonjourAdvertisingScope {
  switch OcaBonjourListenAddressClass(address) {
  case .wildcard:
    return .anyInterface
  case .unreachable:
    return .noAddress
  case .specific:
    if let scope = ipv6ScopeID(of: address) { return .interface(scope) }
    return lookup(address).map { .interface($0) } ?? .noAddress
  }
}

/// The index of the interface holding `address`, an IPv4 or IPv6 address, from
/// `getifaddrs()` and `if_nametoindex()`; nil if no interface holds it.
package func interfaceIndex(holding address: any SocketAddress) -> UInt32? {
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
    if index != 0 { return index }
  }
  return nil
  #endif
}

/// The host part of an IPv4 address (4 bytes) or IPv6 address (16 bytes) in network order,
/// an IPv4-mapped IPv6 address as its IPv4 address; nil for any other family.
private func hostAddressBytes(of address: any SocketAddress) -> [UInt8]? {
  address.withSockAddr { sa, _ in hostAddressBytes(of: sa) }
}

private func hostAddressBytes(of sa: UnsafePointer<sockaddr>) -> [UInt8]? {
  let raw = UnsafeRawPointer(sa)
  switch Int32(sa.pointee.sa_family) {
  case AF_INET:
    return withUnsafeBytes(of: raw.load(as: sockaddr_in.self).sin_addr) { Array($0) }
  case AF_INET6:
    var host = withUnsafeBytes(of: raw.load(as: sockaddr_in6.self).sin6_addr) { Array($0) }
    if host[0..<10].allSatisfy({ $0 == 0 }), host[10] == 0xFF, host[11] == 0xFF {
      return Array(host[12..<16]) // IPv4-mapped (RFC 4291 section 2.5.5.2)
    }
    if host[0] == 0xFE, host[1] & 0xC0 == 0x80 {
      host[2] = 0 // link-local: Darwin's getifaddrs embeds the scope here (KAME)
      host[3] = 0
    }
    return host
  default:
    return nil
  }
}

/// The scope (interface index) of a scoped IPv6 address, or nil.
private func ipv6ScopeID(of address: any SocketAddress) -> UInt32? {
  address.withSockAddr { sa, _ in
    guard Int32(sa.pointee.sa_family) == AF_INET6 else { return nil }
    let scope = UnsafeRawPointer(sa).load(as: sockaddr_in6.self).sin6_scope_id
    return scope == 0 ? nil : scope
  }
}
