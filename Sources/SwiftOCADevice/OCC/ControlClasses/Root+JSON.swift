//
// Copyright (c) 2024 PADL Software Pty Ltd
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
let actionObjectsJSONKey = "_members"

public extension OcaDevice {
  @discardableResult
  func deserialize(
    jsonObject: [String: Sendable]
  ) async throws -> OcaRoot {
    guard let classID = jsonObject[classIDJSONKey] as? String else {
      logger.warning("bad or missing object class when deserializing")
      throw Ocp1Error.objectClassMismatch
    }

    guard let objectNumber = jsonObject[objectNumberJSONKey] as? OcaONo,
          objectNumber != OcaInvalidONo
    else {
      logger.warning("bad or missing object number when deserializing")
      throw Ocp1Error.status(.badONo)
    }

    guard let object = objects[objectNumber] else {
      logger.warning("object \(objectNumber.oNoString) not present, cannot deserialize")
      throw Ocp1Error.objectNotPresent(objectNumber)
    }

    guard try await object.objectIdentification.classIdentification
      .classID == OcaClassID(unsafeString: classID)
    else {
      logger.warning("object class mismatch between \(object) and \(classID)")
      throw Ocp1Error.objectClassMismatch
    }

    for (_, propertyKeyPath) in object.allDevicePropertyKeyPaths {
      let property = object[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)
      let propertyName = property.propertyID.description

      guard let value = jsonObject[propertyName] else {
        continue
      }

      do {
        try await property.set(object: object, jsonValue: value, device: self)
      } catch {
        logger
          .warning(
            "failed to set value \(value) on property \(propertyName) of \(object): \(error)"
          )
        throw error
      }
    }

    return object
  }
}

public extension OcaRoot {
  var jsonObject: [String: Any] {
    try! serialize(flags: .ignoreErrors)
  }
}
