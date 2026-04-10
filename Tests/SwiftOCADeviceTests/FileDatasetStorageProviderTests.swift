//
// Copyright (c) 2025 PADL Software Pty Ltd
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

final class FileDatasetStorageProviderTests: XCTestCase {
  private var basePath: URL!

  override func setUp() async throws {
    basePath = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  override func tearDown() async throws {
    if let basePath {
      try? FileManager.default.removeItem(at: basePath)
    }
  }

  func testConstructAndResolve() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let provider = try OcaFileDatasetStorageProvider(
      basePath: basePath,
      deviceDelegate: device
    )
    await device.setDatasetStorageProvider(provider)

    let json = Data("{\"key\":\"value\"}".utf8)
    let oNo = try await provider.construct(
      classID: SwiftOCADevice.OcaDataset.classID,
      targetONo: OcaRootBlockONo,
      datasetONo: nil,
      name: "test_dataset",
      type: OcaParamDatasetMimeType,
      maxSize: .max,
      initialContents: .init(json),
      controller: nil
    )

    let dataset = try await provider.resolve(targetONo: OcaRootBlockONo, datasetONo: oNo)
    XCTAssertEqual(dataset.objectNumber, oNo)
    await Task { @OcaDevice in
      XCTAssertEqual(dataset.name, "test_dataset")
      XCTAssertEqual(dataset.type, OcaParamDatasetMimeType)
      XCTAssertEqual(dataset.owner, OcaRootBlockONo)
    }.value
  }

  func testResolveWithNilTarget() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let provider = try OcaFileDatasetStorageProvider(
      basePath: basePath,
      deviceDelegate: device
    )
    await device.setDatasetStorageProvider(provider)

    let oNo = try await provider.construct(
      classID: SwiftOCADevice.OcaDataset.classID,
      targetONo: OcaRootBlockONo,
      datasetONo: nil,
      name: "resolve_nil_target",
      type: OcaParamDatasetMimeType,
      maxSize: .max,
      initialContents: .init(),
      controller: nil
    )

