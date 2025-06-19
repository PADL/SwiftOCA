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
@_spi(SwiftOCAPrivate)
import SwiftOCA

let objectNumberJSONKey = "_oNo"
let classIDJSONKey = "_classID"

// for datasets, these keys are merged with the top-level JSON object for validation
let datasetVersionJSONKey = "_version"
let datasetDeviceModelJSONKey = "_deviceModel"
let datasetMimeTypeJSONKey = "_mimeType"

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

extension OcaBlock {
  func serializeDatasetParameters() async throws -> [String: any Sendable] {
    var root = try serialize(flags: [], isIncluded: datasetFilter)

    root[datasetVersionJSONKey] = OcaJsonDatasetVersion
    root[datasetDeviceModelJSONKey] = await deviceDelegate?.deviceManager?.modelGUID
    root[datasetMimeTypeJSONKey] = OcaParamDatasetMimeType

    return root
  }

  func deserializeDataset(parameters: [String: any Sendable]) async throws {
    guard let version = parameters[datasetVersionJSONKey] as? OcaUint32,
          version == OcaJsonDatasetVersion
    else {
      throw Ocp1Error.unknownDatasetVersion
    }
    guard let deviceModel = parameters[datasetDeviceModelJSONKey] as? OcaModelGUID,
          await deviceModel == deviceDelegate?.deviceManager?.modelGUID
    else {
      throw Ocp1Error.datasetDeviceMismatch
    }
    guard let mimeType = parameters[datasetMimeTypeJSONKey] as? String,
          mimeType == OcaParamDatasetMimeType
    else {
      throw Ocp1Error.datasetMimeTypeMismatch
    }
    do {
      try await deserialize(jsonObject: parameters)
    } catch is DecodingError {
      throw Ocp1Error.invalidDatasetFormat
    }
  }

  func serializeDatasetParameters() async throws -> OcaLongBlob {
    let datasetParameters: [String: any Sendable] = try await serializeDatasetParameters()
    do {
      return try OcaLongBlob(JSONSerialization.data(withJSONObject: datasetParameters, options: []))
    } catch is EncodingError {
      throw Ocp1Error.invalidDatasetFormat
    }
  }

  func deserializeDatasetParameters(from parameterData: OcaLongBlob) async throws {
    let parameterData = Data(parameterData)
    do {
      guard let jsonObject = try JSONSerialization
        .jsonObject(with: parameterData) as? [String: Any]
      else {
        throw Ocp1Error.invalidDatasetFormat
      }
      try await deserializeDataset(parameters: jsonObject)
    } catch is DecodingError {
      throw Ocp1Error.invalidDatasetFormat
    }
  }
}
