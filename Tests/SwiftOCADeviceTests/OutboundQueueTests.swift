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

import XCTest

@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice

/// A controller's outbound queue is per-connection state. An earlier design kept the
/// equivalent state in a device-side table keyed by `ObjectIdentifier`; because the
/// allocator reuses addresses, a reconnecting peer inherited the previous peer's entry
/// and went silently deaf. These cover the invariant that prevents that class of bug:
/// the queue's lifetime is exactly the controller's, and teardown leaves nothing behind.
final class OutboundQueueTests: XCTestCase {
  private func makeDevice() async throws
    -> (OcaDevice, OcaLocalDeviceEndpoint, Task<(), Never>)
  {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)
    let task = Task { do { try await endpoint.run() } catch {} }
    return (device, endpoint, task)
  }

  /// Sending must create a queue, and teardown must clear it — otherwise state outlives
  /// the connection it belongs to.
  func testTeardownClearsTheOutboundQueue() async throws {
    let (_, endpoint, endpointTask) = try await makeDevice()
    defer { endpointTask.cancel() }

    let connection = await OcaLocalConnection(endpoint)
    try await connection.connect()

    guard let controller = await endpoint.controllers.first as? OcaLocalController else {
      return XCTFail("no controller")
    }

    // a connected controller has already exchanged messages, so it must have a queue
    let hadQueue = await controller.outboundQueue != nil
    XCTAssertTrue(hadQueue, "sending did not create a queue; the test would prove nothing")

    await endpoint.expireForTesting(controller: controller)

    let stillHasQueue = await controller.outboundQueue != nil
    XCTAssertFalse(stillHasQueue, "teardown left an outbound queue on the controller")
  }

  /// Queue state must not be shared between controllers, so a peer reconnecting into a
  /// freshly allocated controller cannot inherit anything from its predecessor.
  func testEachControllerHasItsOwnQueue() async throws {
    let (_, endpoint, endpointTask) = try await makeDevice()
    defer { endpointTask.cancel() }

    let connection = await OcaLocalConnection(endpoint)
    try await connection.connect()

    guard let first = await endpoint.controllers.first as? OcaLocalController else {
      return XCTFail("no controller")
    }
    await endpoint.expireForTesting(controller: first)

    // a fresh controller for the same endpoint must start with no queue at all
    let second = await OcaLocalController(endpoint: endpoint)
    let inherited = await second.outboundQueue != nil
    XCTAssertFalse(inherited, "a new controller inherited queue state from a previous one")
  }
}

private extension OcaLocalDeviceEndpoint {
  func expireForTesting(controller: OcaLocalController) async {
    await unlockAndRemove(controller: controller)
  }
}
