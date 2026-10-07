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

@_spi(SwiftOCAPrivate) @testable import SwiftOCA
import Testing

private final class MockConnection: OcaConnection {
  override nonisolated var connectionPrefix: String {
    "oca/mock"
  }
}

/// `_getRolePath()` follows owners through objects already resolved. An object without an
/// owner ends the path only if the root block lists it; otherwise it is not in the block tree,
/// and its path is not known locally.
struct RolePathTests {
  private let flags: OcaPropertyResolutionFlags = [.returnCachedValue]

  private func resolve<T: OcaRoot>(
    _ type: T.Type,
    _ oNo: OcaONo,
    role: String,
    on connection: OcaConnection
  ) async throws -> T {
    let object: T = try await connection.resolve(object: OcaObjectIdentification(
      oNo: oNo,
      classIdentification: T.classIdentification
    ))
    object._set(role: role)
    return object
  }

  private func setRootBlockMembers(_ oNos: [OcaONo], on connection: OcaConnection) async {
    await connection.rootBlock._set(actionObjects: oNos.map {
      OcaObjectIdentification(oNo: $0, classIdentification: OcaRoot.classIdentification)
    })
  }

  @Test
  func rootBlockMember() async throws {
    let connection = await MockConnection()
    let gain = try await resolve(OcaGain.self, 10001, role: "Gain", on: connection)
    gain._set(owner: OcaRootBlockONo)

    #expect(try await gain._getRolePath(flags: flags) == ["Gain"])
  }

  @Test
  func nestedBlockMember() async throws {
    let connection = await MockConnection()
    let block = try await resolve(OcaBlock.self, 10001, role: "Block", on: connection)
    block._set(owner: OcaRootBlockONo)
    let gain = try await resolve(OcaGain.self, 10002, role: "Gain", on: connection)
    gain._set(owner: block.objectNumber)

    #expect(try await gain._getRolePath(flags: flags) == ["Block", "Gain"])
  }

  @Test
  func managerListedInRootBlock() async throws {
    let connection = await MockConnection()
    let securityManager = try await resolve(
      OcaSecurityManager.self,
      OcaSecurityManagerONo,
      role: "SecurityManager",
      on: connection
    )
    await setRootBlockMembers([securityManager.objectNumber], on: connection)

    #expect(try await securityManager._getRolePath(flags: flags) == ["SecurityManager"])
  }

  @Test
  func managerNotListedInRootBlock() async throws {
    let connection = await MockConnection()
    let securityManager = try await resolve(
      OcaSecurityManager.self,
      OcaSecurityManagerONo,
      role: "SecurityManager",
      on: connection
    )
    await setRootBlockMembers([], on: connection)

    await #expect(throws: Ocp1Error.objectClassMismatch) {
      try await securityManager._getRolePath(flags: flags)
    }
  }

  @Test
  func unownedObjectNotListedInRootBlock() async throws {
    let connection = await MockConnection()
    let gain = try await resolve(OcaGain.self, 10001, role: "Gain", on: connection)
    gain._set(owner: OcaInvalidONo)
    await setRootBlockMembers([], on: connection)

    // not found locally, so the device is asked, which a mock connection cannot answer
    await #expect(throws: Ocp1Error.notConnected) {
      try await gain._getRolePath(flags: flags)
    }
  }

  @Test
  func memberOfUnownedBlock() async throws {
    let connection = await MockConnection()
    let block = try await resolve(OcaBlock.self, 10001, role: "Block", on: connection)
    block._set(owner: OcaInvalidONo)
    let gain = try await resolve(OcaGain.self, 10002, role: "Gain", on: connection)
    gain._set(owner: block.objectNumber)
    await setRootBlockMembers([], on: connection)

    await #expect(throws: Ocp1Error.notConnected) {
      try await gain._getRolePath(flags: flags)
    }
  }

  @Test
  func ownersThatFormACycle() async throws {
    let connection = await MockConnection()
    let blockA = try await resolve(OcaBlock.self, 10001, role: "A", on: connection)
    let blockB = try await resolve(OcaBlock.self, 10002, role: "B", on: connection)
    blockA._set(owner: blockB.objectNumber)
    blockB._set(owner: blockA.objectNumber)

    await #expect(throws: Ocp1Error.notConnected) {
      try await blockA._getRolePath(flags: flags)
    }
  }
}
