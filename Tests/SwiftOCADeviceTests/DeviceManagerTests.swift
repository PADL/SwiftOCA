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

final class DeviceManagerTests: XCTestCase {
  @OcaDevice
  func testClearResetCauseRestoresPowerOn() async throws {
    let harness = try await CM4TestHarness.make()
    defer { harness.endpointTask.cancel() }

    let deviceManager = await harness.device.deviceManager!
    deviceManager.resetCause = .externalRequest

    try await harness.connection.deviceManager.clearResetCause()
    XCTAssertEqual(deviceManager.resetCause, .powerOn)
  }

  /// AES70-4 requires NotImplemented of SetResetKey on a device without the reset
  /// mechanism, which is what the base OcaDeviceManager is.
  @OcaDevice
  func testSetResetKeyAnswersNotImplementedWithoutAResetMechanism() async throws {
    let harness = try await CM4TestHarness.make()
    defer { harness.endpointTask.cancel() }

    let key: SwiftOCA.OcaDeviceManager.ResetKey = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    await XCTAssertThrowsStatus(.notImplemented) {
      try await harness.connection.deviceManager
        .setResetKey(key: key, address: OcaNetworkAddress())
    }
  }
}
