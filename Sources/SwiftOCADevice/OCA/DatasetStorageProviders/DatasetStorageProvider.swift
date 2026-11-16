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

import SwiftOCA

/// The storage of the device's datasets. The provider owns it, so it announces every change
/// to a block's datasets with `notifyDatasetObjectsChanged(for:_:device:)`; OcaBlock does not.
public protocol OcaDatasetStorageProvider: Actor {
  /// enumerate data objects in a block. This may include dataset objects that are not associated
  /// with the specific block,
  /// but can be applied because they share the same global type identifier
  func getDatasetObjects(targetONo: OcaONo?) async throws -> [OcaDataset]

  /// lookup a dataset by object number
  func resolve(
    targetONo: OcaONo?,
    datasetONo: OcaONo
  ) async throws -> OcaDataset

  /// lookup a dataset by name
  func find(
    targetONo: OcaONo?,
    name: OcaString,
    nameComparisonType: OcaStringComparisonType
  ) async throws -> [OcaDataset]

  @discardableResult
  func construct(
    classID: OcaClassID,
    targetONo: OcaONo,
    datasetONo: OcaONo?,
    name: OcaString,
    type: OcaMimeType,
    maxSize: OcaUint64,
    initialContents: OcaLongBlob,
    controller: OcaController?
  ) async throws -> OcaONo

  @discardableResult
  func duplicate(
    oldDatasetONo: OcaONo,
    oldTargetONo: OcaONo?,
    newDatasetONo: OcaONo?,
    newTargetONo: OcaONo,
    newName: OcaString,
    newMaxSize: OcaUint64,
    controller: OcaController?
  ) async throws -> OcaONo

  func delete(targetONo: OcaONo?, datasetONo: OcaONo) async throws
}

public extension OcaDatasetStorageProvider {
  /// Sends DatasetObjects (3.7) for the block `targetONo` of `device` after a `changeType`
  /// change to its datasets: `itemAdded`, `itemChanged` (a replacement or new contents) or
  /// `itemDeleted`. A provider must call it after every change it makes to a block's datasets,
  /// by any path, OcaBlock's own dataset methods included: the block sends none. Nothing is
  /// sent when `device` is nil or `targetONo` is not one of its blocks.
  func notifyDatasetObjectsChanged(
    for targetONo: OcaONo,
    _ changeType: OcaPropertyChangeType,
    device: OcaDevice?
  ) async {
    await device?.notifyDatasetObjectsChanged(for: targetONo, changeType)
  }
}

extension OcaDevice {
  /// Sends the block `targetONo`'s DatasetObjects, if it is a block of this device.
  func notifyDatasetObjectsChanged(
    for targetONo: OcaONo,
    _ changeType: OcaPropertyChangeType
  ) async {
    guard let block = objects[targetONo] as? any OcaBlockContainer else { return }
    await block.notifyDatasetObjectsChanged(changeType)
  }
}

#endif
