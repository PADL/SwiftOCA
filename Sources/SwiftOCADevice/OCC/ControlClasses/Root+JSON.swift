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
import SwiftOCA

private let objectNumberJSONKey = "_oNo"
private let classIDJSONKey = "_classID"
private let actionObjectsJSONKey = "_members"

public extension OcaRoot {
    var jsonObject: [String: Any] {
        var dict = [String: Any]()

        precondition(objectNumber != OcaInvalidONo)

        guard self is OcaWorker else {
            return [:]
        }

        dict[objectNumberJSONKey] = objectNumber
        dict[classIDJSONKey] = Self.classID.description

        for (_, propertyKeyPath) in allDevicePropertyKeyPaths {
            let property = self[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)
            dict[property.propertyID.description] = try? property.getJsonValue(object: self)
        }

        return dict
    }
}

public extension OcaDevice {
    @discardableResult
    func deserialize(jsonObject: [String: Sendable]) async throws -> OcaRoot {
        guard let classID = jsonObject[classIDJSONKey] as? String else {
            throw Ocp1Error.objectClassMismatch
        }

        guard let objectNumber = jsonObject[objectNumberJSONKey] as? OcaONo,
              objectNumber != OcaInvalidONo
        else {
            throw Ocp1Error.status(.badONo)
        }

        guard let object = objects[objectNumber] else {
            throw Ocp1Error.objectNotPresent
        }

        guard try object.objectIdentification.classIdentification
            .classID == OcaClassID(unsafeString: classID)
        else {
            throw Ocp1Error.objectClassMismatch
        }

        for (_, propertyKeyPath) in object.allDevicePropertyKeyPaths {
            let property = object[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)
            guard let value = jsonObject[property.propertyID.description] else {
                throw Ocp1Error.status(.badFormat)
            }

            try await property.set(object: object, jsonValue: value, device: self)
        }

        return object
    }
}
