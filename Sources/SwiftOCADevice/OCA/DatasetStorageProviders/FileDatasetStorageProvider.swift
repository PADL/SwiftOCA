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
import SwiftOCA

public actor OcaFileDatasetStorageProvider: OcaDatasetStorageProvider {
  let basePath: URL
  let validDatasetONos: ClosedRange<OcaONo>
  let validBlockONos: Set<OcaONo>
  /// largest dataset, in bytes, that controllers may store; nil for no limit
  let maxDatasetSize: OcaUint64?
  /// largest the dataset files in `basePath` may grow to together, in bytes; nil for no limit
  let maxTotalSize: OcaUint64?
  weak var deviceDelegate: OcaDevice?

  private nonisolated var fileManager: FileManager {
    FileManager.default
  }

  private func list() throws -> Set<OcaFileDatasetDirEntry> {
    try OcaFileDatasetDirEntry.list(at: basePath)
  }

  private func allocateONo(targetONo: OcaONo?) throws -> OcaONo {
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
    maxDatasetSize: OcaUint64? = nil,
    maxTotalSize: OcaUint64? = nil,
    deviceDelegate: OcaDevice?
  ) throws {
    self.basePath = basePath
    self.validDatasetONos = validDatasetONos
    self.validBlockONos = validBlockONos
    self.maxDatasetSize = maxDatasetSize
    self.maxTotalSize = maxTotalSize
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
      return try await OcaFileDataset(
        dirEntry: dirEntry,
        maxSize: maxDatasetSize ?? .max,
        maxTotalSize: maxTotalSize,
        deviceDelegate: deviceDelegate
      )
    }
  }

  public func getDatasetObjects(
    targetONo: OcaONo?
  ) async throws -> [OcaDataset] {
    let list = try list()

    let entries = if let targetONo {
      list.filter { $0.target == targetONo }
    } else {
      list
    }

    return try await entries.asyncMap { @Sendable in try await dirEntryToDataSet($0) }
  }

  private func resolve(
    targetONo: OcaONo?,
    datasetONo: OcaONo
  ) async throws -> OcaFileDatasetDirEntry {
    guard let dirEntry = try list().first(where: {
      if let targetONo {
        precondition(targetONo != OcaInvalidONo)
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
    targetONo: OcaONo?,
    datasetONo: OcaONo
  ) async throws -> OcaDataset {
    let dirEntry: OcaFileDatasetDirEntry = try await resolve(
      targetONo: targetONo,
      datasetONo: datasetONo
    )
    return try await dirEntryToDataSet(dirEntry)
  }

  public func find(
    targetONo: OcaONo?,
    name: OcaString,
    nameComparisonType: OcaStringComparisonType
  ) async throws -> [OcaDataset] {
    try await list()
      .filter {
        if let targetONo {
          guard targetONo == $0.target else {
            return false
          }
        }
        return nameComparisonType.compare($0.name, name)
      }
      .asyncMap { @Sendable in try await dirEntryToDataSet($0) }
  }

  public func construct(
    classID: OcaClassID,
    targetONo: OcaONo,
    datasetONo: OcaONo?,
    name: OcaString,
    type: OcaMimeType,
    maxSize: OcaUint64,
    initialContents: SwiftOCA.OcaLongBlob,
    controller: OcaController?
  ) async throws -> OcaONo {
    guard classID.isSubclass(of: OcaDataset.classID) else {
      throw Ocp1Error.unknownDataset
    }
    // checked before the dataset file is created, so a rejected dataset leaves nothing behind
    guard OcaUint64(initialContents.count) <= maxDatasetSize ?? .max else {
      throw Ocp1Error.arrayOrDataTooBig
    }
    try checkTotalSize(adding: OcaUint64(initialContents.count))

    let oNo = try datasetONo ?? allocateONo(targetONo: targetONo)
    let dirEntry = try OcaFileDatasetDirEntry(
      basePath: basePath,
      oNo: oNo,
      target: targetONo,
      name: name,
      mimeType: type
    )
    let dataset = try await OcaFileDataset(
      dirEntry: dirEntry,
      maxSize: maxDatasetSize ?? .max,
      maxTotalSize: maxTotalSize,
      deviceDelegate: deviceDelegate
    )

    let (_, handle) = try await dataset.openWrite(lockState: .noLock, controller: controller)
    try await dataset.write(
      handle: handle,
      position: 0,
      part: initialContents,
      from: controller
    )
    try await dataset.close(handle: handle, from: controller)

    return oNo
  }

  public func duplicate(
    oldDatasetONo: OcaONo,
    oldTargetONo: OcaONo?,
    newDatasetONo: OcaONo?,
    newTargetONo: OcaONo,
    newName: OcaString,
    newMaxSize: OcaUint64,
    controller: OcaController?
  ) async throws -> SwiftOCA.OcaONo {
    let oldDirEntry: OcaFileDatasetDirEntry = try await resolve(
      targetONo: oldTargetONo,
      datasetONo: oldDatasetONo
    )
    let newONo = try allocateONo(targetONo: newTargetONo)
    let newDirEntry = try OcaFileDatasetDirEntry(
      basePath: basePath,
      oNo: newONo,
      target: newTargetONo,
      name: newName,
      mimeType: oldDirEntry.mimeType
    )
    let oldSize = try oldDirEntry.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    try checkTotalSize(adding: OcaUint64(oldSize))
    // FIXME: need to rewrite target object number
    try fileManager.copyItem(at: oldDirEntry.url, to: newDirEntry.url)
    return newONo
  }

  private func checkTotalSize(adding size: OcaUint64) throws {
    guard let maxTotalSize else { return }
    guard try fileDatasetUsage(at: basePath) + size <= maxTotalSize else {
      throw Ocp1Error.arrayOrDataTooBig
    }
  }

  public func delete(targetONo: OcaONo?, datasetONo: OcaONo) async throws {
    let dirEntry: OcaFileDatasetDirEntry = try await resolve(
      targetONo: targetONo,
      datasetONo: datasetONo
    )
    try fileManager.removeItem(at: dirEntry.url)
    try? await deviceDelegate?.deregister(objectNumber: datasetONo)
  }
}

#endif
