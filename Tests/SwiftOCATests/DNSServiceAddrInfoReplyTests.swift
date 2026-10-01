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

#if canImport(dnssd)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import dnssd
@_spi(SwiftOCAPrivate) @testable import SwiftOCA
import Testing

@Suite
struct DNSServiceAddrInfoReplyTests {
  private func withIPv4<T>(_ address: String, _ body: (UnsafePointer<sockaddr>) -> T) -> T {
    var sin = sockaddr_in()
    sin.sin_family = sa_family_t(AF_INET)
    _ = inet_pton(AF_INET, address, &sin.sin_addr)
    return withUnsafePointer(to: &sin) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0) }
    }
  }

  @Test
  func answersAreCollectedUntilNoMoreAreComing() async {
    let (stream, continuation) = AsyncStream<String>.makeStream()
    let context = Unmanaged.passRetained(_DNSServiceAddrInfoContext(channel: continuation))
    defer { context.release() }
    let add = DNSServiceFlags(kDNSServiceFlagsAdd)
    let moreComing = DNSServiceFlags(kDNSServiceFlagsMoreComing)
    let noError = DNSServiceErrorType(kDNSServiceErr_NoError)

    // one family having no record is not the end: the other may yet answer
    DNSServiceGetAddrInfoBlock_Thunk(nil, 0, 0, DNSServiceErrorType(kDNSServiceErr_NoSuchRecord), nil, nil, 0, context.toOpaque())
    withIPv4("192.0.2.1") {
      DNSServiceGetAddrInfoBlock_Thunk(nil, add | moreComing, 0, noError, nil, $0, 120, context.toOpaque())
    }
    withIPv4("192.0.2.2") {
      DNSServiceGetAddrInfoBlock_Thunk(nil, add, 0, noError, nil, $0, 120, context.toOpaque())
    }

    var addresses = [String]()
    for await address in stream { addresses.append(address) }
    #expect(addresses == ["192.0.2.1", "192.0.2.2"])
  }

  @Test
  func aLiteralOrLocalNameResolvesThroughEitherPath() async {
    let literal = await DNSServiceDiscovery.addresses(of: "127.0.0.1", timeout: .seconds(1))
    #expect(literal == ["127.0.0.1"])
    let localhost = await DNSServiceDiscovery.addresses(of: "localhost", timeout: .seconds(1))
    #expect(!localhost.isEmpty)
  }
}
#endif
