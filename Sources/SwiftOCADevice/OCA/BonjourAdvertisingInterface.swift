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
  init(_ address: sockaddr_storage) {
    switch Int32(address.ss_family) {
    case AF_INET:
      let s_addr = withUnsafeBytes(of: address) {
        $0.load(as: sockaddr_in.self).sin_addr.s_addr
      }
      self.init(ipv4HostOrder: UInt32(bigEndian: s_addr))
    case AF_INET6:
      let bytes = withUnsafeBytes(of: address) {
        withUnsafeBytes(of: $0.load(as: sockaddr_in6.self).sin6_addr) { Array($0) }
      }
      if bytes.allSatisfy({ $0 == 0 }) {
        self = .wildcard
      } else if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 {
        self = .unreachable
      } else if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF {
        // IPv4-mapped (RFC 4291 section 2.5.5.2)
        self.init(ipv4HostOrder: bytes[12..<16].reduce(0) { $0 << 8 | UInt32($1) })
      } else {
        self = .specific
      }
    default:
      self = .unreachable
    }
  }

  private init(ipv4HostOrder address: UInt32) {
    if address == 0 {
      self = .wildcard
    } else if address >> 24 == 127 {
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
  for address: sockaddr_storage,
  lookup: (sockaddr_storage) -> UInt32? = interfaceIndex(holding:),
  onNoInterface: (sockaddr_storage) -> () = { _ in }
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
package func interfaceIndex(holding address: sockaddr_storage) -> UInt32? {
  #if canImport(WinSDK)
  return nil
  #else
  let family = Int32(address.ss_family)
  guard family == AF_INET || family == AF_INET6 else { return nil }

  var ifaddrs: UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&ifaddrs) == 0 else { return nil }
  defer { freeifaddrs(ifaddrs) }

  for ifa in sequence(first: ifaddrs, next: { $0?.pointee.ifa_next }) {
    guard let ifa, let ifaAddr = ifa.pointee.ifa_addr,
          Int32(ifaAddr.pointee.sa_family) == family,
          hostAddressesMatch(ifaAddr, address)
    else { continue }
    let index = if_nametoindex(ifa.pointee.ifa_name)
    if index != 0 { return UInt32(index) }
  }
  return nil
  #endif
}

#if !canImport(WinSDK)
private func hostAddressesMatch(_ lhs: UnsafePointer<sockaddr>, _ rhs: sockaddr_storage) -> Bool {
  withUnsafeBytes(of: rhs) { rhs in
    if Int32(rhs.load(as: sockaddr.self).sa_family) == AF_INET {
      let lhs = UnsafeRawPointer(lhs).load(as: sockaddr_in.self).sin_addr.s_addr
      return lhs == rhs.load(as: sockaddr_in.self).sin_addr.s_addr
    } else {
      var lhs = UnsafeRawPointer(lhs).load(as: sockaddr_in6.self).sin6_addr
      var rhs = rhs.load(as: sockaddr_in6.self).sin6_addr
      return memcmp(&lhs, &rhs, MemoryLayout<in6_addr>.size) == 0
    }
  }
}
#endif

/// `address` copied into a `sockaddr_storage`.
package func makeSockaddrStorage(_ address: any SocketAddress) -> sockaddr_storage {
  var storage = sockaddr_storage()
  address.withSockAddr { sa, size in
    withUnsafeMutableBytes(of: &storage) { dst in
      dst.copyMemory(from: UnsafeRawBufferPointer(
        start: sa,
        count: min(Int(size), MemoryLayout<sockaddr_storage>.size)
      ))
    }
  }
  return storage
}
