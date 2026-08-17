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

@testable import SocketAddress
@testable import SwiftOCA
import Testing

/// On a NAT64 network, resolving with a full lookup lets the system rewrite
/// IPv4 literals to the NAT64 prefix, which cannot reach private device
/// addresses — a literal must come back exactly as given.
@Suite
struct HostnameResolutionTests {
  @Test
  func anIPv4LiteralResolvesToItself() async throws {
    let addresses = await _resolveDeviceAddresses(host: "172.16.85.133", port: 65000, isDatagram: false)
    #expect(addresses.map(\._presentationAddress) == ["172.16.85.133:65000"])
  }

  @Test
  func anIPv6LiteralResolvesToItself() async throws {
    let addresses = await _resolveDeviceAddresses(host: "::1", port: 65000, isDatagram: false)
    #expect(addresses.map(\._presentationAddress) == ["[::1]:65000"])
  }

  @Test
  func aHostnameStillResolves() async throws {
    let addresses = await _resolveDeviceAddresses(host: "localhost", port: 65000, isDatagram: true)
    #expect(!addresses.isEmpty)
  }

  @Test
  func anUnresolvableNameResolvesToNothing() async throws {
    let addresses = await _resolveDeviceAddresses(host: "device.invalid", port: 65000, isDatagram: false)
    #expect(addresses.isEmpty)
  }
}
