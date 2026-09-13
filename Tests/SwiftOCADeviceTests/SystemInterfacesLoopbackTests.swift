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

/// OcaApplicationNetwork.SystemInterfaces, a list of OcaBlob typedefs, read from a
/// device over OCP.1 and OCP.2.
final class SystemInterfacesLoopbackTests: XCTestCase {
  private let networkONo: OcaONo = 0x0001_0300

  func testSystemInterfacesOverOcp1() async throws {
    try await roundTrip(controlProtocol: .ocp1)
  }

  func testSystemInterfacesOverOcp2() async throws {
    try await roundTrip(controlProtocol: .ocp2)
  }

  private func roundTrip(controlProtocol: OcaControlProtocol) async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(
      device: device,
      controlProtocol: controlProtocol
    )
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(
      endpoint,
      options: OcaConnectionOptions(controlProtocol: controlProtocol)
    )
    defer {
      Task {
        try? await connection.disconnect()
        endpointTask.cancel()
      }
    }
    try await connection.connect()

    let descriptor = try Ocp1NetworkSystemInterfaceDescriptor(
      systemInterfaceParameters: OcaBlob(Data([0xAA, 0xBB])),
      myNetworkAddress: Ocp1NetworkAddress(address: "10.0.0.1", port: 65000).networkAddress
    )
    let deviceNetwork = try await SwiftOCADevice.OcaControlNetwork(
      objectNumber: networkONo,
      role: "Control Network",
      deviceDelegate: device,
      addToRootBlock: true
    )
    let blob = try descriptor.blob
    await { @OcaDevice in deviceNetwork.systemInterfaces = [blob] }()

    let network: SwiftOCA.OcaControlNetwork = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: networkONo,
        classIdentification: SwiftOCA.OcaControlNetwork.classIdentification
      )
    )
    let systemInterfaces = try await network.$systemInterfaces._getValue(network, flags: [])
    XCTAssertEqual(systemInterfaces.count, 1)
    XCTAssertEqual(
      try systemInterfaces.first?.decode(Ocp1NetworkSystemInterfaceDescriptor.self),
      descriptor
    )
  }
}
#endif
