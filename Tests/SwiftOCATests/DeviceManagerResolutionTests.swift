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

@testable import SwiftOCA
import Testing

private final class MockConnection: Ocp1Connection {
  override nonisolated var connectionPrefix: String { "oca/mock" }
}

private final class MockVendorDeviceManager: OcaDeviceManager, @unchecked Sendable {
  override class var classID: OcaClassID { OcaClassID("1.3.1.1") }
  override class var classVersion: OcaClassVersionNumber { 1 }
}

private final class MockVendorNetworkManager: OcaNetworkManager, @unchecked Sendable {
  override class var classID: OcaClassID { OcaClassID("1.3.6.1") }
  override class var classVersion: OcaClassVersionNumber { 1 }
}

/// `connection.deviceManager` returns the deepest subclass resolved for the
/// well-known ONo, so a caller reading it after a vendor subclass was resolved
/// observes the same instance (and property subjects) as the resolver.
@Suite
struct DeviceManagerResolutionTests {
  @Test
  func deviceManagerFollowsResolvedSubclass() async throws {
    try await OcaClassRegistry.shared.register(MockVendorDeviceManager.self)
    let connection = await MockConnection()

    let base = await connection.deviceManager
    #expect(type(of: base) == OcaDeviceManager.self)

    let resolved: MockVendorDeviceManager = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: OcaDeviceManagerONo,
        classIdentification: MockVendorDeviceManager.classIdentification
      )
    )
    #expect(resolved !== base)
    #expect(await connection.deviceManager === resolved)
  }

  @Test
  func networkManagerFollowsResolvedSubclass() async throws {
    try await OcaClassRegistry.shared.register(MockVendorNetworkManager.self)
    let connection = await MockConnection()

    let base = await connection.networkManager
    #expect(type(of: base) == OcaNetworkManager.self)

    let resolved: MockVendorNetworkManager = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: OcaNetworkManagerONo,
        classIdentification: MockVendorNetworkManager.classIdentification
      )
    )
    #expect(resolved !== base)
    #expect(await connection.networkManager === resolved)
  }
}
