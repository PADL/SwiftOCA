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

import AsyncExtensions
import SwiftOCA

extension AES70Controller {
    typealias ID = ObjectIdentifier

    nonisolated var id: ID {
        ObjectIdentifier(self)
    }
}

open class OcaRoot: CustomStringConvertible, Codable, @unchecked
Sendable {
    var notificationTasks = [OcaPropertyID: Task<(), Error>]()

    open class var classID: OcaClassID { OcaClassID("1") }
    open class var classVersion: OcaClassVersionNumber { 2 }

    public let objectNumber: OcaONo
    public var lockable: OcaBoolean
    public var role: OcaString

    public internal(set) weak var deviceDelegate: AES70Device?

    enum LockState: Sendable, CustomStringConvertible {
        /// AES70-1-2023 uses this confusing `NoReadWrite` and `NoWrite` nomenclature
        case unlocked
        case lockedNoWrite(AES70Controller.ID)
        case lockedNoReadWrite(AES70Controller.ID)

        var lockState: OcaLockState {
            switch self {
            case .unlocked:
                return .noLock
            case .lockedNoWrite:
                return .lockNoWrite
            case .lockedNoReadWrite:
                return .lockNoReadWrite
            }
        }

        var description: String {
            switch self {
            case .unlocked:
                return "Unlocked"
            case .lockedNoWrite:
                return "Read locked"
            case .lockedNoReadWrite:
                return "Read/write locked"
            }
        }
    }

    var lockStateSubject = AsyncCurrentValueSubject<LockState>(.unlocked)

    var lockState: LockState {
        get {
            lockStateSubject.value
        }
        set {
            lockStateSubject.value = newValue
        }
    }

    public class var classIdentification: OcaClassIdentification {
        OcaClassIdentification(classID: classID, classVersion: classVersion)
    }

    public var objectIdentification: OcaObjectIdentification {
        OcaObjectIdentification(oNo: objectNumber, classIdentification: Self.classIdentification)
    }

    public init(
        objectNumber: OcaONo? = nil,
        lockable: OcaBoolean = false,
        role: OcaString? = nil,
        deviceDelegate: AES70Device? = nil,
        addToRootBlock: Bool = true
    ) async throws {
        if let objectNumber {
            precondition(objectNumber != OcaInvalidONo)
            self.objectNumber = objectNumber
        } else {
            self.objectNumber = await deviceDelegate?.allocateObjectNumber() ?? OcaInvalidONo
        }
        self.lockable = lockable
        self.role = role ?? String(self.objectNumber)
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

    enum CodingKeys: String, CodingKey {
        case objectNumber = "oNo"
        case classIdentification = "1.1"
        case lockable = "1.2"
        case role = "1.3"
    }

    public func encode(to encoder: Encoder) throws {
        if encoder._isOcp1Encoder {
            var container = encoder.unkeyedContainer()
            try container.encode(objectNumber)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Self.classID.description, forKey: .classIdentification)
            try container.encode(objectNumber, forKey: .objectNumber)
            try container.encode(lockable, forKey: .lockable)
            try container.encode(role, forKey: .role)
        }
    }

    public required init(from decoder: Decoder) throws {
        if decoder._isOcp1Decoder {
            throw Ocp1Error.notImplemented
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let classID = try OcaClassID(
                container
                    .decode(String.self, forKey: .classIdentification)
            )
            guard classID == Self.classID else {
                throw Ocp1Error.objectClassMismatch
            }

            objectNumber = try container.decode(OcaONo.self, forKey: .objectNumber)
            lockable = try container.decode(OcaBoolean.self, forKey: .lockable)
            role = try container.decode(OcaString.self, forKey: .role)
            deviceDelegate = AES70Device.shared
        }
    }

    public var description: String {
        let objectNumberString = String(format: "0x%08x", objectNumber)
        return "\(type(of: self))(objectNumber: \(objectNumberString), role: \(role))"
    }

    func handlePropertyAccessor(
        _ command: Ocp1Command,
        from controller: any AES70Controller
    ) async throws -> Ocp1Response {
        for (_, propertyKeyPath) in allPropertyKeyPaths {
            let property = self[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)

            if command.methodID == property.getMethodID {
                try await ensureReadable(by: controller, command: command)
                return try await property.get(object: self)
            } else if command.methodID == property.setMethodID {
                try await ensureWritable(by: controller, command: command)
                try await property.set(object: self, command: command)
                return Ocp1Response()
            }
        }
        await deviceDelegate?.logger.info("unknown property accessor method \(command)")
        throw Ocp1Error.status(.notImplemented)
    }

    open func handleCommand(
        _ command: Ocp1Command,
        from controller: any AES70Controller
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
        case OcaMethodID("1.7"):
            return try encodeResponse(lockState.lockState)
        default:
            return try await handlePropertyAccessor(command, from: controller)
        }
        return Ocp1Response()
    }

    public var isContainer: Bool {
        false
    }

    open func ensureReadable(
        by controller: any AES70Controller,
        command: Ocp1Command
    ) async throws {
        if let deviceManager = await deviceDelegate?.deviceManager, deviceManager != self {
            try await deviceManager.ensureReadable(by: controller, command: command)
        }

        switch lockState {
        case .unlocked:
            break
        case .lockedNoWrite:
            break
        case let .lockedNoReadWrite(lockholder):
            guard controller.id == lockholder else {
                throw Ocp1Error.status(.locked)
            }
        }
    }

    /// Important note: when subclassing you will typically want to override ensureWritable() to
    /// implement your own form of access control.
    open func ensureWritable(
        by controller: any AES70Controller,
        command: Ocp1Command
    ) async throws {
        if let deviceManager = await deviceDelegate?.deviceManager, deviceManager != self {
            try await deviceManager.ensureWritable(by: controller, command: command)
        }

        switch lockState {
        case .unlocked:
            break
        case let .lockedNoWrite(lockholder):
            fallthrough
        case let .lockedNoReadWrite(lockholder):
            guard controller.id == lockholder else {
                throw Ocp1Error.status(.locked)
            }
        }
    }

    func lockNoWrite(controller: any AES70Controller) throws {
        if !lockable {
            throw Ocp1Error.status(.notImplemented)
        }

        switch lockState {
        case .unlocked:
            lockState = .lockedNoWrite(controller.id)
        case .lockedNoWrite:
            throw Ocp1Error.status(.locked)
        case let .lockedNoReadWrite(lockholder):
            guard controller.id == lockholder else {
                throw Ocp1Error.status(.locked)
            }
            // downgrade lock
            lockState = .lockedNoWrite(controller.id)
        }
    }

    func lockNoReadWrite(controller: any AES70Controller) throws {
        if !lockable {
            throw Ocp1Error.status(.notImplemented)
        }

        switch lockState {
        case .unlocked:
            lockState = .lockedNoReadWrite(controller.id)
        case let .lockedNoWrite(lockholder):
            guard controller.id == lockholder else {
                throw Ocp1Error.status(.locked)
            }
            lockState = .lockedNoReadWrite(controller.id)
        case .lockedNoReadWrite:
            throw Ocp1Error.status(.locked)
        }
    }

    func unlock(controller: any AES70Controller) throws {
        if !lockable {
            throw Ocp1Error.status(.notImplemented)
        }

        switch lockState {
        case .unlocked:
            throw Ocp1Error.status(.invalidRequest)
        case let .lockedNoWrite(lockholder):
            fallthrough
        case let .lockedNoReadWrite(lockholder):
            guard controller.id == lockholder else {
                throw Ocp1Error.status(.locked)
            }
            lockState = .unlocked
        }
    }

    func setLockState(to lockState: OcaLockState, controller: any AES70Controller) -> Bool {
        do {
            switch lockState {
            case .noLock:
                try unlock(controller: controller)
            case .lockNoWrite:
                try lockNoWrite(controller: controller)
            case .lockNoReadWrite:
                try lockNoReadWrite(controller: controller)
            }
            return true
        } catch {
            return false
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

public protocol OcaOwnable: OcaRoot {
    var owner: OcaONo { get set }
}

public extension OcaOwnable {
    func getOwnerObject<T>() async -> OcaBlock<T>? {
        await deviceDelegate?.objects[owner] as? OcaBlock<T>
    }
}
