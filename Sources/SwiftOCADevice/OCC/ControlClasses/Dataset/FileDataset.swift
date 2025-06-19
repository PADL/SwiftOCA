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

extension OcaMimeType {
  var fileExtension: String {
    get throws {
      switch self {
      case OcaParamDatasetMimeType:
        return ".param.json.gz"
      case OcaPatchDatasetMimeType:
        return ".patch.json.gz"
      default:
        throw Ocp1Error.unknownDatasetMimeType
      }
    }
  }

  init(filePath: String) throws {
    if filePath.hasSuffix(".param.json.gz") {
      self = OcaParamDatasetMimeType
    } else if filePath.hasSuffix(".patch.json.gz") {
      self = OcaPatchDatasetMimeType
    } else {
      throw Ocp1Error.unknownDatasetMimeType
    }
  }
}

struct OcaFileDatasetDirEntry: Hashable, CustomStringConvertible {
  static func == (lhs: OcaFileDatasetDirEntry, rhs: OcaFileDatasetDirEntry) -> Bool {
    try! lhs.absolutePath == rhs.absolutePath
  }

  let basePath: URL
  let oNo: OcaONo
  let target: OcaONo
  let name: String
  let mimeType: OcaMimeType

  public var description: String {
    try! String(describing: url)
  }

  static func list(at basePath: URL) throws -> Set<Self> {
    let fileManager = FileManager.default
    var entries = Set<Self>()

    for path in try fileManager.contentsOfDirectory(at: basePath, includingPropertiesForKeys: nil) {
      if let entry = try? Self(at: path) { entries.insert(entry) }
    }

    return entries
  }

  init(basePath: URL, oNo: OcaONo, target: OcaONo, name: String, mimeType: OcaMimeType) throws {
    guard !name.contains("$") else {
      throw Ocp1Error.invalidDatasetName
    }

    self.basePath = basePath
    self.oNo = oNo
    self.target = target
    self.name = name
    self.mimeType = mimeType
  }

  init(at url: URL) throws {
    guard url.isFileURL else {
      throw Ocp1Error.invalidDatasetName
    }
    try self.init(atPath: url.lastPathComponent, relativeTo: url.deletingLastPathComponent())
  }

  init(atPath path: String, relativeTo basePath: URL) throws {
    let mimeType = try OcaMimeType(filePath: path)

    let components = path.split(separator: "$", maxSplits: 3)
    guard components.count == 3 else {
      throw Ocp1Error.invalidDatasetName
    }

    guard let oNo = OcaONo(components[0], radix: 16),
          let target = OcaONo(components[1], radix: 16)
    else {
      throw Ocp1Error.invalidDatasetName
    }

    let name = try components[2].dropLast(mimeType.fileExtension.count)

    try self.init(
      basePath: basePath,
      oNo: oNo,
      target: target,
      name: String(name),
      mimeType: mimeType
    )
  }

  var url: URL {
    get throws {
      try basePath.appending(path: relativePath)
    }
  }

  var absolutePath: String {
    get throws {
      guard let absolutePath = try? url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
      else {
        return try url.path()
      }
      return absolutePath
    }
  }

  var attributes: [FileAttributeKey: Any] {
    get throws {
      try FileManager.default.attributesOfItem(atPath: url.path())
    }
  }

  var lastModificationTime: OcaTime {
    guard let time = try? (attributes[.modificationDate] as? Date) else {
      return .init()
    }
    return time.ocaTime
  }

  var size: OcaUint64 {
    guard let size = try? attributes[.size] as? NSNumber else {
      return 0
    }
    return size.uint64Value
  }

  var relativePath: String {
    get throws {
      let oNoString = String(format: "%08x", oNo)
      let targetString = String(format: "%08x", target)

      return try "\(oNoString)$\(targetString)$\(name)\(mimeType.fileExtension)"
    }
  }
}

final class OcaFileDataset: OcaDataset, OcaCompressibleDataset, @unchecked Sendable {
  let basePath: URL

