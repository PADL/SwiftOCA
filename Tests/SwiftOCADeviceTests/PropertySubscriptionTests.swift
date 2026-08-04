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

@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

private final class Flag: @unchecked Sendable {
  private var value = false
  private let lock = NSLock()
  var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
  func set() { lock.lock(); value = true; lock.unlock() }
}

final class PropertySubscriptionTests: XCTestCase {
  private struct Harness {
    let device: OcaDevice
    let connection: OcaLocalConnection
    let endpointTask: Task<(), Never>
  }

  private func makeHarness() async throws -> Harness {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(endpoint)
    try await connection.connect()
    return Harness(device: device, connection: connection, endpointTask: endpointTask)
  }

  /// Waits for the property subject to observe `expected`.
  private func awaitLabel(
    _ property: OcaProperty<OcaString>,
    expected: String,
    timeout: Duration = .seconds(5)
  ) async -> Bool {
    let seen = Flag()
    let consumer = Task {
      for try await result in property.async {
        if case let .success(value) = result, value as? OcaString == expected {
          seen.set()
          return
        }
      }
    }
    defer { consumer.cancel() }

    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if seen.isSet { return true }
      try? await Task.sleep(for: .milliseconds(25))
    }
    return seen.isSet
  }

  /// Waits until the object registers its own property-changed handler.
  private func awaitObjectSubscription(
    _ object: SwiftOCA.OcaRoot,
    timeout: Duration = .seconds(5)
  ) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if (try? await object.isSubscribed) == true { return true }
      try? await Task.sleep(for: .milliseconds(25))
    }
    return (try? await object.isSubscribed) == true
  }

  private func makeBlockPair(
    _ harness: Harness,
    objectNumber: OcaONo,
    role: String
  ) async throws -> (SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>, SwiftOCA.OcaBlock) {
    let deviceBlock = try await SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>(
      objectNumber: objectNumber,
      role: role,
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    let clientBlock: SwiftOCA.OcaBlock = try await harness.connection.resolve(
      object: OcaObjectIdentification(
        oNo: objectNumber,
        classIdentification: SwiftOCA.OcaBlock.classIdentification
      )
    )
    return (deviceBlock, clientBlock)
  }

  /// Baseline: nothing else subscribed.
  func testPropertyObservesChangesWithNoPriorSubscription() async throws {
    let harness = try await makeHarness()
    defer { harness.endpointTask.cancel() }

    let (deviceBlock, clientBlock) = try await makeBlockPair(
      harness,
      objectNumber: 0x0001_0001,
      role: "Control"
    )

    await clientBlock.$label.subscribe(clientBlock)
    let registered = await awaitObjectSubscription(clientBlock)
    XCTAssertTrue(registered)

    await { @OcaDevice in deviceBlock.label = "changed" }()
    let observed = await awaitLabel(clientBlock.$label, expected: "changed")
    XCTAssertTrue(observed, "property did not observe the device change")

    try await harness.connection.disconnect()
  }

  /// Regression: another component's subscription to the same event must not
  /// stop this object registering its own handler. `_getValue()` skips
  /// `subscribe()` when `isSubscribed`, which once meant "the connection has
  /// any subscription for this event".
  func testPropertyObservesChangesWhenAnotherComponentAlreadySubscribed() async throws {
    let harness = try await makeHarness()
    defer { harness.endpointTask.cancel() }

    let objectNumber: OcaONo = 0x0001_0002
    let (deviceBlock, clientBlock) = try await makeBlockPair(
      harness,
      objectNumber: objectNumber,
      role: "Shared"
    )

    // e.g. AES70Orchestrator's OcaObjectBinding following a bound object
    let foreignFired = Flag()
    _ = try await harness.connection.addSubscription(
      label: "foreign-subscriber",
      event: OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
    ) { _, _ in foreignFired.set() }

    await clientBlock.$label.subscribe(clientBlock)
    let registered = await awaitObjectSubscription(clientBlock)
    XCTAssertTrue(
      registered,
      "object did not register its own handler while a foreign subscription existed"
    )

    await { @OcaDevice in deviceBlock.label = "changed" }()

    let observed = await awaitLabel(clientBlock.$label, expected: "changed")
    XCTAssertTrue(
      observed,
      "property did not observe the device change while a foreign subscription existed"
    )
    XCTAssertTrue(foreignFired.isSet, "foreign subscriber should still be notified")

    try await harness.connection.disconnect()
  }
}
