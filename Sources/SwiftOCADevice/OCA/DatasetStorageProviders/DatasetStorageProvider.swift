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

import SwiftOCA

public protocol OcaDatasetStorageProvider: Actor {
  /// enumerate data objects in a block. This may include dataset objects that are not associated
  /// with the specific block,
  /// but can be applied because they share the same global type identifier
  func getDatasetObjects(targetONo: OcaONo) async throws -> [OcaDataset]

  /// lookup a dataset by object number
  func resolve(
    targetONo: OcaONo,
    datasetONo: OcaONo,
  ) async throws -> OcaDataset

  /// lookup a dataset by name
  func find(
    targetONo: OcaONo,
    name: OcaString,
    nameComparisonType: OcaStringComparisonType,
  ) async throws -> [OcaDataset]

  func construct(
    classID: OcaClassID,
    targetONo: OcaONo,
    name: OcaString,
    type: OcaMimeType,
    maxSize: OcaUint64,
    initialContents: OcaLongBlob,
    controller: OcaController
  ) async throws -> OcaONo

  func duplicate(
    oldONo: OcaONo,
    oldTargetONo: OcaONo,
    newTargetONo: OcaONo,
    newName: OcaString,
    newMaxSize: OcaUint64,
    controller: OcaController
  ) async throws -> OcaONo

  func delete(targetONo: OcaONo, datasetONo: OcaONo) async throws
}