  private init(
    basePath: URL,
    owner: OcaONo,
    name: OcaString,
    type: OcaMimeType,
    readOnly: OcaBoolean,
    lastModificationTime: OcaTime = .now,
    maxSize: OcaUint64 = .max,
    objectNumber: OcaONo,
    lockable: OcaBoolean = true,
    role: OcaString,
    deviceDelegate: OcaDevice? = nil
  ) async throws {
    self.basePath = basePath
    try await super.init(
      owner: owner,
      name: name,
      type: type,
      readOnly: readOnly,
      lastModificationTime: lastModificationTime,
      maxSize: maxSize,
      objectNumber: objectNumber,
      lockable: lockable,
      role: role,
      deviceDelegate: deviceDelegate,
      addToRootBlock: false
    )
  }

  convenience init(
    dirEntry: OcaFileDatasetDirEntry,
    deviceDelegate: OcaDevice? = nil
  ) async throws {
    try await self.init(
      basePath: dirEntry.basePath,
      owner: dirEntry.target,
      name: dirEntry.name,
      type: dirEntry.mimeType,
      readOnly: false,
      lastModificationTime: dirEntry.lastModificationTime,
      objectNumber: dirEntry.oNo,
      role: "File Dataset \(dirEntry)",
      deviceDelegate: deviceDelegate
    )
  }

  public required nonisolated init(from decoder: Decoder) throws {
    fatalError("init(from:) has not been implemented")
  }

  var dirEntry: OcaFileDatasetDirEntry {
    get throws {
      try OcaFileDatasetDirEntry(
        basePath: basePath,
        oNo: objectNumber,
        target: owner,
        name: name,
        mimeType: type
      )
    }
  }

  override func openRead(
    lockState: OcaLockState,
    controller: OcaController?
  ) async throws -> (OcaUint64, OcaIOSessionHandle) {
    let dirEntry = try dirEntry
    let fileHandle = try FileHandle(forReadingFrom: dirEntry.url)
    let handle = try allocateIOSessionHandle(with: fileHandle, controller: controller)
    return (dirEntry.size, handle)
  }

  override func openWrite(
    lockState: OcaLockState,
    controller: OcaController?
  ) async throws -> (OcaUint64, OcaIOSessionHandle) {
    let dirEntry = try dirEntry
    try FileManager.default.createFile(
      atPath: dirEntry.absolutePath,
      contents: nil,
      attributes: nil
    )
    let fileHandle = try FileHandle(forWritingTo: dirEntry.url)
    let handle = try allocateIOSessionHandle(with: fileHandle, controller: controller)
    return (maxSize, handle)
  }

  override func close(handle: OcaIOSessionHandle, controller: OcaController?) async throws {
    let fileHandle: FileHandle = try resolveIOSessionHandle(handle, controller: controller)
    try? fileHandle.synchronize()
    try fileHandle.close()
    try releaseIOSessionHandle(handle, controller: controller)
  }

  override func read(
    handle: OcaIOSessionHandle,
    position: OcaUint64,
    partSize: OcaUint64,
    controller: OcaController?
  ) async throws -> (OcaBoolean, OcaLongBlob) {
    let fileHandle: FileHandle = try resolveIOSessionHandle(handle, controller: controller)
    do {
      try fileHandle.seek(toOffset: position)
      guard let data = try fileHandle.read(upToCount: Int(partSize)) else {
        throw Ocp1Error.datasetReadFailed
      }
      let complete = fileHandle.availableData.count == 0
      return (complete, .init(data))
    } catch {
      throw Ocp1Error.datasetReadFailed
    }
  }

  override func write(
    handle: OcaIOSessionHandle,
    position: OcaUint64,
    part: OcaLongBlob,
    controller: OcaController?
  ) async throws {
    let fileHandle: FileHandle = try resolveIOSessionHandle(handle, controller: controller)
    do {
      try fileHandle.seek(toOffset: position)
      try fileHandle.write(contentsOf: part)
      try fileHandle.truncate(atOffset: position + UInt64(part.count))
    } catch {
      throw Ocp1Error.datasetWriteFailed
    }
  }

  override func clear(handle: OcaIOSessionHandle, controller: OcaController?) async throws {
    let fileHandle: FileHandle = try resolveIOSessionHandle(handle, controller: controller)
    do {
      try fileHandle.seek(toOffset: 0)
      try fileHandle.truncate(atOffset: 0)
    } catch {
      throw Ocp1Error.datasetWriteFailed
    }
  }

  override func getDataSetSizes() async throws -> (OcaUint64, OcaUint64) {
    try (dirEntry.size, maxSize)
  }
}
