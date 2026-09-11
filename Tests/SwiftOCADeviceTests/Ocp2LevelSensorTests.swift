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

/// `OcaLevelSensor` encodes its own property-changed events to keep metering off the
/// `Codable` path; the notification must still reach a controller speaking OCP.2.
final class Ocp2LevelSensorTests: XCTestCase {
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

  func testLevelSensorNotifiesAnOcp2Controller() async throws {
    let harness = try await makeHarness(controlProtocol: .ocp2)
    defer { Task { await harness.tearDown() } }

    let sensorONo: OcaONo = 0x0001_0400
    let sensor = try await SwiftOCADevice.OcaLevelSensor(
      objectNumber: sensorONo,
      role: "Meter",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    let client: SwiftOCA.OcaLevelSensor = try await harness.connection.resolve(
      object: OcaObjectIdentification(
        oNo: sensorONo,
        classIdentification: SwiftOCA.OcaLevelSensor.classIdentification
      )
    )

    await client.$reading.subscribe(client)
    let subscribed = await wait { (try? await client.isSubscribed) == true }
    XCTAssertTrue(subscribed)

    try await sensor.update(reading: -12.0)

    let observed = await wait {
      if case let .success(value) = client.$reading.currentValue { return value.value == -12.0 }
      return false
    }
    XCTAssertTrue(observed, "OCP.2 controller did not observe the level sensor reading")
  }

  /// The same path on OCP.1, so a failure above is about the protocol and not the sensor.
  func testLevelSensorNotifiesAnOcp1Controller() async throws {
    let harness = try await makeHarness(controlProtocol: .ocp1)
    defer { Task { await harness.tearDown() } }

    let sensorONo: OcaONo = 0x0001_0401
    let sensor = try await SwiftOCADevice.OcaLevelSensor(
      objectNumber: sensorONo,
      role: "Meter",
      deviceDelegate: harness.device,
      addToRootBlock: true
    )
    let client: SwiftOCA.OcaLevelSensor = try await harness.connection.resolve(
      object: OcaObjectIdentification(
        oNo: sensorONo,
        classIdentification: SwiftOCA.OcaLevelSensor.classIdentification
      )
    )

    await client.$reading.subscribe(client)
    let subscribed = await wait { (try? await client.isSubscribed) == true }
    XCTAssertTrue(subscribed)

    try await sensor.update(reading: -12.0)

    let observed = await wait {
      if case let .success(value) = client.$reading.currentValue { return value.value == -12.0 }
      return false
    }
    XCTAssertTrue(observed, "OCP.1 controller did not observe the level sensor reading")
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
