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

/// OcaMatrix over the local transport: its members, the current area, the proxy that
/// forwards to it, and the locking AES70-2 specifies for SetCurrentXY (3.2),
/// SetCurrentXYLock (3.15) and UnlockCurrent (3.16).
final class MatrixTests: XCTestCase {
  private static let matrixONo: OcaONo = 0x0001_0300
  private static let columns: OcaUint16 = 3 // X
  private static let rows: OcaUint16 = 2 // Y
  private static let wildcard: OcaMatrixCoordinate = 0xFFFF

  private struct Harness {
    let connection: OcaLocalConnection
    let endpointTask: Task<(), Never>
    let deviceMatrix: SwiftOCADevice.OcaMatrix<SwiftOCADevice.OcaBooleanActuator>
    /// indexed `[x][y]`
    let actuators: [[SwiftOCADevice.OcaBooleanActuator]]
    let matrix: SwiftOCA.OcaMatrix

    func tearDown() async {
      try? await connection.disconnect()
      endpointTask.cancel()
    }
  }

  private func makeHarness() async throws -> Harness {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let deviceMatrix = try await SwiftOCADevice.OcaMatrix<SwiftOCADevice.OcaBooleanActuator>(
      rows: Self.rows,
      columns: Self.columns,
      objectNumber: Self.matrixONo,
      deviceDelegate: device,
      addToRootBlock: true
    )
    var actuators = [[SwiftOCADevice.OcaBooleanActuator]]()
    for x in 0..<Self.columns {
      var column = [SwiftOCADevice.OcaBooleanActuator]()
      for y in 0..<Self.rows {
        let actuator = try await SwiftOCADevice.OcaBooleanActuator(
          role: "Actuator \(x),\(y)",
          deviceDelegate: device,
          addToRootBlock: false
        )
        try await deviceMatrix.add(member: actuator, at: OcaVector2D(x: x, y: y))
        column.append(actuator)
      }
      actuators.append(column)
    }
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)
    let endpointTask = Task { do { try await endpoint.run() } catch {} }
    let connection = await OcaLocalConnection(endpoint)
    try await connection.connect()
    let matrix: SwiftOCA.OcaMatrix = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: Self.matrixONo,
        classIdentification: SwiftOCA.OcaMatrix.classIdentification
      )
    )
    return Harness(
      connection: connection,
      endpointTask: endpointTask,
      deviceMatrix: deviceMatrix,
      actuators: actuators,
      matrix: matrix
    )
  }

  private func isLocked(_ object: SwiftOCADevice.OcaRoot) async -> Bool {
    await { @OcaDevice in
      if case .unlocked = object.lockState { return false }
      return true
    }()
  }

  private func setting(_ actuator: SwiftOCADevice.OcaBooleanActuator) async -> Bool {
    await { @OcaDevice in actuator.setting }()
  }

  /// SetCurrentXY as a request that awaits the device's response. Through the property
  /// setter it would go without one once the matrix is subscribed (as resolving the
  /// proxy leaves it), and the next proxy call could then overtake it.
  private func setCurrentXY(_ h: Harness, x: OcaMatrixCoordinate, y: OcaMatrixCoordinate) async throws {
    try await h.matrix.sendCommandRrq(
      methodID: OcaMethodID("3.2"),
      parameters: OcaVector2D<OcaMatrixCoordinate>(x: x, y: y)
    )
  }

  /// GetSize (3.3) returns six values: the size and each axis's bounds.
  func testSizeCarriesEachAxisBounds() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    let size = try await h.matrix.$size._getValue(h.matrix, flags: [])
    XCTAssertEqual(size.x, Self.columns)
    XCTAssertEqual(size.y, Self.rows)
    XCTAssertEqual(size.minX, 0)
    XCTAssertEqual(size.maxX, Self.columns)
    XCTAssertEqual(size.minY, 0)
    XCTAssertEqual(size.maxY, Self.rows)
  }

  func testMembers() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    let members = try await h.matrix.$members._getValue(h.matrix, flags: [])
    XCTAssertEqual(members.nX, Int(Self.columns))
    XCTAssertEqual(members.nY, Int(Self.rows))
    for x in 0..<Int(Self.columns) {
      for y in 0..<Int(Self.rows) {
        XCTAssertEqual(members[x, y], h.actuators[x][y].objectNumber, "(\(x),\(y))")
      }
    }
  }

  func testGetMemberReturnsTheMemberAtACoordinate() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    let oNo = try await h.matrix.get(x: 2, y: 1)
    XCTAssertEqual(oNo, h.actuators[2][1].objectNumber)
  }

  func testSetCurrentXYLocksTheMatrixButNotItsMembers() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    try await setCurrentXY(h, x: 1, y: 0)
    let xy = try await h.matrix.$currentXY._getValue(h.matrix, flags: [])
    XCTAssertEqual(xy.x, 1)
    XCTAssertEqual(xy.y, 0)
    let matrixLocked = await isLocked(h.deviceMatrix)
    let memberLocked = await isLocked(h.actuators[1][0])
    XCTAssertTrue(matrixLocked)
    XCTAssertFalse(memberLocked, "SetCurrentXY must not lock the members (AES70-2)")
  }

  func testProxyForwardsToTheCurrentMemberAndReleasesTheLock() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    // resolved first: any forwarded command consumes SetCurrentXY's temporary lock
    let proxy: SwiftOCA.OcaBooleanActuator = try await h.matrix.resolveProxy()
    try await setCurrentXY(h, x: 2, y: 1)
    try await proxy.$setting._setValue(proxy, true)

    for x in 0..<Int(Self.columns) {
      for y in 0..<Int(Self.rows) {
        let value = await setting(h.actuators[x][y])
        XCTAssertEqual(value, x == 2 && y == 1, "(\(x),\(y))")
      }
    }
    let matrixLocked = await isLocked(h.deviceMatrix)
    XCTAssertFalse(matrixLocked, "the proxy call releases SetCurrentXY's lock")
  }

  func testWildcardAddressesAWholeRow() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    let proxy: SwiftOCA.OcaBooleanActuator = try await h.matrix.resolveProxy()
    try await setCurrentXY(h, x: Self.wildcard, y: 1)
    try await proxy.$setting._setValue(proxy, true)

    for x in 0..<Int(Self.columns) {
      for y in 0..<Int(Self.rows) {
        let value = await setting(h.actuators[x][y])
        XCTAssertEqual(value, y == 1, "(\(x),\(y))")
      }
    }
  }

  func testRepeatedSetCurrentXYStillReleasesTheLock() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    let proxy: SwiftOCA.OcaBooleanActuator = try await h.matrix.resolveProxy()
    try await setCurrentXY(h, x: 0, y: 0)
    try await setCurrentXY(h, x: 1, y: 1)
    try await proxy.$setting._setValue(proxy, true)

    let value = await setting(h.actuators[1][1])
    XCTAssertTrue(value)
    let matrixLocked = await isLocked(h.deviceMatrix)
    XCTAssertFalse(matrixLocked, "a second SetCurrentXY must not leave the matrix locked")
  }

  func testSetCurrentXYLockLocksTheMembersUntilUnlockCurrent() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    try await h.matrix.lockCurrent(x: Self.wildcard, y: 0)
    for x in 0..<Int(Self.columns) {
      let row0 = await isLocked(h.actuators[x][0])
      let row1 = await isLocked(h.actuators[x][1])
      XCTAssertTrue(row0, "(\(x),0) is in the current area")
      XCTAssertFalse(row1, "(\(x),1) is not")
    }

    try await h.matrix.unlockCurrent()
    for x in 0..<Int(Self.columns) {
      let row0 = await isLocked(h.actuators[x][0])
      XCTAssertFalse(row0, "(\(x),0) after UnlockCurrent")
    }

    // members that are already unlocked are not a failure (AES70-2)
    try await h.matrix.unlockCurrent()
  }

  func testCoordinatesOutsideTheMatrixAreRejected() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    do {
      try await setCurrentXY(h, x: Self.columns, y: 0)
      XCTFail("expected parameterOutOfRange")
    } catch let Ocp1Error.status(status) {
      XCTAssertEqual(status, .parameterOutOfRange)
    }
  }

  private func awaitSubscription(_ object: SwiftOCA.OcaRoot) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
      if (try? await object.isSubscribed) == true { return true }
      try? await Task.sleep(for: .milliseconds(25))
    }
    return false
  }

  /// A member change is notified as GetMembers returns the members: object numbers,
  /// `OcaInvalidONo` for an empty cell. A `nil` member cannot be encoded, so a
  /// notification carrying the members themselves reached nobody.
  func testRemovingAMemberNotifiesAnEmptyCell() async throws {
    let h = try await makeHarness()
    defer { Task { await h.tearDown() } }

    await h.matrix.$members.subscribe(h.matrix)
    let subscribed = await awaitSubscription(h.matrix)
    XCTAssertTrue(subscribed, "precondition: the matrix should have subscribed")

    let emptied = Seen()
    let consumer = Task {
      for try await result in h.matrix.$members.async {
        if case let .success(value) = result,
           let members = value as? OcaArray2D<OcaONo>,
           members[1, 0] == OcaInvalidONo
        {
          await emptied.set()
          return
        }
      }
    }
    defer { consumer.cancel() }

    let deviceMatrix = h.deviceMatrix
    try await { @OcaDevice in
      try await deviceMatrix.remove(coordinate: OcaVector2D(x: 1, y: 0))
    }()

    var notified = false
    let deadline = ContinuousClock.now + .seconds(5)
    while !notified, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(25))
      notified = await emptied.value
    }
    XCTAssertTrue(notified, "the client did not see (1,0) emptied")
  }
}

private actor Seen {
  private(set) var value = false
  func set() { value = true }
}
