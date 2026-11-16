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

private typealias DeviceBlock = SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>

/// One DatasetObjects (3.7) event: the block that sent it, the change type and the list.
private struct DatasetObjectsEvent: Equatable {
  let emitterONo: OcaONo
  let changeType: OcaPropertyChangeType
  let datasetONos: Set<OcaONo>
}

/// The DatasetObjects events the device raises, in order: the device tells its event delegate
/// of each before fanning it out.
private final class DatasetObjectsEvents: OcaDeviceEventDelegate, @unchecked Sendable {
  private var _events = [DatasetObjectsEvent]()
  private let lock = NSLock()

  /// The events since the last call.
  func next() -> [DatasetObjectsEvent] {
    lock.withLock {
      defer { _events.removeAll() }
      return _events
    }
  }

  func onEvent(_ event: OcaEvent, parameters: OcaEventParameters) async {
    typealias Data37 = OcaPropertyChangedEventData<[OcaObjectIdentification]>
    guard parameters.propertyID == OcaPropertyID("3.7"),
          let data = try? parameters.encoded(as: .ocp1),
          let decoded = try? Ocp1Decoder().decode(Data37.self, from: data)
    else { return }
    let recorded = DatasetObjectsEvent(
      emitterONo: event.emitterONo,
      changeType: decoded.changeType,
      datasetONos: Set(decoded.propertyValue.map(\.oNo))
    )
    lock.withLock { _events.append(recorded) }
  }

  func onControllerExpiry(_ controller: OcaController) async {}
}

/// Datasets held in memory, numbered from 20000, by a provider that never calls
/// `notifyDatasetObjectsChanged(for:_:device:)`.
private actor SilentDatasetProvider: OcaDatasetStorageProvider {
  private weak var device: OcaDevice?
  private var datasets = [OcaONo: SwiftOCADevice.OcaDataset]()
  private var nextONo: OcaONo = 20000

  init(device: OcaDevice) {
    self.device = device
  }

  func getDatasetObjects(targetONo: OcaONo?) async throws -> [SwiftOCADevice.OcaDataset] {
    datasets.keys.sorted().compactMap { datasets[$0] }
  }

  func resolve(targetONo: OcaONo?, datasetONo: OcaONo) async throws -> SwiftOCADevice.OcaDataset {
    guard let dataset = datasets[datasetONo] else { throw Ocp1Error.objectNotPresent(datasetONo) }
    return dataset
  }

  func find(
    targetONo: OcaONo?,
    name: OcaString,
    nameComparisonType: OcaStringComparisonType
  ) async throws -> [SwiftOCADevice.OcaDataset] {
    []
  }

  func construct(
    classID: OcaClassID,
    targetONo: OcaONo,
    datasetONo: OcaONo?,
    name: OcaString,
    type: OcaMimeType,
    maxSize: OcaUint64,
    initialContents: OcaLongBlob,
    controller: OcaController?
  ) async throws -> OcaONo {
    let oNo = nextONo
    nextONo += 1
    datasets[oNo] = try await SwiftOCADevice.OcaDataset(
      owner: targetONo, name: name, type: type, objectNumber: oNo, deviceDelegate: device
    )
    return oNo
  }

  func duplicate(
    oldDatasetONo: OcaONo,
    oldTargetONo: OcaONo?,
    newDatasetONo: OcaONo?,
    newTargetONo: OcaONo,
    newName: OcaString,
    newMaxSize: OcaUint64,
    controller: OcaController?
  ) async throws -> OcaONo {
    throw Ocp1Error.status(.notImplemented)
  }

  func delete(targetONo: OcaONo?, datasetONo: OcaONo) async throws {
    guard let dataset = datasets.removeValue(forKey: datasetONo) else {
      throw Ocp1Error.objectNotPresent(datasetONo)
    }
    try await device?.deregister(object: dataset)
  }
}

/// The storage provider sends a block's DatasetObjects, once for each change to its datasets,
/// with the change type it knows; the block sends none of its own.
final class BlockDatasetObjectsEventTests: XCTestCase {
  private var basePath: URL!

