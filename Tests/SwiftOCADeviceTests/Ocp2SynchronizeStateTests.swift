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

#if NonEmbeddedBuild
import Foundation
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

/// `OcaSubscriptionManager` emits SynchronizeState when notifications are re-enabled;
/// like any other event it must reach a controller whatever protocol it speaks.
final class Ocp2SynchronizeStateTests: XCTestCase {
  /// Every payload delivered for the subscribed emitter. A subscriber to one of an
  /// object's events is currently sent all of them, so the object list is picked out
  /// by decoding rather than by assuming it arrived alone.
  private final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var _payloads = [Data]()

    var payloads: [Data] {
      lock.withLock { _payloads }
    }

    func store(_ data: Data) {
      lock.withLock { _payloads.append(data) }
    }
  }

  func testSynchronizeStateReachesAnOcp2Controller() async throws {
    try await assertSynchronizeStateIsDelivered(over: .ocp2)
  }

  /// The same path on OCP.1, so a failure above is about the protocol and not the manager.
  func testSynchronizeStateReachesAnOcp1Controller() async throws {
    try await assertSynchronizeStateIsDelivered(over: .ocp1)
  }

  private func assertSynchronizeStateIsDelivered(
    over controlProtocol: OcaControlProtocol,
    line: UInt = #line
  ) async throws {
    let harness = try await makeHarness(controlProtocol: controlProtocol)
    defer { Task { await harness.tearDown() } }

    let block = try await SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>(
      objectNumber: 0x0001_0500,
      role: "Changed",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )

    let received = Received()
    let subscriptionManager = await harness.connection.subscriptionManager
    let event = OcaEvent(
      emitterONo: subscriptionManager.objectNumber,
      eventID: SwiftOCA.OcaSubscriptionManager.SynchronizeStateEventID
    )
    _ = try await harness.connection.addSubscription(event: event) { _, data in
      received.store(data)
    }

    try await subscriptionManager.disableNotifications()
    // a change made while notifications are off is what SynchronizeState reports
    await { @OcaDevice in block.label = "changed" }()
    try await subscriptionManager.reenableNotifications()

    let format = controlProtocol.parameterFormat
    let changedONo = block.objectNumber
    let delivered = await wait {
      received.payloads.contains { payload in
        guard let objectList = try? OcaEventDataCoding.decode(
          OcaObjectListEventData.self,
          from: payload,
          format: format
        ) else { return false }
        return objectList.objectList.contains(changedONo)
      }
    }
    XCTAssertTrue(
      delivered,
      "\(controlProtocol) controller did not receive SynchronizeState listing the changed object",
      line: line
    )

    // the manager emits other events of its own while notifications are toggled; a
    // subscription to one event must not be sent them
    for payload in received.payloads {
      XCTAssertNoThrow(
        try OcaEventDataCoding.decode(
          OcaObjectListEventData.self,
          from: payload,
          format: format
        ),
        "a subscription to SynchronizeState received another event's data",
        line: line
      )
    }
  }

  private struct Harness {
    let device: OcaDevice
    let endpoint: OcaLocalDeviceEndpoint
    let connection: OcaLocalConnection
    let endpointTask: Task<(), Never>

    func tearDown() async {
      try? await connection.disconnect()
      endpointTask.cancel()
    }
  }

  private func makeHarness(controlProtocol: OcaControlProtocol) async throws -> Harness {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(
      device: device,
      controlProtocol: controlProtocol
    )
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(
      endpoint,
      options: Ocp1ConnectionOptions(controlProtocol: controlProtocol)
    )
    try await connection.connect()
    return Harness(
      device: device,
      endpoint: endpoint,
      connection: connection,
      endpointTask: endpointTask
    )
  }

  private func wait(
    timeout: Duration = .seconds(5),
    until condition: @Sendable () async -> Bool
  ) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if await condition() { return true }
      try? await Task.sleep(for: .milliseconds(25))
    }
    return await condition()
  }
}
#endif