    let dataset = try await provider.resolve(targetONo: nil, datasetONo: oNo)
    XCTAssertEqual(dataset.objectNumber, oNo)
  }

  func testGetDatasetObjects() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let provider = try OcaFileDatasetStorageProvider(
      basePath: basePath,
      deviceDelegate: device
    )
    await device.setDatasetStorageProvider(provider)

    let targetA: OcaONo = 10001
    let targetB: OcaONo = 10002

    try await provider.construct(
      classID: SwiftOCADevice.OcaDataset.classID,
      targetONo: targetA,
      datasetONo: nil,
      name: "ds_a",
      type: OcaParamDatasetMimeType,
      maxSize: .max,
      initialContents: .init(),
      controller: nil
    )

    try await provider.construct(
      classID: SwiftOCADevice.OcaDataset.classID,
      targetONo: targetB,
      datasetONo: nil,
      name: "ds_b",
      type: OcaParamDatasetMimeType,
      maxSize: .max,
      initialContents: .init(),
      controller: nil
    )

    let allDatasets = try await provider.getDatasetObjects(targetONo: nil)
    XCTAssertEqual(allDatasets.count, 2)

    let datasetsForA = try await provider.getDatasetObjects(targetONo: targetA)
    XCTAssertEqual(datasetsForA.count, 1)
    await Task { @OcaDevice in
      XCTAssertEqual(datasetsForA.first?.name, "ds_a")
    }.value
  }

  func testFindByName() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let provider = try OcaFileDatasetStorageProvider(
      basePath: basePath,
      deviceDelegate: device
    )
    await device.setDatasetStorageProvider(provider)

    try await provider.construct(
      classID: SwiftOCADevice.OcaDataset.classID,
      targetONo: OcaRootBlockONo,
      datasetONo: nil,
      name: "Alpha",
      type: OcaParamDatasetMimeType,
      maxSize: .max,
      initialContents: .init(),
      controller: nil
    )

    try await provider.construct(
      classID: SwiftOCADevice.OcaDataset.classID,
      targetONo: OcaRootBlockONo,
      datasetONo: nil,
      name: "AlphaBeta",
      type: OcaParamDatasetMimeType,
      maxSize: .max,
      initialContents: .init(),
      controller: nil
    )

    let exact = try await provider.find(
      targetONo: nil,
      name: "Alpha",
      nameComparisonType: .exact
    )
    XCTAssertEqual(exact.count, 1)

    let prefix = try await provider.find(
      targetONo: nil,
      name: "Alpha",
      nameComparisonType: .substring
    )
    XCTAssertEqual(prefix.count, 2)

    let caseInsensitive = try await provider.find(
      targetONo: nil,
      name: "alpha",
      nameComparisonType: .exactCaseInsensitive
    )
    XCTAssertEqual(caseInsensitive.count, 1)
  }

  func testReadWriteRoundTrip() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let provider = try OcaFileDatasetStorageProvider(
      basePath: basePath,
      deviceDelegate: device
    )
    await device.setDatasetStorageProvider(provider)

    let jsonString = "{\"hello\":\"world\"}"
    let jsonData = Data(jsonString.utf8)

    let oNo = try await provider.construct(
      classID: SwiftOCADevice.OcaDataset.classID,
      targetONo: OcaRootBlockONo,
      datasetONo: nil,
      name: "rw_test",
      type: OcaParamDatasetMimeType,
      maxSize: .max,
      initialContents: .init(jsonData),
      controller: nil
    )

    let dataset = try await provider.resolve(targetONo: OcaRootBlockONo, datasetONo: oNo)

    let (size, readHandle) = try await dataset.openRead(lockState: .noLock, controller: nil)
    XCTAssertEqual(size, OcaUint64(jsonData.count))
    let (complete, blob) = try await dataset.read(
      handle: readHandle,
      position: 0,
      partSize: size,
      controller: nil
    )
    XCTAssertTrue(complete)
    XCTAssertEqual(Data(blob), jsonData)
    try await dataset.close(handle: readHandle, controller: nil)

    let newJsonString = "{\"updated\":true}"
    let newJsonData = Data(newJsonString.utf8)

    let (_, writeHandle) = try await dataset.openWrite(lockState: .noLock, controller: nil)
    try await dataset.write(
      handle: writeHandle,
      position: 0,
      part: .init(newJsonData),
      controller: nil
    )
    try await dataset.close(handle: writeHandle, controller: nil)

    let (size2, readHandle2) = try await dataset.openRead(lockState: .noLock, controller: nil)
    XCTAssertEqual(size2, OcaUint64(newJsonData.count))
    let (complete2, blob2) = try await dataset.read(
      handle: readHandle2,
      position: 0,
      partSize: size2,
      controller: nil
    )
    XCTAssertTrue(complete2)
    XCTAssertEqual(Data(blob2), newJsonData)
    try await dataset.close(handle: readHandle2, controller: nil)
  }

  func testDelete() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let provider = try OcaFileDatasetStorageProvider(
      basePath: basePath,
      deviceDelegate: device
    )
    await device.setDatasetStorageProvider(provider)

    let oNo = try await provider.construct(
      classID: SwiftOCADevice.OcaDataset.classID,
      targetONo: OcaRootBlockONo,
      datasetONo: nil,
      name: "to_delete",
      type: OcaParamDatasetMimeType,
      maxSize: .max,
      initialContents: .init(),
      controller: nil
    )

    try await provider.delete(targetONo: OcaRootBlockONo, datasetONo: oNo)

    do {
      _ = try await provider.resolve(targetONo: OcaRootBlockONo, datasetONo: oNo)
      XCTFail("Expected unknownDataset error")
    } catch let error as Ocp1Error {
      XCTAssertEqual(error, .unknownDataset)
    }
  }

  func testDuplicate() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let provider = try OcaFileDatasetStorageProvider(
      basePath: basePath,
      deviceDelegate: device
    )
    await device.setDatasetStorageProvider(provider)

    let jsonData = Data("{\"dup\":\"test\"}".utf8)
    let oldONo = try await provider.construct(
      classID: SwiftOCADevice.OcaDataset.classID,
      targetONo: OcaRootBlockONo,
      datasetONo: nil,
      name: "original",
      type: OcaParamDatasetMimeType,
      maxSize: .max,
      initialContents: .init(jsonData),
      controller: nil
    )

    let newTargetONo: OcaONo = 10001
    let newONo = try await provider.duplicate(
      oldDatasetONo: oldONo,
      oldTargetONo: OcaRootBlockONo,
      newDatasetONo: nil,
      newTargetONo: newTargetONo,
      newName: "copy",
      newMaxSize: .max,
      controller: nil
    )

    XCTAssertNotEqual(oldONo, newONo)

    let newDataset = try await provider.resolve(targetONo: newTargetONo, datasetONo: newONo)
    await Task { @OcaDevice in
      XCTAssertEqual(newDataset.name, "copy")
      XCTAssertEqual(newDataset.owner, newTargetONo)
    }.value

    let (size, handle) = try await newDataset.openRead(lockState: .noLock, controller: nil)
    let (_, blob) = try await newDataset.read(
      handle: handle,
      position: 0,
      partSize: size,
      controller: nil
    )
    try await newDataset.close(handle: handle, controller: nil)
    XCTAssertEqual(Data(blob), jsonData)
  }

  func testONoAllocation() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    _ = try await OcaLocalDeviceEndpoint(device: device)

    let provider = try OcaFileDatasetStorageProvider(
      basePath: basePath,
      validDatasetONos: 0x10000...0x10002,
      deviceDelegate: device
    )
    await device.setDatasetStorageProvider(provider)

    let oNo1 = try await provider.construct(
      classID: SwiftOCADevice.OcaDataset.classID,
      targetONo: OcaRootBlockONo,
      datasetONo: nil,
      name: "ds1",
      type: OcaParamDatasetMimeType,
      maxSize: .max,
      initialContents: .init(),
      controller: nil
    )

    let oNo2 = try await provider.construct(
      classID: SwiftOCADevice.OcaDataset.classID,
      targetONo: OcaRootBlockONo,
      datasetONo: nil,
      name: "ds2",
      type: OcaParamDatasetMimeType,
      maxSize: .max,
      initialContents: .init(),
      controller: nil
    )

    let oNo3 = try await provider.construct(
      classID: SwiftOCADevice.OcaDataset.classID,
      targetONo: OcaRootBlockONo,
      datasetONo: nil,
      name: "ds3",
      type: OcaParamDatasetMimeType,
      maxSize: .max,
      initialContents: .init(),
      controller: nil
    )

    let allocatedONos: Set<OcaONo> = [oNo1, oNo2, oNo3]
    XCTAssertEqual(allocatedONos.count, 3)

    do {
      _ = try await provider.construct(
        classID: SwiftOCADevice.OcaDataset.classID,
        targetONo: OcaRootBlockONo,
        datasetONo: nil,
        name: "ds4",
        type: OcaParamDatasetMimeType,
        maxSize: .max,
        initialContents: .init(),
        controller: nil
      )
      XCTFail("Expected invalidDatasetONo error")
    } catch let error as Ocp1Error {
      XCTAssertEqual(error, .invalidDatasetONo)
    }
  }

  func testEndToEndParamDataset() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)

    let provider = try OcaFileDatasetStorageProvider(
      basePath: basePath,
      deviceDelegate: device
    )
    await device.setDatasetStorageProvider(provider)

    let connection = await OcaLocalConnection(endpoint)
    let endpointTask = Task { try? await endpoint.run() }
    try await connection.connect()

    let testDataset = try await connection.rootBlock.constructDataset(
      classID: SwiftOCA.OcaDataset.classID,
      name: "e2e_test",
      type: OcaParamDatasetMimeType,
      maxSize: 1024,
      initialContents: .init()
    )
    try await connection.rootBlock.store(currentParameterData: testDataset)
    try await device.deregister(objectNumber: testDataset)
    try await connection.rootBlock.apply(paramDataset: testDataset)

    try await connection.disconnect()
    endpointTask.cancel()
  }

  func testEndToEndPatchDataset() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await OcaLocalDeviceEndpoint(device: device)

    let provider = try OcaFileDatasetStorageProvider(
      basePath: basePath,
      deviceDelegate: device
    )
    await device.setDatasetStorageProvider(provider)

    let connection = await OcaLocalConnection(endpoint)
    let endpointTask = Task { try? await endpoint.run() }
    try await connection.connect()

    let paramDataset = try await connection.rootBlock.constructDataset(
      classID: SwiftOCA.OcaDataset.classID,
      name: "param_for_patch",
      type: OcaParamDatasetMimeType,
      maxSize: 1024,
      initialContents: .init()
    )
    try await connection.rootBlock.store(currentParameterData: paramDataset)

    let deviceManager = await device.deviceManager!
    let patchONo = try await deviceManager.storePatch(
      patchDatasetONo: nil,
      name: "file_patch",
      paramDatasetONos: [paramDataset],
      controller: nil,
      createIfAbsent: true
    )
    try await deviceManager.applyPatch(datasetONo: patchONo, controller: nil)

    try await connection.disconnect()
    endpointTask.cancel()
  }
}

#endif
