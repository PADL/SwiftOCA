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

@_spi(SwiftOCAPrivate) import SwiftOCA
@testable import SwiftOCADevice
import XCTest

final class DatasetClassTests: XCTestCase {
  /// OcaRoot's class ID, which every class descends from, names no object's class, so a
  /// dataset carrying it is refused rather than applied to whatever object reads it.
  func testADatasetOfOcaRootsClassIsRefused() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let gain = try await SwiftOCADevice.OcaGain(role: "Gain", deviceDelegate: device, addToRootBlock: false)

    var json = try await gain.serialize()
    json["_classID"] = "1"
    do {
      try await gain.deserialize(jsonObject: json)
      XCTFail("a dataset of class 1 was applied")
    } catch {
      XCTAssertEqual(error as? Ocp1Error, .objectClassMismatch)
    }
  }

  /// GetDatasetSizes is dispatched to the dataset's own `getDataSetSizes`, so a subclass's
  /// override answers it.
  func testGetDatasetSizesIsAnsweredByASubclassOverride() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)
    let oNo: OcaONo = 10001
    _ = try await SizedDataset(
      owner: OcaRootBlockONo, name: "Sized", type: "application/octet-stream", objectNumber: oNo,
      deviceDelegate: device, addToRootBlock: true
    )

    let connection = await OcaLocalConnection(endpoint)
    let endpointTask = Task { try? await endpoint.run() }
    try await connection.connect()

    let dataset: SwiftOCA.OcaDataset = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: oNo,
        classIdentification: SwiftOCA.OcaDataset.classIdentification
      )
    )
    let sizes = try await dataset.getDatasetSizes()
    XCTAssertEqual(sizes.currentSize, 42)
    XCTAssertEqual(sizes.maxSize, 4096)

    try await connection.disconnect()
    endpointTask.cancel()
  }
}

private final class SizedDataset: SwiftOCADevice.OcaDataset, @unchecked Sendable {
  override func getDataSetSizes() async throws -> (OcaUint64, OcaUint64) {
    (42, 4096)
  }
}
