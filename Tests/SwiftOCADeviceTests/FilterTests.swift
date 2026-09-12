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

/// OcaFilterArbitraryCurve over the local transport. AES70-2 returns the curve from
/// GetTransferFunction (4.1) as one structure, but SetTransferFunction (4.2) takes
/// its three lists as separate parameters.
final class FilterArbitraryCurveTests: XCTestCase {
  private static let filterONo: OcaONo = 0x0001_0400

  private static let curve = OcaTransferFunction(
    frequency: [100.0, 1000.0, 10000.0],
    amplitude: [-3.0, 0.0, -6.0],
    phase: [0.0, 0.5, 1.0]
  )

  private struct Harness {
    let connection: OcaLocalConnection
    let endpointTask: Task<(), Never>
    let deviceFilter: SwiftOCADevice.OcaFilterArbitraryCurve
    let filter: SwiftOCA.OcaFilterArbitraryCurve

    func tearDown() async {
      try? await connection.disconnect()
      endpointTask.cancel()
    }
  }

  private func makeHarness() async throws -> Harness {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let deviceFilter = try await SwiftOCADevice.OcaFilterArbitraryCurve(
      objectNumber: Self.filterONo,
      role: "Arbitrary Curve",
      deviceDelegate: device,
      addToRootBlock: true
    )
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(endpoint)
    try await connection.connect()
    let filter: SwiftOCA.OcaFilterArbitraryCurve = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: Self.filterONo,
        classIdentification: SwiftOCA.OcaFilterArbitraryCurve.classIdentification
      )
    )
    return Harness(
      connection: connection,
      endpointTask: endpointTask,
      deviceFilter: deviceFilter,
      filter: filter
    )
  }

  func testSetTransferFunctionSendsEachListSeparately() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    try await h.filter.$transferFunction._setValue(h.filter, Self.curve)

    let stored = await { @OcaDevice in h.deviceFilter.transferFunction }()
    XCTAssertEqual(stored.frequency, Self.curve.frequency)
    XCTAssertEqual(stored.amplitude, Self.curve.amplitude)
    XCTAssertEqual(stored.phase, Self.curve.phase)
  }

  func testGetTransferFunctionReturnsOneStructure() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    await { @OcaDevice in h.deviceFilter.transferFunction = Self.curve }()
    let value = try await h.filter.$transferFunction._getValue(h.filter, flags: [])
    XCTAssertEqual(value, Self.curve)
  }
}
