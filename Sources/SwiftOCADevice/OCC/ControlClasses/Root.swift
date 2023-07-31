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
    var notificationTasks = [OcaPropertyID: Task<(), Error>]()

    open class var classID: OcaClassID { OcaClassID("1") }
    open class var classVersion: OcaClassVersionNumber { 2 }

    public let objectNumber: OcaONo
    public let lockable: OcaBoolean
    public let role: OcaString

    weak var deviceDelegate: AES70OCP1Device?

    enum LockState {
        /// AES70-1-2023 uses this confusing `NoReadWrite` and `NoWrite` nomenclature
        case unlocked
        case lockedNoWrite(AES70OCP1Controller)
        case lockedNoReadWrite(AES70OCP1Controller)
    }

    var lockState: LockState = .unlocked

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
        deviceDelegate: AES70OCP1Device? = nil,
        addToRootBlock: Bool = true
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
            try await deviceDelegate.register(object: self, addToRootBlock: addToRootBlock)
        }
    }

    deinit {
        for (_, propertyKeyPath) in allPropertyKeyPaths {
            let property = self[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)
            property.finish()
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
                try await ensureReadable(by: controller)
                return try await property.get(object: self)
            } else if command.methodID == property.setMethodID {
                try await ensureWritable(by: controller)
                try await property.set(object: self, command: command)
                return Ocp1Response()
            }
        }
        debugPrint("unknown property accessor method \(command)")
        throw Ocp1Error.unhandledMethod
    }

    open func handleCommand(
        _ command: Ocp1Command,
        from controller: AES70OCP1Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("1.1"):
            struct GetClassIdentificationParameters: Codable {
                let classIdentification: OcaClassIdentification
            }
            let response =
                GetClassIdentificationParameters(
                    classIdentification: objectIdentification
                        .classIdentification
                )
            return try encodeResponse(response)
        case OcaMethodID("1.2"):
            return try encodeResponse(lockable)
        case OcaMethodID("1.3"):
            try lockNoReadWrite(controller: controller)
        case OcaMethodID("1.4"):
            try unlock(controller: controller)
        case OcaMethodID("1.5"):
            return try encodeResponse(role)
        case OcaMethodID("1.6"):
            try lockNoWrite(controller: controller)
        default:
            return try await handlePropertyAccessor(command, from: controller)
        }
        return Ocp1Response()
    }

    public var isContainer: Bool {
        false
    }

    public func ensureReadable(by controller: AES70OCP1Controller) async throws {
        if let deviceManager = await deviceDelegate?.deviceManager, deviceManager != self {
            try await deviceManager.ensureReadable(by: controller)
        }

        switch lockState {
        case .unlocked:
            break
        case .lockedNoWrite:
            break
        case let .lockedNoReadWrite(lockholder):
            guard controller == lockholder else {
                throw Ocp1Error.status(.locked)
            }
        }
    }

    public func ensureWritable(by controller: AES70OCP1Controller) async throws {
        if let deviceManager = await deviceDelegate?.deviceManager, deviceManager != self {
            try await deviceManager.ensureWritable(by: controller)
        }

        switch lockState {
        case .unlocked:
            break
        case let .lockedNoWrite(lockholder):
            fallthrough
        case let .lockedNoReadWrite(lockholder):
            guard controller == lockholder else {
                throw Ocp1Error.status(.locked)
            }
        }
    }

    func lockNoWrite(controller: AES70OCP1Controller) throws {
        if !lockable {
            throw Ocp1Error.status(.notImplemented)
        }

        switch lockState {
        case .unlocked:
            lockState = .lockedNoWrite(controller)
        case .lockedNoWrite:
            throw Ocp1Error.status(.locked)
        case let .lockedNoReadWrite(lockholder):
            guard controller == lockholder else {
                throw Ocp1Error.status(.locked)
            }
            // downgrade lock
            lockState = .lockedNoWrite(controller)
        }
    }

    func lockNoReadWrite(controller: AES70OCP1Controller) throws {
        if !lockable {
            throw Ocp1Error.status(.notImplemented)
        }

        switch lockState {
        case .unlocked:
            lockState = .lockedNoReadWrite(controller)
        case let .lockedNoWrite(lockholder):
            guard controller == lockholder else {
                throw Ocp1Error.status(.locked)
            }
            lockState = .lockedNoReadWrite(controller)
        case .lockedNoReadWrite:
            throw Ocp1Error.status(.locked)
        }
    }

    func unlock(controller: AES70OCP1Controller) throws {
        if !lockable {
            throw Ocp1Error.status(.notImplemented)
        }

        switch lockState {
        case .unlocked:
            throw Ocp1Error.status(.invalidRequest)
        case let .lockedNoWrite(lockholder):
            fallthrough
        case let .lockedNoReadWrite(lockholder):
            guard controller == lockholder else {
                throw Ocp1Error.status(.locked)
            }
            lockState = .unlocked
        }
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
    private subscript(_ wrapper: _MirrorWrapper, checkedMirrorDescendant key: String) -> Any {
        wrapper.wrappedValue.descendant(key)!
    }

    private var allKeyPaths: [String: PartialKeyPath<OcaRoot>] {
        // TODO: Mirror is inefficient
        var membersToKeyPaths = [String: PartialKeyPath<OcaRoot>]()
        var mirror: Mirror? = Mirror(reflecting: self)

        repeat {
            if let mirror {
                for case let (key?, _) in mirror.children {
                    guard let dictionaryKey = key.deletingPrefix("_") else { continue }
                    membersToKeyPaths[dictionaryKey] = \Self
                        .[_MirrorWrapper(mirror), checkedMirrorDescendant: key] as PartialKeyPath
                }
            }
            mirror = mirror?.superclassMirror
        } while mirror != nil

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
