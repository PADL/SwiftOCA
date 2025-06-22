//
// Copyright (c) 2024-2025 PADL Software Pty Ltd
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
#if canImport(Gzip)
import Gzip
#endif
@_spi(SwiftOCAPrivate)
import SwiftOCA

let objectNumberJSONKey = "_oNo"
let classIDJSONKey = "_classID"

// for datasets, these keys are merged with the top-level JSON object for validation
let datasetVersionJSONKey = "_version"
let datasetDeviceModelJSONKey = "_deviceModel"
let datasetMimeTypeJSONKey = "_mimeType"
let datasetParamDatasetsJSONKey = "_paramDatasets"

let OcaJsonDatasetVersion: OcaUint32 = 1

func _getObjectNumberFromJsonObject(jsonObject: [String: Sendable]) throws -> OcaONo {
  guard let objectNumber = jsonObject[objectNumberJSONKey] as? OcaONo,
        objectNumber != OcaInvalidONo
  else {
    throw Ocp1Error.status(.badONo)
  }

  return objectNumber
}

public extension OcaRoot {
  struct SerializationFlags: OptionSet, Sendable {
    public typealias RawValue = UInt

    public let rawValue: RawValue

    public init(rawValue: RawValue) {
      self.rawValue = rawValue
    }

    public static let ignoreEncodingErrors = SerializationFlags(rawValue: 1 << 0)
  }

  struct DeserializationFlags: OptionSet, Sendable {
    public typealias RawValue = UInt

    public let rawValue: RawValue

    public init(rawValue: RawValue) {
      self.rawValue = rawValue
    }

    public static let ignoreDecodingErrors = DeserializationFlags(rawValue: 1 << 0)
    public static let ignoreMissingProperties = DeserializationFlags(rawValue: 1 << 1)
    public static let ignoreUnknownObjectNumbers = DeserializationFlags(rawValue: 1 << 2)
    public static let ignoreObjectClassMismatches = DeserializationFlags(rawValue: 1 << 3)

    public static let ignoreAllErrors: DeserializationFlags = [
      .ignoreDecodingErrors,
      .ignoreMissingProperties,
      .ignoreUnknownObjectNumbers,
      .ignoreObjectClassMismatches,
    ]
  }

  typealias SerializationFilterFunction = @Sendable (
    OcaRoot,
    OcaPropertyID,
    Codable & Sendable
  ) -> Bool
}

public extension OcaDevice {
  @discardableResult
  func deserialize(
    jsonObject: [String: Sendable],
    flags: OcaRoot.DeserializationFlags = []
  ) async throws -> OcaRoot {
    let objectNumber = try _getObjectNumberFromJsonObject(jsonObject: jsonObject)

    guard let object = objects[objectNumber] else {
      logger.warning("root object \(objectNumber.oNoString) not present, cannot deserialize")
      throw Ocp1Error.objectNotPresent(objectNumber)
    }

    try await object.deserialize(jsonObject: jsonObject, flags: flags)

    return object
  }
}

extension OcaModelGUID {
  var scalarValue: OcaUint64 {
    OcaUint64(mfrCode.id.0 << 48) |
      OcaUint64(mfrCode.id.1 << 40) |
      OcaUint64(mfrCode.id.2 << 32) |
      OcaUint64(modelCode)
  }
}

extension OcaBlock {
  func serializeParameterDataset() async throws -> [String: any Sendable] {
    var root = try serialize(flags: [], isIncluded: datasetFilter)

    root[datasetVersionJSONKey] = OcaJsonDatasetVersion
    root[datasetDeviceModelJSONKey] = await deviceDelegate?.deviceManager?.modelGUID.scalarValue
    root[datasetMimeTypeJSONKey] = OcaParamDatasetMimeType

    return root
  }

  func deserializeParameterDataset(_ parameters: [String: any Sendable]) async throws {
    guard let version = parameters[datasetVersionJSONKey] as? OcaUint32,
          version == OcaJsonDatasetVersion
    else {
      throw Ocp1Error.unknownDatasetVersion
    }
    guard let deviceModel = parameters[datasetDeviceModelJSONKey] as? OcaUint64,
          await deviceModel == deviceDelegate?.deviceManager?.modelGUID.scalarValue
    else {
      throw Ocp1Error.datasetDeviceMismatch
    }
    guard let mimeType = parameters[datasetMimeTypeJSONKey] as? String,
          mimeType == OcaParamDatasetMimeType
    else {
      throw Ocp1Error.datasetMimeTypeMismatch
    }
    do {
      try await deserialize(jsonObject: parameters, flags: .ignoreMissingProperties)
    } catch is DecodingError {
      throw Ocp1Error.invalidDatasetFormat
    }
  }

  func serializeParameterDataset(compress: Bool) async throws -> OcaLongBlob {
    let jsonObject: [String: any Sendable] = try await serializeParameterDataset()
    do {
      let blob = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
      #if canImport(Gzip)
      return try .init(compress ? blob.gzipped() : blob)
      #else
      guard !compress else { throw Ocp1Error.notImplemented }
      return .init(blob)
      #endif
    } catch is EncodingError {
      throw Ocp1Error.invalidDatasetFormat
    }
  }

