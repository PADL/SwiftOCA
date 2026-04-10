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

public actor OcaSQLiteDatasetStorageProvider: OcaDatasetStorageProvider {
  private let _db: SendableConnectionBox
  let validDatasetONos: ClosedRange<OcaONo>
  let validBlockONos: Set<OcaONo>
  weak var deviceDelegate: OcaDevice?

  private var db: Connection { _db.connection }

  private let datasets = Table(OcaSQLiteDatasetSchema.tableName)
  private let colDatasetONo = SQLite.Expression<Int64>(OcaSQLiteDatasetSchema.colDatasetONo)
  private let colTargetONo = SQLite.Expression<Int64?>(OcaSQLiteDatasetSchema.colTargetONo)
  private let colName = SQLite.Expression<String>(OcaSQLiteDatasetSchema.colName)
  private let colMimeType = SQLite.Expression<String>(OcaSQLiteDatasetSchema.colMimeType)
  private let colData = SQLite.Expression<String?>(OcaSQLiteDatasetSchema.colData)

  public init(
    path: String,
    validDatasetONos: ClosedRange<OcaONo> = 0x10000...0x1FFFF,
    validBlockONos: Set<OcaONo> = [OcaRootBlockONo],
    deviceDelegate: OcaDevice?
  ) throws {
    let db = try Connection(path)
    try db.run("PRAGMA auto_vacuum = INCREMENTAL")
    _db = SendableConnectionBox(db)
    self.validDatasetONos = validDatasetONos
    self.validBlockONos = validBlockONos
    self.deviceDelegate = deviceDelegate

    let datasets = Table(OcaSQLiteDatasetSchema.tableName)
    let colDatasetONo = SQLite.Expression<Int64>(OcaSQLiteDatasetSchema.colDatasetONo)
    let colTargetONo = SQLite.Expression<Int64?>(OcaSQLiteDatasetSchema.colTargetONo)
    let colName = SQLite.Expression<String>(OcaSQLiteDatasetSchema.colName)
    let colMimeType = SQLite.Expression<String>(OcaSQLiteDatasetSchema.colMimeType)
    let colData = SQLite.Expression<String?>(OcaSQLiteDatasetSchema.colData)

    try db.run(datasets.create(ifNotExists: true) { t in
      t.column(colDatasetONo, primaryKey: true)
      t.column(colTargetONo)
      t.column(colName)
      t.column(colMimeType)
      t.column(colData)
    })
    try db.run(datasets.createIndex(colTargetONo, ifNotExists: true))
    try db.run(datasets.createIndex(colName, ifNotExists: true))
  }

  private func allocateONo() throws -> OcaONo {
    let existingONos = try Set(
      db.prepare(datasets.select(colDatasetONo)).map { OcaONo($0[colDatasetONo]) }
    )

    for oNo in validDatasetONos {
      if !existingONos.contains(oNo) {
        return oNo
      }
    }

    throw Ocp1Error.invalidDatasetONo
  }

  private struct DatasetRowInfo: Sendable {
    let datasetONo: OcaONo
    let targetONo: OcaONo
    let name: OcaString
    let mimeType: OcaMimeType
  }

  private func extractRowInfo(_ row: Row) -> DatasetRowInfo {
    DatasetRowInfo(
      datasetONo: OcaONo(row[colDatasetONo]),
      targetONo: row[colTargetONo].map { OcaONo($0) } ?? OcaInvalidONo,
      name: row[colName],
      mimeType: row[colMimeType]
    )
  }

  private func makeDataset(from info: DatasetRowInfo) async throws -> OcaSQLiteDataset {
    if let existingDataset = await deviceDelegate?.resolve(objectIdentification: .init(
      oNo: info.datasetONo,
      classIdentification: OcaSQLiteDataset.classIdentification
    )) as? OcaSQLiteDataset {
      return existingDataset
    }

    return try await OcaSQLiteDataset(
      db: _db,
      datasetONo: info.datasetONo,
      targetONo: info.targetONo,
      name: info.name,
      mimeType: info.mimeType,
      deviceDelegate: deviceDelegate
    )
  }

  public func getDatasetObjects(targetONo: OcaONo?) async throws -> [OcaDataset] {
    let query: Table = if let targetONo {
      datasets.filter(colTargetONo == Int64(targetONo) || colTargetONo == nil)
    } else {
      datasets
    }

    let rows = try Array(db.prepare(query)).map(extractRowInfo)
    var results = [OcaDataset]()
    for info in rows {
      try await results.append(makeDataset(from: info))
    }
    return results
  }

  public func resolve(
    targetONo: OcaONo?,
    datasetONo: OcaONo
  ) async throws -> OcaDataset {
    var query = datasets.filter(colDatasetONo == Int64(datasetONo))
    if let targetONo {
      precondition(targetONo != OcaInvalidONo)
      query = query.filter(colTargetONo == Int64(targetONo) || colTargetONo == nil)
    }

    guard let row = try db.pluck(query) else {
      throw Ocp1Error.unknownDataset
    }

    return try await makeDataset(from: extractRowInfo(row))
  }

  public func find(
    targetONo: OcaONo?,
    name: OcaString,
    nameComparisonType: OcaStringComparisonType
  ) async throws -> [OcaDataset] {
    var query = datasets.select(*)

    if let targetONo {
      query = query.filter(colTargetONo == Int64(targetONo) || colTargetONo == nil)
    }

    let rows = try Array(db.prepare(query))
      .filter { nameComparisonType.compare($0[colName], name) }
      .map(extractRowInfo)

    var results = [OcaDataset]()
    for info in rows {
      try await results.append(makeDataset(from: info))
    }
    return results
  }

  @discardableResult
  public func construct(
    classID: OcaClassID,
    targetONo: OcaONo,
    datasetONo: OcaONo?,
    name: OcaString,
    type: OcaMimeType,
    maxSize: OcaUint64,
    initialContents: OcaLongBlob,
    controller: OcaController?
  ) async throws -> OcaONo {
    guard classID.isSubclass(of: OcaDataset.classID) else {
      throw Ocp1Error.unknownDataset
    }

    let oNo = try datasetONo ?? allocateONo()
    let json = String(data: Data(initialContents), encoding: .utf8)

    try db.run(datasets.insert(
      colDatasetONo <- Int64(oNo),
      colTargetONo <- Int64(targetONo),
      colName <- name,
      colMimeType <- type,
      colData <- json
    ))

    let dataset = try await OcaSQLiteDataset(
      db: _db,
      datasetONo: oNo,
      targetONo: targetONo,
      name: name,
      mimeType: type,
      deviceDelegate: deviceDelegate
    )

    _ = dataset

    return oNo
  }

  @discardableResult
  public func duplicate(
    oldDatasetONo: OcaONo,
    oldTargetONo: OcaONo?,
    newDatasetONo: OcaONo?,
    newTargetONo: OcaONo,
    newName: OcaString,
    newMaxSize: OcaUint64,
    controller: OcaController?
  ) async throws -> OcaONo {
    var query = datasets.filter(colDatasetONo == Int64(oldDatasetONo))
    if let oldTargetONo {
      query = query.filter(colTargetONo == Int64(oldTargetONo) || colTargetONo == nil)
    }

    guard let oldRow = try db.pluck(query) else {
      throw Ocp1Error.unknownDataset
    }

    let newONo = try newDatasetONo ?? allocateONo()

    var newData = oldRow[colData]
    let oldRowTargetONo = oldRow[colTargetONo].map { OcaONo($0) }
    if let existingData = newData, oldRowTargetONo != newTargetONo {
      guard let data = existingData.data(using: .utf8),
            var jsonObject = try JSONSerialization
            .jsonObject(with: data) as? [String: Any]
      else {
        throw Ocp1Error.invalidDatasetFormat
      }
      if jsonObject[objectNumberJSONKey] != nil {
        jsonObject[objectNumberJSONKey] = newTargetONo
        let updatedData = try JSONSerialization.data(withJSONObject: jsonObject)
        newData = String(data: updatedData, encoding: .utf8)
      }
    }

    try db.run(datasets.insert(
      colDatasetONo <- Int64(newONo),
      colTargetONo <- Int64(newTargetONo),
      colName <- newName,
      colMimeType <- oldRow[colMimeType],
      colData <- newData
    ))

    return newONo
  }

  public func delete(targetONo: OcaONo?, datasetONo: OcaONo) async throws {
    var query = datasets.filter(colDatasetONo == Int64(datasetONo))
    if let targetONo {
      query = query.filter(colTargetONo == Int64(targetONo) || colTargetONo == nil)
    }

    guard try db.run(query.delete()) > 0 else {
      throw Ocp1Error.unknownDataset
    }

    try db.run("PRAGMA incremental_vacuum")

    try? await deviceDelegate?.deregister(objectNumber: datasetONo)
  }
}

#endif
