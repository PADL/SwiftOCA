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

final class MediaClock3CurrentRateTests: XCTestCase {
  func testSetCurrentRateKeepsTheTimeSource() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device, controlProtocol: .ocp1)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(endpoint)
    try await connection.connect()
    defer {
      Task {
        try? await connection.disconnect()
        endpointTask.cancel()
      }
    }

    let timeSource = try await SwiftOCADevice.OcaTimeSource(
      objectNumber: 0x0001_0600,
      role: "Time Source",
      deviceDelegate: device,
      addToRootBlock: true
    )
    let deviceClock = try await SwiftOCADevice.OcaMediaClock3(
      objectNumber: 0x0001_0601,
      role: "Media Clock",
      deviceDelegate: device,
      addToRootBlock: true
    )
    try await deviceClock.set(
      currentRate: OcaMediaClockRate(nominalRate: 48000),
      timeSource: timeSource
    )

    let clock: SwiftOCA.OcaMediaClock3 = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: 0x0001_0601,
        classIdentification: SwiftOCA.OcaMediaClock3.classIdentification
      )
    )
    try await clock.setCurrentRate(rate: OcaMediaClockRate(nominalRate: 96000))

    let current = try await clock.getCurrentRate()
    XCTAssertEqual(current.rate.nominalRate, 96000)
    XCTAssertEqual(current.timeSourceONo, 0x0001_0600)
  }
}
#endif
