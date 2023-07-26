//
// Copyright (c) 2023 PADL Software Pty Ltd
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

open class OcaRoot: CustomStringConvertible {
    public class var classID: OcaClassID { OcaClassID("1") }
    public class var classVersion: OcaClassVersionNumber { 2 }
    public let objectNumber: OcaONo
    public let lockable: OcaBoolean
    public let role: OcaString

    weak var deviceDelegate: AES70OCP1Device?

    public class var classIdentification: OcaClassIdentification {
        OcaClassIdentification(classID: classID, classVersion: classVersion)
    }

    public var objectIdentification: OcaObjectIdentification {
        OcaObjectIdentification(oNo: objectNumber, classIdentification: Self.classIdentification)
    }

    public init(
        objectNumber: OcaONo? = nil,
        lockable: OcaBoolean = false,
        role: OcaString = "Root",
        deviceDelegate: AES70OCP1Device? = nil
    ) async throws {
        if let objectNumber {
            precondition(objectNumber != OcaInvalidONo)
            self.objectNumber = objectNumber
        } else {
            self.objectNumber = await deviceDelegate?.allocateObjectNumber() ?? OcaInvalidONo
        }
        self.lockable = lockable
        self.role = role
        self.deviceDelegate = deviceDelegate
        if let deviceDelegate {
            try await deviceDelegate.register(object: self)
        }
    }

    public var description: String {
        "\(type(of: self))(objectNumber: \(objectNumber), role: \(role))"
    }

    func handlePropertyAccessor(
        _ command: Ocp1Command,
        from controller: AES70OCP1Controller
    ) async throws -> Ocp1Response {
        for (_, propertyKeyPath) in allPropertyKeyPaths {
            let property = self[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)

            if command.methodID == property.getMethodID {
                return try await property.get(object: self)
            } else if command.methodID == property.setMethodID {
                // FIXME: this doesn't actually mutate the value in the class
                var property = property
                try await property.set(object: self, command: command)
                return Ocp1Response()
            }
        }
        throw Ocp1Error.unhandledMethod
    }

    open func handleCommand(
        _ command: Ocp1Command,
        from controller: AES70OCP1Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("1.1"):
            return try encodeResponse(Self.classID)
        case OcaMethodID("1.2"):
            return try encodeResponse(Self.classVersion)
        case OcaMethodID("1.3"):
            return try encodeResponse(objectNumber)
        case OcaMethodID("1.4"):
            return try encodeResponse(lockable)
        case OcaMethodID("1.5"):
            return try encodeResponse(role)
        default:
            return try await handlePropertyAccessor(command, from: controller)
        }
    }

    public var isContainer: Bool {
        false
    }
}

extension OcaRoot: Equatable {
    public static func == (lhs: OcaRoot, rhs: OcaRoot) -> Bool {
        lhs.objectNumber == rhs.objectNumber
    }
}

extension OcaRoot: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(objectNumber)
    }
}

extension OcaRoot {
    private subscript(checkedMirrorDescendant key: String) -> Any {
        Mirror(reflecting: self).descendant(key)!
    }

    private var allKeyPaths: [String: PartialKeyPath<OcaRoot>] {
        // TODO: Mirror is inefficient
        var membersToKeyPaths = [String: PartialKeyPath<OcaRoot>]()
        let mirror = Mirror(reflecting: self)

        for case let (key?, _) in mirror.children {
            guard let dictionaryKey = key.deletingPrefix("_") else { continue }
            membersToKeyPaths[dictionaryKey] = \Self
                .[checkedMirrorDescendant: key] as PartialKeyPath
        }
        return membersToKeyPaths
    }

    var allPropertyKeyPaths: [String: PartialKeyPath<OcaRoot>] {
        allKeyPaths.filter { self[keyPath: $0.value] is any OcaDevicePropertyRepresentable }
    }
}

private extension String {
    func deletingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
