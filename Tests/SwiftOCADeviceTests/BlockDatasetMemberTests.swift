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

/// A block's datasets as members: DeleteMember and FindDatasets over the wire.
final class BlockDatasetMemberTests: XCTestCase {
  private var endpointTask: Task<(), Never>?

  override func tearDown() async throws {
    endpointTask?.cancel()
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

  func testDeleteMemberDeletesADatasetOfTheBlock() async throws {
    let basePath = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: basePath) }
    let gainONo: OcaONo = 10003
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)
    let provider = try OcaFileDatasetStorageProvider(basePath: basePath, deviceDelegate: device)
    await device.setDatasetStorageProvider(provider)
    _ = try await SwiftOCADevice.OcaGain(
      objectNumber: gainONo,
      role: "Gain",
      deviceDelegate: device,
      addToRootBlock: true
    )
    let connection = await OcaLocalConnection(endpoint)
    endpointTask = Task { try? await endpoint.run() }
    try await connection.connect()
    let oNo = try await provider.construct(
      classID: SwiftOCADevice.OcaDataset.classID,
      targetONo: OcaRootBlockONo,
      datasetONo: nil,
      name: "Station ident",
      type: OcaParamDatasetMimeType,
      maxSize: .max,
      initialContents: .init(),
      controller: nil
    )
    let rootBlock = await connection.rootBlock

    // the type is matched as its comparison type says
    let found = try await rootBlock.findDatasets(
      name: "Station",
      nameComparisonType: .substring,
      type: OcaParamDatasetMimeType.uppercased(),
      typeComparisonType: .exactCaseInsensitive
    )
    XCTAssertEqual(found.map { $0.object.memberObjectIdentification.oNo }, [oNo])
    let none = try await rootBlock.findDatasets(
      name: "Station",
      nameComparisonType: .substring,
      type: OcaPatchDatasetMimeType,
      typeComparisonType: .exact
    )
    XCTAssertEqual(none.count, 0)

    try await rootBlock.deleteMember(objectNumber: oNo)
    let remaining = try await rootBlock.getDatasetObjects()
    XCTAssertEqual(remaining.count, 0)

    await assertStatus(.notImplemented) { try await rootBlock.deleteMember(objectNumber: gainONo) }
    await assertStatus(.parameterOutOfRange) { try await rootBlock.deleteMember(objectNumber: oNo) }
    try await connection.disconnect()
  }
}
#endif
