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
#endif
import SocketAddress
@testable import SwiftOCADevice
import XCTest

/// Where an endpoint's DNS-SD services are announced, from the address it is bound to.
final class BonjourAdvertisingInterfaceTests: XCTestCase {
  private func storage(_ presentationAddress: String) -> OcaBonjourListenAddress {
    if presentationAddress.contains(":") {
      try! sockaddr_in6(family: sa_family_t(AF_INET6), presentationAddress: presentationAddress)
    } else {
      try! sockaddr_in(family: sa_family_t(AF_INET), presentationAddress: "\(presentationAddress):65000")
    }
  }

  private func unixStorage() -> OcaBonjourListenAddress {
    try! sockaddr_un(family: sa_family_t(AF_LOCAL), presentationAddress: "/var/run/inferno.socket")
  }

  func testWildcardAddressesAreEveryInterface() {
    XCTAssertEqual(OcaBonjourListenAddressClass(storage("0.0.0.0")), .wildcard)
    XCTAssertEqual(OcaBonjourListenAddressClass(storage("::")), .wildcard)
    XCTAssertEqual(OcaBonjourListenAddressClass(storage("::ffff:0.0.0.0")), .wildcard)
    XCTAssertEqual(bonjourInterfaceIndex(for: storage("0.0.0.0"), lookup: { _ in 7 }), 0)
    XCTAssertEqual(bonjourInterfaceIndex(for: storage("::"), lookup: { _ in 7 }), 0)
  }

  func testSpecificAddressesAreTheirInterface() {
    XCTAssertEqual(OcaBonjourListenAddressClass(storage("10.10.32.8")), .specific)
    XCTAssertEqual(OcaBonjourListenAddressClass(storage("fe80::1")), .specific)
    XCTAssertEqual(OcaBonjourListenAddressClass(storage("2001:db8::8")), .specific)
    XCTAssertEqual(OcaBonjourListenAddressClass(storage("::ffff:10.10.32.8")), .specific)
    XCTAssertEqual(bonjourInterfaceIndex(for: storage("10.10.32.8"), lookup: { _ in 7 }), 7)
    XCTAssertEqual(bonjourInterfaceIndex(for: storage("2001:db8::8"), lookup: { _ in 3 }), 3)
  }

  func testAnAddressNoInterfaceHoldsIsEveryInterface() {
    var unheld: String?
    let index = bonjourInterfaceIndex(
      for: storage("10.10.32.8"),
      lookup: { _ in nil },
      onNoInterface: { unheld = $0._presentationAddress }
    )
    XCTAssertEqual(index, 0)
    XCTAssertNotNil(unheld)
  }

  func testLoopbackAddressesAreNotAdvertised() {
    XCTAssertEqual(OcaBonjourListenAddressClass(storage("127.0.0.1")), .unreachable)
    XCTAssertEqual(OcaBonjourListenAddressClass(storage("127.1.2.3")), .unreachable)
    XCTAssertEqual(OcaBonjourListenAddressClass(storage("::1")), .unreachable)
    XCTAssertEqual(OcaBonjourListenAddressClass(storage("::ffff:127.0.0.1")), .unreachable)
    XCTAssertNil(bonjourInterfaceIndex(for: storage("127.0.0.1"), lookup: { _ in 1 }))
    XCTAssertNil(bonjourInterfaceIndex(for: storage("::1"), lookup: { _ in 1 }))
  }

  func testDomainSocketsAreNotAdvertised() {
    XCTAssertEqual(OcaBonjourListenAddressClass(unixStorage()), .unreachable)
    XCTAssertNil(bonjourInterfaceIndex(for: unixStorage(), lookup: { _ in 1 }))
  }

  func testTheLoopbackInterfaceHoldsTheLoopbackAddress() {
    // every host has one; no other network is needed
    let index = interfaceIndex(holding: storage("127.0.0.1"))
    XCTAssertNotNil(index)
    XCTAssertNotEqual(index, 0)
    XCTAssertNil(interfaceIndex(holding: storage("192.0.2.254")))
    XCTAssertNil(interfaceIndex(holding: unixStorage()))
  }
}
