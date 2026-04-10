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
import SQLite
import SwiftOCA

enum OcaSQLiteDatasetSchema {
  static let tableName = "oca_datasets"

  static let colDatasetONo = "dataset_ono"
  static let colTargetONo = "target_ono"
  static let colName = "name"
  static let colMimeType = "mime_type"
  static let colData = "data"
}

final class SendableConnectionBox: @unchecked Sendable {
  let connection: Connection

  init(_ connection: Connection) {
    self.connection = connection
  }
}

final class OcaSQLiteDataset: OcaDataset, @unchecked Sendable {
  private let _db: SendableConnectionBox
  private var db: Connection { _db.connection }

  private final class IOSessionData {
    var buffer: Data
    let isWrite: Bool

    init(data: Data, isWrite: Bool) {
      buffer = data
      self.isWrite = isWrite
    }
  }

  private init(
    db: SendableConnectionBox,
    owner: OcaONo,
    name: OcaString,
    type: OcaMimeType,
    readOnly: OcaBoolean,
    maxSize: OcaUint64 = .max,
    objectNumber: OcaONo,
    lockable: OcaBoolean = true,
    role: OcaString,
    deviceDelegate: OcaDevice? = nil
  ) async throws {
    _db = db
    try await super.init(
      owner: owner,
      name: name,
      type: type,
      readOnly: readOnly,
      maxSize: maxSize,
      objectNumber: objectNumber,
      lockable: lockable,
      role: role,
      deviceDelegate: deviceDelegate,
      addToRootBlock: false
    )
  }

  convenience init(
    db: SendableConnectionBox,
    datasetONo: OcaONo,
    targetONo: OcaONo,
    name: OcaString,
    mimeType: OcaMimeType,
    deviceDelegate: OcaDevice? = nil
  ) async throws {
    try await self.init(
      db: db,
      owner: targetONo,
      name: name,
      type: mimeType,
      readOnly: false,
      objectNumber: datasetONo,
      role: "SQLite Dataset \(name)",
      deviceDelegate: deviceDelegate
    )
  }

  required nonisolated init(from decoder: Decoder) throws {
    fatalError("init(from:) has not been implemented")
  }

  required init(
    objectNumber: OcaONo? = nil,
    lockable: OcaBoolean = true,
    role: OcaString? = nil,
    deviceDelegate: OcaDevice? = nil,
    addToRootBlock: Bool = true
  ) async throws {
    fatalError("not supported")
  }

  private func loadData() throws -> Data {
    let datasets = Table(OcaSQLiteDatasetSchema.tableName)
    let colDatasetONo = SQLite.Expression<Int64>(OcaSQLiteDatasetSchema.colDatasetONo)
    let colData = SQLite.Expression<String?>(OcaSQLiteDatasetSchema.colData)

    let query = datasets.filter(colDatasetONo == Int64(objectNumber))
    guard let row = try db.pluck(query) else {
      throw Ocp1Error.unknownDataset
    }
    guard let json = row[colData] else {
      return Data()
    }
    return Data(json.utf8)
  }

  private func storeData(_ data: Data) throws {
    let datasets = Table(OcaSQLiteDatasetSchema.tableName)
    let colDatasetONo = SQLite.Expression<Int64>(OcaSQLiteDatasetSchema.colDatasetONo)
    let colData = SQLite.Expression<String?>(OcaSQLiteDatasetSchema.colData)

    let json = String(data: data, encoding: .utf8)
    try db.run(datasets.filter(colDatasetONo == Int64(objectNumber)).update(colData <- json))
  }

  override func openRead(
    lockState: OcaLockState,
    controller: OcaController?
  ) async throws -> (OcaUint64, OcaIOSessionHandle) {
    let data = try loadData()
    let session = IOSessionData(data: data, isWrite: false)
    let handle = try allocateIOSessionHandle(with: session, controller: controller)
    return (OcaUint64(data.count), handle)
  }

  override func openWrite(
    lockState: OcaLockState,
    controller: OcaController?
  ) async throws -> (OcaUint64, OcaIOSessionHandle) {
    let session = IOSessionData(data: Data(), isWrite: true)
    let handle = try allocateIOSessionHandle(with: session, controller: controller)
    return (maxSize, handle)
  }

  override func close(handle: OcaIOSessionHandle, controller: OcaController?) async throws {
    let session: IOSessionData = try resolveIOSessionHandle(handle, controller: controller)
    if session.isWrite {
      try storeData(session.buffer)
    }
    try releaseIOSessionHandle(handle, controller: controller)
  }

  override func read(
    handle: OcaIOSessionHandle,
    position: OcaUint64,
    partSize: OcaUint64,
    controller: OcaController?
  ) async throws -> (OcaBoolean, OcaLongBlob) {
    let session: IOSessionData = try resolveIOSessionHandle(handle, controller: controller)
    let dataCount = OcaUint64(session.buffer.count)
    guard position <= dataCount else {
      throw Ocp1Error.datasetReadFailed
    }
    let start = Int(position)
    let end = min(start + Int(partSize), session.buffer.count)
    let part = session.buffer[start..<end]
    let complete = OcaUint64(end) >= dataCount
    return (complete, .init(part))
  }

  override func write(
    handle: OcaIOSessionHandle,
    position: OcaUint64,
    part: OcaLongBlob,
    controller: OcaController?
  ) async throws {
    let session: IOSessionData = try resolveIOSessionHandle(handle, controller: controller)
    guard position + OcaUint64(part.count) <= maxSize else {
      throw Ocp1Error.arrayOrDataTooBig
    }
    let start = Int(position)
    if start >= session.buffer.count {
      session.buffer.append(contentsOf: part)
    } else {
      let end = start + part.count
      if end > session.buffer.count {
        session.buffer.count = end
      }
      session.buffer.replaceSubrange(start..<end, with: part)
    }
  }

  override func clear(handle: OcaIOSessionHandle, controller: OcaController?) async throws {
    let session: IOSessionData = try resolveIOSessionHandle(handle, controller: controller)
    session.buffer = Data()
  }

  override func getDataSetSizes() async throws -> (OcaUint64, OcaUint64) {
    let data = try loadData()
    return (OcaUint64(data.count), maxSize)
  }
}

#endif
