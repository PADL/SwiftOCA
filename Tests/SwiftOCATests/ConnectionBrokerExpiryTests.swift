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

private struct MockServiceInfo: OcaNetworkAdvertisingServiceInfo {
  let name: String
  let txtRecords: [String: String]

  var service: OcaNetworkAdvertisingService { .mDNS_DNSSD }
  var serviceType: OcaNetworkAdvertisingServiceType { .tcp }
  var domain: String { "local." }
  var hostname: String { "mock.local." }
  var port: UInt16 { 65000 }
  var addresses: [Data] {
    get throws {
      try [AnySocketAddress(family: sockaddr_in.family, presentationAddress: "127.0.0.1").data]
    }
  }

  func resolve() async throws {}
}

private actor EventCollector {
  var events = [OcaConnectionBroker.Event]()

  func append(_ event: OcaConnectionBroker.Event) { events.append(event) }

  func removals(of deviceIdentifier: OcaConnectionBroker.DeviceIdentifier) -> Int {
    events.filter { $0.eventType == .deviceRemoved && $0.deviceIdentifier == deviceIdentifier }
      .count
  }
}

private final class MockConnection: Ocp1Connection {
  override nonisolated var connectionPrefix: String { "oca/mock" }
}

@OcaConnection
private func setConnectionState(_ connection: Ocp1Connection, _ state: Ocp1ConnectionState) {
  connection._connectionState.send(state)
}

/// A DNS-SD browse removal is a hint, not a fact: a device that re-registers
/// under another instance name (as the Monitor Two does) sends a goodbye for
/// the old name while its OCP.1 connection stays up. The broker must only
/// expire a device once it has stayed unadvertised with no live connection.
@Suite
struct ConnectionBrokerExpiryTests {
  static let modelGUID = try! OcaModelGUID("0AE91B02010100")

  fileprivate static func mockInfo(name: String) -> MockServiceInfo {
    MockServiceInfo(name: name, txtRecords: [
      "txtvers": "1",
      "protovers": "4",
      "modelGUID": "0AE91B02010100",
      "serialNumber": "TEST01",
    ])
  }

  fileprivate static func makeBroker() async -> (OcaConnectionBroker, EventCollector, Task<(), Never>) {
    let broker = await OcaConnectionBroker(
      serviceTypes: [],
      deviceExpiryTimeout: .milliseconds(100)
    )
    let collector = EventCollector()
    let pump = Task {
      for await event in await broker.events {
        await collector.append(event)
      }
    }
    return (broker, collector, pump)
  }

  @Test
  func browseRemovalSparesALiveConnection() async throws {
    let (broker, collector, pump) = await Self.makeBroker()
    defer { pump.cancel() }
    let info = Self.mockInfo(name: "MockDevice")
    let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(
      serviceType: .tcp,
      modelGUID: Self.modelGUID,
      serialNumber: "TEST01",
      name: "MockDevice"
    )

    try await broker._onBrowseResult(.added(info))
    let connection = await MockConnection()
    await setConnectionState(connection, .connected)
    await broker.register(device: deviceIdentifier, connection: connection)

    try await broker._onBrowseResult(.removed(info))
    try await Task.sleep(for: .milliseconds(400))
    #expect(await collector.removals(of: deviceIdentifier) == 0)

    // once the connection actually dies, the pending expiry may remove it
    await setConnectionState(connection, .notConnected)
    try await Task.sleep(for: .milliseconds(400))
    #expect(await collector.removals(of: deviceIdentifier) == 1)
  }

  @Test
  func reregistrationUnderANewNameKeepsTheDevice() async throws {
    let (broker, collector, pump) = await Self.makeBroker()
    defer { pump.cancel() }
    let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(
      serviceType: .tcp,
      modelGUID: Self.modelGUID,
      serialNumber: "TEST01",
      name: "MockDevice"
    )

    try await broker._onBrowseResult(.added(Self.mockInfo(name: "MockDevice")))
    try await broker._onBrowseResult(.removed(Self.mockInfo(name: "MockDevice")))
    try await broker._onBrowseResult(.added(Self.mockInfo(name: "MockDevice-Dante")))
    try await Task.sleep(for: .milliseconds(400))

    #expect(await collector.removals(of: deviceIdentifier) == 0)
    #expect(await broker.registeredDevices == [deviceIdentifier])
  }
}

#endif
