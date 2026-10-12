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

#if (os(macOS) || os(iOS) || os(Linux)) && NonEmbeddedBuild

import FlyingSocks
import Foundation
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - helpers

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
private typealias StreamController = OcaIORingStreamController

/// io_uring endpoints bind only once they run, so reserve a loopback port for them.
private func unusedPort() throws -> UInt16 {
  let socket = try Socket(domain: AF_INET, type: .stream)
  defer { try? socket.close() }
  try socket.bind(to: .inet(ip4: "127.0.0.1", port: 0))
  return try boundPort(of: socket)
}

private func startStreamEndpoint(
  device: OcaDevice
) async throws -> (StreamDeviceEndpoint, Task<(), Error>, UInt16) {
  let port = try unusedPort()
  let endpoint = try await StreamDeviceEndpoint(address: localhostAddress(port: port), device: device)
  return (endpoint, Task { try await endpoint.run() }, port)
}
#else
private typealias StreamDeviceEndpoint = OcaFlyingSocksStreamDeviceEndpoint
private typealias StreamController = OcaFlyingSocksStreamController

private func startStreamEndpoint(
  device: OcaDevice
) async throws -> (StreamDeviceEndpoint, Task<(), Error>, UInt16) {
  let endpoint = try await StreamDeviceEndpoint(address: localhostAddress(port: 0), device: device)
  let socket = try await endpoint.bind()
  let port = try boundPort(of: socket)
  return (endpoint, Task { try await endpoint.serve(on: socket) }, port)
}
#endif

/// A device listening for OCP.1 over TCP.
private struct Fixture {
  let device: OcaDevice
  let endpoint: StreamDeviceEndpoint
  let port: UInt16
  let endpointTask: Task<(), Error>

  init() async throws {
    device = OcaDevice()
    try await device.initializeDefaultObjects()
    (endpoint, endpointTask, port) = try await startStreamEndpoint(device: device)
  }

  /// Connects, retrying while the endpoint has yet to bind (io_uring binds once it runs).
  func connect() async throws -> AsyncSocket {
    let deadline = ContinuousClock.now + .seconds(2)
    while true {
      do {
        return try await AsyncSocket.connected(to: .inet(ip4: "127.0.0.1", port: port))
      } catch where ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(25))
      }
    }
  }

  func controllerCount() async -> Int {
    await endpoint.controllers.count
  }

  func tearDown() {
    endpointTask.cancel()
  }
}

// MARK: - tests

final class TcpKeepAliveTests: XCTestCase {
  func testAcceptedSocketsHaveTcpKeepAlive() async throws {
    let fixture = try await Fixture()
    defer { fixture.tearDown() }

    let client = try await fixture.connect()
    defer { try? client.close() }
    let added = await waitUntil { await fixture.controllerCount() == 1 }
    XCTAssertTrue(added, "controller was not added")
    let controllers = await fixture.endpoint.controllers
    let controller = try XCTUnwrap(controllers.first as? StreamController)

    let options = OcaTcpKeepAlive.socketOptions
    XCTAssertTrue(options.contains { $0.name == CInt(SO_KEEPALIVE) && $0.value == 1 })
    XCTAssertGreaterThan(options.count, 1, "no probe timing was set")
    for option in options {
      let value = try controller.socketOption(level: option.level, name: option.name)
      if option.name == CInt(SO_KEEPALIVE) {
        // BSD reads a boolean option back as its flag bit, Linux as 1
        XCTAssertNotEqual(value, 0, "SO_KEEPALIVE is off")
      } else {
        XCTAssertEqual(value, option.value, "option \(option.name) at level \(option.level)")
      }
    }
  }
}

#endif
