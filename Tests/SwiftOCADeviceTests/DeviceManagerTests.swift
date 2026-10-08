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

  /// Managers constructed before the device manager (subscription, security) are listed
  /// too, by role, then the class manager, and later managers come and go with registration.
  func testManagersListsEveryRegisteredManager() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let deviceManager = await device.deviceManager!

    var managers = await deviceManager.managers
    let classManager = OcaClassManagerONo
    XCTAssertEqual(managers.map(\.objectNumber), [OcaSecurityManagerONo, OcaSubscriptionManagerONo, classManager])
    XCTAssertEqual(managers.map(\.name), ["SecurityManager", "SubscriptionManager", "ClassManager"])

    let firmwareManager = try await SwiftOCADevice.OcaFirmwareManager(deviceDelegate: device)
    managers = await deviceManager.managers
    XCTAssertEqual(managers.map(\.objectNumber), [
      OcaSecurityManagerONo,
      OcaSubscriptionManagerONo,
      classManager,
      OcaFirmwareManagerONo,
    ])

    // the device's managers are the device manager and those it lists
    let objects = await device.managers.map(\.objectNumber)
    XCTAssertEqual(objects, [OcaDeviceManagerONo] + managers.map(\.objectNumber))

    try await device.deregister(object: firmwareManager)
    managers = await deviceManager.managers
    XCTAssertFalse(managers.contains(where: { $0.objectNumber == OcaFirmwareManagerONo }))
  }
}
