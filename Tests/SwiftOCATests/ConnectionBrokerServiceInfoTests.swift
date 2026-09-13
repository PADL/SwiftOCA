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
import Foundation
import SocketAddress
@testable import SwiftOCA
import Testing

private func socketAddress(_ family: sa_family_t, _ address: String) throws -> Data {
  try AnySocketAddress(family: family, presentationAddress: address).data
}

private struct MockWebSocketServiceInfo: OcaNetworkAdvertisingServiceInfo {
  let name: String

  var service: OcaNetworkAdvertisingService { .mDNS_DNSSD }
  var serviceType: OcaNetworkAdvertisingServiceType { .tcpWebSocket }
  var domain: String { "local." }
  var hostname: String { "mock.local." }
  var port: UInt16 { 8080 }
  var addresses: [Data] {
    get throws {
      // deliberately out of preference order
      try [
        socketAddress(sockaddr_in6.family, "::1"),
        socketAddress(sockaddr_in.family, "127.0.0.2"),
        socketAddress(sockaddr_in.family, "127.0.0.1"),
      ]
    }
  }

  var txtRecords: [String: String] {
    [
      "txtvers": "1",
      "protovers": "4",
      "modelGUID": "0AE91B02010100",
      "serialNumber": "TEST02",
      "path": "/ocp1",
    ]
  }

  func resolve() async throws {}
}

private actor RemovalCollector {
  var removed = [OcaConnectionBroker.DeviceIdentifier]()

  func append(_ event: OcaConnectionBroker.Event) {
    if event.eventType == .deviceRemoved { removed.append(event.deviceIdentifier) }
  }
}

/// A caller that uses the broker only to browse can read a discovered device's
/// resolved endpoint and connect to it by itself.
@Suite
struct ConnectionBrokerServiceInfoTests {
  static let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(
    serviceType: .tcpWebSocket,
    modelGUID: try! OcaModelGUID("0AE91B02010100"),
    serialNumber: "TEST02",
    name: "MockDevice"
  )

  static func makeBroker() async -> OcaConnectionBroker {
    await OcaConnectionBroker(serviceTypes: [], deviceExpiryTimeout: .milliseconds(100))
  }

  @Test
  func discoveredDeviceHasItsServiceInfo() async throws {
    let broker = await Self.makeBroker()
    try await broker._onBrowseResult(.added(MockWebSocketServiceInfo(name: "MockDevice")))

    let serviceInfo = try await broker.serviceInfo(for: Self.deviceIdentifier)
    #expect(serviceInfo.name == "MockDevice")
    #expect(serviceInfo.serviceType == .tcpWebSocket)
    #expect(try serviceInfo.hostname == "mock.local.")
    #expect(try serviceInfo.port == 8080)
    #expect(try serviceInfo.txtRecords["path"] == "/ocp1")

    #expect(try await broker.deviceAddresses(for: Self.deviceIdentifier) == [
      socketAddress(sockaddr_in.family, "127.0.0.1"),
      socketAddress(sockaddr_in.family, "127.0.0.2"),
      socketAddress(sockaddr_in6.family, "::1"),
    ])
  }

  @Test
  func unknownDeviceThrows() async throws {
    let broker = await Self.makeBroker()

    await #expect(throws: Ocp1Error.endpointNotRegistered) {
      try await broker.serviceInfo(for: Self.deviceIdentifier)
    }
    await #expect(throws: Ocp1Error.endpointNotRegistered) {
      try await broker.deviceAddresses(for: Self.deviceIdentifier)
    }
  }

  @Test
  func removedDeviceThrowsAfterExpiry() async throws {
    let broker = await Self.makeBroker()
    let collector = RemovalCollector()
    let pump = Task {
      for await event in await broker.events {
        await collector.append(event)
      }
    }
    defer { pump.cancel() }

    let info = MockWebSocketServiceInfo(name: "MockDevice")
    try await broker._onBrowseResult(.added(info))
    _ = try await broker.serviceInfo(for: Self.deviceIdentifier)

    try await broker._onBrowseResult(.removed(info))
    try await Task.sleep(for: .milliseconds(400))
    #expect(await collector.removed == [Self.deviceIdentifier])

    await #expect(throws: Ocp1Error.endpointNotRegistered) {
      try await broker.serviceInfo(for: Self.deviceIdentifier)
    }
    await #expect(throws: Ocp1Error.endpointNotRegistered) {
      try await broker.deviceAddresses(for: Self.deviceIdentifier)
    }
  }
}

#endif