  func deserializeParameterDataset(from parameterData: OcaLongBlob) async throws {
    let parameterData = Data(parameterData)
    do {
      #if canImport(Gzip)
      let data = try parameterData.isGzipped ? parameterData.gunzipped() : parameterData
      #else
      let data = parameterData
      #endif
      guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: any Sendable]
      else {
        throw Ocp1Error.invalidDatasetFormat
      }
      try await deserializeParameterDataset(jsonObject)
    } catch is DecodingError {
      throw Ocp1Error.invalidDatasetFormat
    }
  }
}

extension OcaDeviceManager {
  func serializePatchDataset(paramDatasetONos: Set<OcaONo>) async throws
    -> [String: any Sendable]
  {
    var root = try serialize(flags: [], isIncluded: datasetFilter)

    root[datasetVersionJSONKey] = OcaJsonDatasetVersion
    root[datasetDeviceModelJSONKey] = modelGUID.scalarValue
    root[datasetMimeTypeJSONKey] = OcaPatchDatasetMimeType
    root[datasetParamDatasetsJSONKey] = Array(paramDatasetONos)

    return root
  }

  func serializePatchDataset(paramDatasetONos: Set<OcaONo>) async throws -> OcaLongBlob {
    let jsonObject: [String: any Sendable] =
      try await serializePatchDataset(paramDatasetONos: paramDatasetONos)
    do {
      let blob = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
      #if canImport(Gzip)
      return try .init(blob.gzipped())
      #else
      return .init(blob)
      #endif
    } catch is EncodingError {
      throw Ocp1Error.invalidDatasetFormat
    }
  }

  func deserializePatchDataset(
    _ jsonObject: [String: any Sendable]
  ) async throws {
    guard let deviceDelegate,
          let storageProvider = await deviceDelegate.datasetStorageProvider
    else {
      throw Ocp1Error.noDatasetStorageProvider
    }
    guard let version = jsonObject[datasetVersionJSONKey] as? OcaUint32,
          version == OcaJsonDatasetVersion
    else {
      throw Ocp1Error.unknownDatasetVersion
    }
    guard let deviceModel = jsonObject[datasetDeviceModelJSONKey] as? OcaUint64,
          deviceModel == modelGUID.scalarValue
    else {
      throw Ocp1Error.datasetDeviceMismatch
    }
    guard let mimeType = jsonObject[datasetMimeTypeJSONKey] as? OcaString,
          mimeType == OcaPatchDatasetMimeType
    else {
      throw Ocp1Error.datasetMimeTypeMismatch
    }

    do {
      try await deserialize(jsonObject: jsonObject, flags: .ignoreMissingProperties)
    } catch is DecodingError {
      throw Ocp1Error.invalidDatasetFormat
    }

    let datasetParams = (jsonObject[datasetParamDatasetsJSONKey] as? [OcaONo]) ?? []
    for datasetParam in datasetParams {
      let dataset = try await storageProvider.resolve(
        targetONo: nil,
        datasetONo: datasetParam
      )
      guard let block = await deviceDelegate.resolve(objectNumber: dataset.owner) as? OcaBlock
      else {
        continue
      }
      try await block.apply(paramDataset: datasetParam, controller: nil)
    }
  }

  func deserializePatchDataset(
    _ patchData: OcaLongBlob
  ) async throws {
    let patchData = Data(patchData)
    do {
      #if canImport(Gzip)
      let data = try patchData.isGzipped ? patchData.gunzipped() : patchData
      #else
      let data = patchData
      #endif
      guard let jsonObject = try JSONSerialization
        .jsonObject(with: data) as? [String: any Sendable]
      else {
        throw Ocp1Error.invalidDatasetFormat
      }
      try await deserializePatchDataset(jsonObject)
    } catch is DecodingError {
      throw Ocp1Error.invalidDatasetFormat
    }
  }

  @_spi(SwiftOCAPrivate)
  @discardableResult
  public func storePatch(
    patchDatasetONo: OcaONo?,
    name: OcaString,
    paramDatasetONos: Set<OcaONo>,
    controller: OcaController?,
    createIfAbsent: Bool
  ) async throws -> OcaONo {
    guard let deviceDelegate,
          let storageProvider = await deviceDelegate.datasetStorageProvider
    else {
      throw Ocp1Error.noDatasetStorageProvider
    }

    for datasetONo in paramDatasetONos {
      // save the datasets first
      guard let dataset = try? await storageProvider.resolve(
        targetONo: nil,
        datasetONo: datasetONo
      ),
        let object = await deviceDelegate.resolve(objectNumber: dataset.owner) as? OcaBlock
      else {
        continue
      }
      try await dataset.storeParameters(object: object, controller: controller)
    }

    if let patchDatasetONo {
      if let existingDataset = try? await storageProvider.resolve(
        targetONo: OcaDeviceManagerONo,
        datasetONo: patchDatasetONo
      ) {
        try await existingDataset.storePatch(
          paramDatasetONos: paramDatasetONos,
          deviceManager: self,
          controller: controller
        )
        return existingDataset.objectNumber
      }
    } else if !createIfAbsent {
      throw Ocp1Error.unknownDataset
    }
    let blob: OcaLongBlob = try await serializePatchDataset(paramDatasetONos: paramDatasetONos)

    return try await storageProvider.construct(
      classID: OcaDataset.classID,
      targetONo: OcaDeviceManagerONo,
      datasetONo: patchDatasetONo,
      name: name,
      type: OcaPatchDatasetMimeType,
      maxSize: .max,
      initialContents: blob,
      controller: nil
    )
  }
}