  override func setUp() async throws {
    basePath = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  override func tearDown() async throws {
    if let basePath {
      try? FileManager.default.removeItem(at: basePath)
    }
  }

  /// Constructs, stores parameters into (StoreCurrentParameterData), duplicates to the same
  /// block and to another, and deletes through the root block, checking the events after each.
  @OcaDevice
  private static func checkEvents(
    providedBy makeProvider: (OcaDevice) throws -> any OcaDatasetStorageProvider
  ) async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let block: DeviceBlock = await device.rootBlock
    let other = try await DeviceBlock(role: "Other", deviceDelegate: device)
    let events = DatasetObjectsEvents()
    await device.setEventDelegate(events)
    let provider = try makeProvider(device)
    await device.setDatasetStorageProvider(provider)

    let oNo = try await block.constructDataset(
      classID: SwiftOCADevice.OcaDataset.classID, name: "Intro", type: OcaParamDatasetMimeType,
      maxSize: .max, initialContents: .init(), controller: nil
    )
    XCTAssertEqual(
      events.next(),
      [.init(emitterONo: block.objectNumber, changeType: .itemAdded, datasetONos: [oNo])]
    )

    // new contents, not a new list: DatasetObjects is unchanged, so nothing is sent
    try await block.storeCurrentParameterData(oNo: oNo, from: nil)
    XCTAssertEqual(events.next(), [])

    let copy = try await block.duplicateDataset(
      oldONo: oNo, targetBlockONo: block.objectNumber, newName: "Ident", newMaxSize: .max,
      controller: nil
    )
    XCTAssertEqual(
      events.next(),
      [.init(emitterONo: block.objectNumber, changeType: .itemAdded, datasetONos: [oNo, copy])]
    )

    let elsewhere = try await block.duplicateDataset(
      oldONo: oNo, targetBlockONo: other.objectNumber, newName: "Elsewhere", newMaxSize: .max,
      controller: nil
    )
    XCTAssertEqual(
      events.next(),
      [.init(emitterONo: other.objectNumber, changeType: .itemAdded, datasetONos: [elsewhere])]
    )

    try await block.delete(datasetObject: provider.resolve(
      targetONo: block.objectNumber,
      datasetONo: copy
    ))
    XCTAssertEqual(
      events.next(),
      [.init(emitterONo: block.objectNumber, changeType: .itemDeleted, datasetONos: [oNo])]
    )
  }

  func testTheFileProviderSendsOneEventForEachChange() async throws {
    let basePath = try XCTUnwrap(basePath)
    try await Self.checkEvents { device in
      try OcaFileDatasetStorageProvider(basePath: basePath, deviceDelegate: device)
    }
  }

  #if canImport(SQLite)
  func testTheSQLiteProviderSendsOneEventForEachChange() async throws {
    let path = basePath.path() + ".sqlite3"
    defer { try? FileManager.default.removeItem(atPath: path) }
    try await Self.checkEvents { device in
      try OcaSQLiteDatasetStorageProvider(path: path, deviceDelegate: device)
    }
  }
  #endif

  /// A provider that does not call the helper has no events sent: the block sends none.
  @OcaDevice
  func testTheBlockSendsNoEventOfItsOwn() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let block: DeviceBlock = await device.rootBlock
    let events = DatasetObjectsEvents()
    await device.setEventDelegate(events)
    let provider = SilentDatasetProvider(device: device)
    await device.setDatasetStorageProvider(provider)

    let oNo = try await block.constructDataset(
      classID: SwiftOCADevice.OcaDataset.classID, name: "Intro", type: OcaParamDatasetMimeType,
      maxSize: .max, initialContents: .init(), controller: nil
    )
    try await block.delete(datasetObject: provider.resolve(
      targetONo: block.objectNumber,
      datasetONo: oNo
    ))
    XCTAssertEqual(events.next(), [])
  }

  /// The helper sends a block's DatasetObjects, and nothing for an object that is not a block.
  @OcaDevice
  func testTheHelperSendsOnlyForABlock() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let events = DatasetObjectsEvents()
    await device.setEventDelegate(events)
    let provider = SilentDatasetProvider(device: device)

    await provider.notifyDatasetObjectsChanged(for: OcaDeviceManagerONo, .itemAdded, device: device)
    await provider.notifyDatasetObjectsChanged(for: OcaRootBlockONo, .itemAdded, device: device)
    XCTAssertEqual(events.next().map(\.emitterONo), [OcaRootBlockONo])
  }
}
#endif
