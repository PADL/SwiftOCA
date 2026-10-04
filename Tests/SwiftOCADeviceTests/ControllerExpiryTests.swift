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
@testable import SwiftOCADevice
@_spi(SwiftOCAPrivate) import SwiftOCA
import Synchronization
import XCTest

/// A controller of an endpoint that is not one of this package's, so nothing but the
/// device's public API tells the device that it has gone.
private actor ForeignController: OcaController {
  nonisolated let flags: OcaControllerFlags = [.supportsLocking]

  func sendMessages(_ messages: [Ocp1Message], type messageType: OcaMessageType) async throws {}
}

private final class ExpiryDelegate: OcaDeviceEventDelegate {
  private let expired = Mutex([ObjectIdentifier]())

  func onEvent(_ event: OcaEvent, parameters: OcaEventParameters) async {}

  func onControllerExpiry(_ controller: OcaController) async {
    expired.withLock { $0.append(ObjectIdentifier(controller)) }
  }

  func hasExpired(_ controller: OcaController) -> Bool {
    expired.withLock { $0.contains(ObjectIdentifier(controller)) }
  }
}

final class ControllerExpiryTests: XCTestCase {
  /// The delegate and the dataset sessions are dealt with without the caller waiting.
  private func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<200 {
      if await condition() { return true }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return false
  }

  func testExpiringAControllerReleasesWhatTheDeviceHoldsForIt() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let delegate = ExpiryDelegate()
    await device.setEventDelegate(delegate)

    let object = try await SwiftOCADevice.OcaWorker(
      objectNumber: 10000, role: "Locked", deviceDelegate: device
    )
    let dataset = try await SwiftOCADevice.OcaDataset(
      owner: 10000, name: "Held", type: "application/octet-stream", objectNumber: 10001,
      deviceDelegate: device, addToRootBlock: true
    )
    let leaving = ForeignController()
    let staying = ForeignController()

    try await object.setLockNoReadWrite(from: leaving)
    let handle = try await dataset.allocateIOSessionHandle(with: "session", controller: leaving)
    let kept = try await dataset.allocateIOSessionHandle(with: "session", controller: staying)
    let lockedOut = await object.isReadLocked(by: staying)
    XCTAssertTrue(lockedOut)

    await device.expire(controller: leaving)

    let stillLockedOut = await object.isReadLocked(by: staying)
    XCTAssertFalse(stillLockedOut, "the expired controller's lock was not released")
    let told = await eventually { delegate.hasExpired(leaving) }
    XCTAssertTrue(told, "the event delegate was not told of the expiry")
    let closed = await eventually {
      await (try? dataset.resolveIOSessionHandle(handle, controller: leaving) as String) == nil
    }
    XCTAssertTrue(closed, "the expired controller's dataset session is still open")

    XCTAssertFalse(delegate.hasExpired(staying))
    let other: String = try await dataset.resolveIOSessionHandle(kept, controller: staying)
    XCTAssertEqual(other, "session")
  }
}
