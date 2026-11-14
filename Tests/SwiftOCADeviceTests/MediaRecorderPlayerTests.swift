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

/// A player of nothing, whose transport and position live in memory, as a device's
/// subclass supplies them.
private final class MemoryPlayer: SwiftOCADevice.OcaMediaRecorderPlayer, @unchecked Sendable {
  var position: OcaUint64 = 0

  override func open(
    datasetONo: OcaONo,
    accessMode: OcaMediaAccessMode,
    lockState: OcaLockState,
    from controller: any OcaController
  ) async throws {
    guard accessMode == .play else { throw Ocp1Error.status(.notImplemented) }
    self.datasetONo = datasetONo
    trackCount = 2
    state = .stopped
  }

  override func close(from controller: any OcaController) async throws {
    datasetONo = OcaInvalidONo
    trackCount = 0
    trackFunctions = []
    state = .idle
  }

  override func play(from controller: any OcaController) async throws {
    guard state != .idle else { throw Ocp1Error.status(.invalidRequest) }
    state = .playing
  }

  override func stop(from controller: any OcaController) async throws {
    guard state != .idle else { throw Ocp1Error.status(.invalidRequest) }
    state = .stopped
  }

  override func getPosition(from controller: any OcaController) async throws
    -> OcaMediaVolumePosition
  {
    guard state != .idle else { throw Ocp1Error.status(.invalidRequest) }
    return .samples(position)
  }

  override func setPosition(
    position: OcaMediaVolumePosition,
    from controller: any OcaController
  ) async throws {
    guard let samples = position.samples else { throw Ocp1Error.status(.parameterError) }
    self.position = samples
  }
}

final class MediaRecorderPlayerTests: XCTestCase {
  private var endpointTask: Task<(), Never>?

  override func tearDown() async throws {
    endpointTask?.cancel()
  }

  /// A device with `player` at `oNo`, and a connection to it.
  private func connect(_ make: (OcaDevice) async throws -> SwiftOCADevice.OcaRoot) async throws
    -> (OcaDevice, OcaConnection)
  {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)
    _ = try await make(device)
    let connection = await OcaLocalConnection(endpoint)
    endpointTask = Task { try? await endpoint.run() }
    try await connection.connect()
    return (device, connection)
  }

  private func resolvePlayer(_ connection: OcaConnection, _ oNo: OcaONo) async throws -> SwiftOCA
    .OcaMediaRecorderPlayer
  {
    try await connection.resolve(object: OcaObjectIdentification(
      oNo: oNo,
      classIdentification: SwiftOCA.OcaMediaRecorderPlayer.classIdentification
    ))
  }

  private func assertStatus(
    _ status: OcaStatus,
    _ body: () async throws -> (),
    line: UInt = #line
  ) async {
    do {
      try await body()
      XCTFail("not refused", line: line)
    } catch {
      XCTAssertEqual(error as? Ocp1Error, .status(status), line: line)
    }
  }

  func testASubclassAnswersTheTransportAndPosition() async throws {
    let oNo: OcaONo = 10001
    let (_, connection) = try await connect { device in
      try await MemoryPlayer(
        objectNumber: oNo,
        role: "Player",
        deviceDelegate: device,
        addToRootBlock: true
      )
    }
    let player = try await resolvePlayer(connection, oNo)

    // the track functions need a volume open
    await assertStatus(.invalidRequest) { try await player.setTrackFunctions(functions: [1]) }
    await assertStatus(.notImplemented) { try await player.open(
      datasetONo: 20001,
      accessMode: .record,
      lockState: .noLock
    ) }

    try await player.open(datasetONo: 20001, accessMode: .play, lockState: .noLock)
    let value1 = try await player.$state._getValue(player, flags: [])
    XCTAssertEqual(value1, .stopped)
    let value2 = try await player.$datasetONo._getValue(player, flags: [])
    XCTAssertEqual(value2, 20001)
    let value3 = try await player.$trackCount._getValue(player, flags: [])
    XCTAssertEqual(value3, 2)

    try await player.setTrackFunctions(functions: [OcaMediaTrackFunctionPlayInPlayMode, 0])
    let value4 = try await player.$trackFunctions._getValue(player, flags: [])
    XCTAssertEqual(value4, [1, 0])

    try await player.setPosition(position: .samples(480))
    let value5 = try await player.getPosition()
    XCTAssertEqual(value5, .samples(480))
    try await player.play()
    let value6 = try await player.$state._getValue(player, flags: [])
    XCTAssertEqual(value6, .playing)
    try await player.stop()

    // recording is refused by the class itself
    await assertStatus(.notImplemented) { try await player.record() }
    // SetTrackCount needs a volume open for recording
    await assertStatus(.notImplemented) { try await player.setTrackCount(trackCount: 4) }

    try await player.close()
    await assertStatus(.invalidRequest) { _ = try await player.getPosition() }
    try await connection.disconnect()
  }

  func testTheClassKeepsTheWindowAndPlayOptionAndRefusesTheRest() async throws {
    let oNo: OcaONo = 10002
    let (_, connection) = try await connect { device in
      try await SwiftOCADevice.OcaMediaRecorderPlayer(
        objectNumber: oNo,
        role: "Player",
        deviceDelegate: device,
        addToRootBlock: true
      )
    }
    let player = try await resolvePlayer(connection, oNo)

    try await player.setWindowRange(firstPosition: .samples(48000), lastPosition: .seconds(2.5))
    let range = try await player.getWindowRange()
    XCTAssertEqual(range.firstPosition, .samples(48000))
    XCTAssertEqual(range.lastPosition.seconds, 2.5)

    try await player.setPlayOption(option: .repeatInterval)
    let value7 = try await player.$playOption._getValue(player, flags: [])
    XCTAssertEqual(value7, .repeatInterval)

    for refused in [
      { try await player.open(datasetONo: 1, accessMode: .play, lockState: .noLock) },
      { try await player.close() },
      { try await player.play() },
      { try await player.stop() },
      { try await player.reset() },
      { _ = try await player.getPosition() },
      { try await player.setPosition(position: .samples(0)) },
    ] as [() async throws -> ()] {
      await assertStatus(.notImplemented, refused)
    }
    let value8 = try await player.$state._getValue(player, flags: [])
    XCTAssertEqual(value8, .idle)
    try await connection.disconnect()
  }

}
#endif
