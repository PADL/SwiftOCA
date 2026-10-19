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

// io_uring's stream reads have no idle timeout; FlyingSocks' do.
#if !canImport(IORing)

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

/// A controller's reads time out after the endpoint's timeout only until it agrees a
/// heartbeat; from then, three missed heartbeats expire it.
final class StreamIdleTimeoutTests: XCTestCase {
  private static let timeout = Duration.seconds(1)

  private func startEndpoint() async throws -> (
    OcaFlyingSocksStreamDeviceEndpoint,
    Task<(), Error>,
    UInt16
  ) {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaFlyingSocksStreamDeviceEndpoint(
      address: localhostAddress(port: 0),
      timeout: Self.timeout,
      device: device
    )
    let socket = try await endpoint.bind()
    let port = try boundPort(of: socket)
    return (endpoint, Task { try await endpoint.serve(on: socket) }, port)
  }

  /// A peer whose writes throw, rather than raise SIGPIPE, once the device has dropped it.
  private func connectPeer(to port: UInt16) throws -> Socket {
    let peer = try Socket(domain: AF_INET, type: .stream)
    #if canImport(Darwin)
    try peer.setValue(true, for: .noSIGPIPE)
    #endif
    try peer.connect(to: .inet(ip4: "127.0.0.1", port: port))
    return peer
  }

  /// A controller whose heartbeat is the read timeout, and whose keepalives arrive a little
  /// late, as a timer's do, is kept.
  func testLateKeepAlivesWithinThreeHeartbeatsKeepTheController() async throws {
    let (endpoint, endpointTask, port) = try await startEndpoint()
    defer { endpointTask.cancel() }

    let peer = try connectPeer(to: port)
    defer { try? peer.close() }
    let keepAlive = try OcaControlProtocol.ocp1.encodePdu(
      [Ocp1KeepAlive1(heartBeatTime: OcaUint16(Self.timeout.components.seconds))],
      type: .ocaKeepAlive
    )
    _ = try peer.write(keepAlive)
    let connected = await waitUntil { await endpoint.controllers.count == 1 }
    XCTAssertTrue(connected, "the peer's controller was not added")

    for _ in 0..<4 {
      try await Task.sleep(for: Self.timeout * 1.5)
      guard (try? peer.write(keepAlive)) != nil else { break }
    }
    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 1, "a controller keeping its heartbeat was dropped")
  }

  /// A controller that never agrees a heartbeat and goes silent is still dropped.
  func testASilentControllerWithoutAHeartbeatTimesOut() async throws {
    let (endpoint, endpointTask, port) = try await startEndpoint()
    defer { endpointTask.cancel() }

    let peer = try connectPeer(to: port)
    defer { try? peer.close() }
    let connected = await waitUntil { await endpoint.controllers.count == 1 }
    XCTAssertTrue(connected, "the peer's controller was not added")

    let removed = await waitUntil(timeout: Self.timeout * 3) { await endpoint.controllers.isEmpty }
    XCTAssertTrue(removed, "a silent controller without a heartbeat was kept")
  }
}

#endif
