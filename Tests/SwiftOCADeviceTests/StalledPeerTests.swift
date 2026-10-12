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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import FlyingSocks
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
import XCTest

private func boundPort(of socket: Socket) throws -> UInt16 {
  switch try socket.sockname() {
  case let .ip4(_, port): return port
  case let .ip6(_, port): return port
  default: throw SocketError.unsupportedAddress
  }
}

private func localhostAddress(port: UInt16) -> Data {
  var addr = sockaddr_in()
  addr.sin_family = sa_family_t(AF_INET)
  addr.sin_port = port.bigEndian
  addr.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
  #if canImport(Darwin)
  addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  #endif
  return withUnsafeBytes(of: addr) { Data($0) }
}

// The platform's native stream backend: io_uring on Linux, FlyingSocks elsewhere.
#if canImport(IORing)
private typealias StreamDeviceEndpoint = OcaIORingStreamDeviceEndpoint

private func startStreamEndpoint(device: OcaDevice) async throws -> (StreamDeviceEndpoint, Task<(), Error>, UInt16) {
  let socket = try Socket(domain: AF_INET, type: .stream)
  try socket.bind(to: .inet(ip4: "127.0.0.1", port: 0))
  let port = try boundPort(of: socket)
  try socket.close()
  let endpoint = try await StreamDeviceEndpoint(address: localhostAddress(port: port), device: device)
  return (endpoint, Task { try await endpoint.run() }, port)
}
#else
private typealias StreamDeviceEndpoint = OcaFlyingSocksStreamDeviceEndpoint

private func startStreamEndpoint(device: OcaDevice) async throws -> (StreamDeviceEndpoint, Task<(), Error>, UInt16) {
  let endpoint = try await StreamDeviceEndpoint(address: localhostAddress(port: 0), device: device)
  let socket = try await endpoint.bind()
  let port = try boundPort(of: socket)
  return (endpoint, Task { try await endpoint.serve(on: socket) }, port)
}
#endif

/// A TCP peer that connects and never reads, as a frozen controller does.
final class StalledPeerTests: XCTestCase {
  private static let emitter: OcaONo = 4243

  func testAPeerThatStopsReadingIsExpiredNotWaitedOn() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (endpoint, endpointTask, port) = try await startStreamEndpoint(device: device)
    defer { endpointTask.cancel() }
    try await Task.sleep(for: .milliseconds(100))

    // a small receive buffer, so the kernel holds little before the device's writes block
    let peer = try Socket(domain: AF_INET, type: .stream)
    defer { try? peer.close() }
    try peer.setValue(4096, for: .receiveBufferSize)
    try peer.connect(to: .inet(ip4: "127.0.0.1", port: port))
    let connected = await waitUntil { await endpoint.controllers.count == 1 }
    XCTAssertTrue(connected, "the peer's controller was not added")
    let controllers = await endpoint.controllers
    let controller = try XCTUnwrap(controllers.first)

    let event = OcaEvent(emitterONo: Self.emitter, eventID: OcaEventID(defLevel: 1, eventIndex: 2))
    let manager = await device.subscriptionManager
    try await XCTUnwrap(manager).addSubscription(.subscription2(OcaSubscription2(
      event: event,
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )), for: controller)

    // each notification carries 64 KiB; the budget is a megabyte past what the kernel takes
    let parameters = Data(count: 1 << 16)
    var longest = Duration.zero
    var sent = 0
    while await endpoint.controllers.isEmpty == false, sent < 1000 {
      let started = ContinuousClock.now
      try await device.notifySubscribers(event, parameters: parameters)
      longest = max(longest, ContinuousClock.now - started)
      sent += 1
    }
    XCTAssertLessThan(longest, .seconds(1), "a notification waited on the stalled peer")
    let expired = await waitUntil { await endpoint.controllers.isEmpty }
    XCTAssertTrue(expired, "the stalled peer was not expired after \(sent) notifications")
    XCTAssertGreaterThan(sent, 8, "the peer was expired before the budget was reached")
  }

  /// With a heartbeat agreed, a peer that stops reading and sending is expired as stale:
  /// the device's own keepalives are queued, so a blocked write cannot keep the check from running.
  func testAPeerWithAHeartbeatThatStopsReadingExpiresAsStale() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (endpoint, endpointTask, port) = try await startStreamEndpoint(device: device)
    defer { endpointTask.cancel() }
    try await Task.sleep(for: .milliseconds(100))

    let peer = try Socket(domain: AF_INET, type: .stream)
    defer { try? peer.close() }
    try peer.setValue(4096, for: .receiveBufferSize)
    try peer.connect(to: .inet(ip4: "127.0.0.1", port: port))
    let keepAlive = try OcaControlProtocol.ocp1.encodePdu([Ocp1KeepAlive1(heartBeatTime: 1)], type: .ocaKeepAlive)
    _ = try peer.write(keepAlive)
    let connected = await waitUntil { await endpoint.controllers.count == 1 }
    XCTAssertTrue(connected, "the peer's controller was not added")
    let controllers = await endpoint.controllers
    let controller = try XCTUnwrap(controllers.first)

    // enough to block the device's writes, well under the budget
    let event = OcaEvent(emitterONo: Self.emitter, eventID: OcaEventID(defLevel: 1, eventIndex: 2))
    let manager = await device.subscriptionManager
    try await XCTUnwrap(manager).addSubscription(.subscription2(OcaSubscription2(
      event: event,
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )), for: controller)
    for _ in 0..<6 {
      try await device.notifySubscribers(event, parameters: Data(count: 1 << 16))
    }
    // three missed heartbeats, not the budget, end it
    let expired = await waitUntil(timeout: .seconds(6)) { await endpoint.controllers.isEmpty }
    XCTAssertTrue(expired, "the stale peer was not expired")
  }
}
