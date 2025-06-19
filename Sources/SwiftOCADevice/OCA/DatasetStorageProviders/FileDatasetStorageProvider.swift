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

import Foundation
import SwiftOCA

public actor OcaFileDatasetStorageProvider: OcaDatasetStorageProvider {
  let basePath: URL
  let validDatasetONos: ClosedRange<OcaONo>
  let validBlockONos: Set<OcaONo>
  let objectToDatasetONoMap: [OcaONo: OcaONo]
  weak var deviceDelegate: OcaDevice?

  private nonisolated var fileManager: FileManager {
    FileManager.default
  }

  private func list() throws -> Set<OcaFileDatasetDirEntry> {
    try OcaFileDatasetDirEntry.list(at: basePath)
  }

  private func allocateONo(targetONo: OcaONo) throws -> OcaONo {
    if targetONo != OcaInvalidONo, let oNo = objectToDatasetONoMap[targetONo] {
      return oNo
    }
    let existingONos = (try? list().map(\.oNo)) ?? []

    for oNo in validDatasetONos {
      if !existingONos.contains(oNo) {
        return oNo
      }
    }

    throw Ocp1Error.invalidDatasetONo
  }

  public init(
    basePath: URL,
    validDatasetONos: ClosedRange<OcaONo> = 0x10000...0x1FFFF,
    validBlockONos: Set<OcaONo> = [OcaRootBlockONo],
    objectToDatasetONoMap: [OcaONo: OcaONo] = .init(),
    deviceDelegate: OcaDevice?
  ) throws {
    self.basePath = basePath
    self.validDatasetONos = validDatasetONos
    self.validBlockONos = validBlockONos
    self.objectToDatasetONoMap = objectToDatasetONoMap
    self.deviceDelegate = deviceDelegate

    if !fileManager.fileExists(atPath: basePath.path()) {
      try fileManager.createDirectory(at: basePath, withIntermediateDirectories: true)
    }
  }

  private func dirEntryToDataSet(_ dirEntry: OcaFileDatasetDirEntry) async throws
    -> OcaFileDataset
  {
    if let existingFileDataset = await deviceDelegate?.resolve(objectIdentification: .init(
      oNo: dirEntry.oNo,
      classIdentification: OcaFileDataset.classIdentification
    )) as? OcaFileDataset {
      guard try await existingFileDataset.dirEntry == dirEntry else {
        throw Ocp1Error.datasetAlreadyExists
      }
      return existingFileDataset
    } else {
      return try await OcaFileDataset(dirEntry: dirEntry, deviceDelegate: deviceDelegate)
    }
  }

  public func getDatasetObjects(
    targetONo oNo: OcaONo
  ) async throws -> [OcaDataset] {
    let entries = try list().filter { oNo != OcaInvalidONo ? $0.target == oNo : true }
    return try await entries.asyncMap { try await dirEntryToDataSet($0) }
  }

  private func resolve(
    targetONo: OcaONo,
    datasetONo: OcaONo
  ) async throws -> OcaFileDatasetDirEntry {
    if targetONo != OcaInvalidONo, let oNo = objectToDatasetONoMap[targetONo], oNo != datasetONo {
      throw Ocp1Error.datasetAlreadyExists
    }
    guard let dirEntry = try list().first(where: {
      if targetONo != OcaInvalidONo {
        guard targetONo == $0.target else {
          return false
        }
      }
      return datasetONo == $0.oNo
    }) else {
      throw Ocp1Error.unknownDataset
    }

    return dirEntry
  }

  public func resolve(
    targetONo: OcaONo,
    datasetONo: OcaONo
  ) async throws -> OcaDataset {
    let dirEntry: OcaFileDatasetDirEntry = try await resolve(
      targetONo: targetONo,
      datasetONo: datasetONo
    )
    return try await dirEntryToDataSet(dirEntry)
  }

  public func find(
    targetONo: OcaONo,
    name: OcaString,
    nameComparisonType: OcaStringComparisonType,
  ) async throws -> [OcaDataset] {
    try await list()
      .filter {
        if targetONo != OcaInvalidONo {
          guard targetONo == $0.target else {
            return false
          }
        }
        return nameComparisonType.compare($0.name, name)
      }
      .asyncMap { try await dirEntryToDataSet($0) }
  }

  public func construct(
    classID: OcaClassID,
    targetONo: OcaONo,
    name: OcaString,
    type: OcaMimeType,
    maxSize: OcaUint64,
    initialContents: SwiftOCA.OcaLongBlob,
    controller: OcaController
  ) async throws -> OcaONo {
    guard classID.isSubclass(of: OcaDataset.classID) else {
      throw Ocp1Error.unknownDataset
    }

    let oNo = try allocateONo(targetONo: targetONo)
    let dirEntry = try OcaFileDatasetDirEntry(
      basePath: basePath,
      oNo: oNo,
      target: targetONo,
      name: name,
      mimeType: type
    )
    let dataset = try await OcaFileDataset(dirEntry: dirEntry, deviceDelegate: deviceDelegate)

    let (_, handle) = try await dataset.openWrite(lockState: .noLock, controller: controller)
    try await dataset.write(
      handle: handle,
      position: 0,
      part: initialContents,
      controller: controller
    )
    try await dataset.close(handle: handle, controller: controller)

    return oNo
  }

  public func duplicate(
    oldONo: OcaONo,
    oldTargetONo: OcaONo,
    newTargetONo: OcaONo,
    newName: OcaString,
    newMaxSize: OcaUint64,
    controller: OcaController
  ) async throws -> SwiftOCA.OcaONo {
    let oldDirEntry: OcaFileDatasetDirEntry = try await resolve(
      targetONo: oldTargetONo,
      datasetONo: oldONo
    )
    let newONo = try allocateONo(targetONo: newTargetONo)
    let newDirEntry = try OcaFileDatasetDirEntry(
      basePath: basePath,
      oNo: newONo,
      target: newTargetONo,
      name: newName,
      mimeType: oldDirEntry.mimeType
    )
    // FIXME: need to rewrite target object number
    try fileManager.copyItem(at: oldDirEntry.url, to: newDirEntry.url)
    return newONo
  }

  public func delete(targetONo: OcaONo, datasetONo: OcaONo) async throws {
    let dirEntry: OcaFileDatasetDirEntry = try await resolve(
      targetONo: targetONo,
      datasetONo: datasetONo
    )
    try fileManager.removeItem(at: dirEntry.url)
    try? await deviceDelegate?.deregister(objectNumber: datasetONo)
  }
}
