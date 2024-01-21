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
import Foundation
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#else
protocol ObservableObject {} // placeholder
#endif

open class OcaRoot: CustomStringConvertible, ObservableObject, @unchecked
Sendable {
    typealias Root = OcaRoot

    public internal(set) weak var connectionDelegate: AES70OCP1Connection?
    // public var objectNumberMapper: OcaObjectNumberMapper = OcaIdentityObjectNumberMapper.shared

    // 1.1
    open class var classID: OcaClassID { OcaClassID("1") }
    private var _classID: StaticProperty<OcaClassID> {
        StaticProperty<OcaClassID>(propertyIDs: [OcaPropertyID("1.1")], value: Self.classID)
    }

    // 1.2
    open class var classVersion: OcaClassVersionNumber { 3 }
    private var _classVersion: StaticProperty<OcaClassVersionNumber> {
        StaticProperty<OcaClassVersionNumber>(
            propertyIDs: [OcaPropertyID("1.2")],
            value: Self.classVersion
        )
    }

    public class var classIdentification: OcaClassIdentification {
        OcaClassIdentification(classID: classID, classVersion: classVersion)
    }

    public var objectIdentification: OcaObjectIdentification {
        OcaObjectIdentification(
            oNo: objectNumber,
            classIdentification: Self.classIdentification
        )
    }

    // 1.3
    public let objectNumber: OcaONo
    private var _objectNumber: StaticProperty<OcaONo> {
        StaticProperty<OcaONo>(propertyIDs: [OcaPropertyID("1.3")], value: objectNumber)
    }

    @OcaProperty(
        propertyID: OcaPropertyID("1.4"),
        getMethodID: OcaMethodID("1.2")
    )
    public var lockable: OcaProperty<OcaBoolean>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("1.5"),
        getMethodID: OcaMethodID("1.5")
    )
    public var role: OcaProperty<OcaString>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("1.6"),
        getMethodID: OcaMethodID("1.7")
    )
    public var lockState: OcaProperty<OcaLockState>.PropertyValue

    // necessary because property wrappers are private
    func _subscribeRole() async {
        await _role.subscribe(self)
    }

    public required init(objectNumber: OcaONo) {
        self.objectNumber = objectNumber
    }

    deinit {
        for (_, keyPath) in allPropertyKeyPaths {
            let value = self[keyPath: keyPath] as! (any OcaPropertySubjectRepresentable)
            value.finish()
        }
    }

    public func get(classIdentification: inout OcaClassIdentification) async throws {
        try await sendCommandRrq(
            methodID: OcaMethodID("1.1"),
            responseParameterCount: 1,
            responseParameters: &classIdentification
        )
    }

    public func lockTotal() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("1.3"))
    }

    public func unlock() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("1.4"))
    }

    public func setLockNoWrite() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("1.6"))
    }

    public var isContainer: Bool {
        false
    }

    public var description: String {
        let objectNumberString = String(format: "0x%08x", objectNumber)

        if case let .success(value) = role {
            return "\(type(of: self))(objectNumber: \(objectNumberString), role: \(value))"
        } else {
            return "\(type(of: self))(objectNumber: \(objectNumberString))"
        }
    }
}

private extension String {
    func deletingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

public extension OcaRoot {
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

    private var staticPropertyKeyPaths: [String: PartialKeyPath<OcaRoot>] {
        ["classID": \._classID,
         "classVersion": \._classVersion,
         "objectNumber": \._objectNumber]
    }

    var allPropertyKeyPaths: [String: PartialKeyPath<OcaRoot>] {
        staticPropertyKeyPaths.merging(
            allKeyPaths.filter { self[keyPath: $0.value] is any OcaPropertySubjectRepresentable },
            uniquingKeysWith: { old, _ in old }
        )
    }

    @Sendable
    internal func propertyDidChange(event: OcaEvent, eventData data: Data) {
        let decoder = Ocp1Decoder()
        guard let propertyID = try? decoder.decode(
            OcaPropertyID.self,
            from: data
        ) else { return }

        allKeyPaths.forEach { _, keyPath in
            if let value = self[keyPath: keyPath] as? (any OcaPropertyChangeEventNotifiable),
               value.propertyIDs.contains(propertyID)
            {
                try? value.onEvent(self, event: event, eventData: data)
                return
            }
        }
    }

    func subscribe() async throws {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
        let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
        do {
            try await connectionDelegate.addSubscription(event: event, callback: propertyDidChange)
        } catch Ocp1Error.alreadySubscribedToEvent {
        } catch Ocp1Error.status(.invalidRequest) {
            // FIXME: in our device implementation not all properties can be subcribed to
        }
    }

    func unsubscribe() async throws {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
        let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
        try await connectionDelegate.removeSubscription(event: event)
    }

    func refreshAll() async {
        for (_, keyPath) in allPropertyKeyPaths {
            let property = (self[keyPath: keyPath] as! any OcaPropertyRepresentable)
            await property.refresh(self)
        }
    }

    func refresh() async {
        for (_, keyPath) in allPropertyKeyPaths {
            let property = (self[keyPath: keyPath] as! any OcaPropertyRepresentable)
            if property.hasValueOrError {
                await property.refresh(self)
            }
        }
    }

    internal var isSubscribed: Bool {
        get async throws {
            guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
            let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
            return await connectionDelegate.isSubscribed(event: event)
        }
    }

    internal struct StaticProperty<T: Codable & Sendable>: OcaPropertySubjectRepresentable {
        typealias Value = T

        var propertyIDs: [OcaPropertyID]
        var value: T

        func refresh(_ object: SwiftOCA.OcaRoot) async {}
        func subscribe(_ object: OcaRoot) async {}

        var description: String {
            String(describing: value)
        }

        var currentValue: OcaProperty<Value>.PropertyValue {
            OcaProperty<Value>.PropertyValue.success(value)
        }

        var subject: AsyncCurrentValueSubject<PropertyValue> {
            AsyncCurrentValueSubject(currentValue)
        }
    }
}

extension OcaRoot: Equatable {
    public static func == (lhs: OcaRoot, rhs: OcaRoot) -> Bool {
        lhs.connectionDelegate == rhs.connectionDelegate &&
            lhs.objectNumber == rhs.objectNumber
    }
}

extension OcaRoot: Hashable {
    public func hash(into hasher: inout Hasher) {
        connectionDelegate?.hash(into: &hasher)
        hasher.combine(objectNumber)
    }
}

public struct OcaGetPathParameters: Codable, Sendable, OcaParameterCountReflectable {
    public static var responseParameterCount: OcaUint8 { 2 }

    public var namePath: OcaNamePath
    public var oNoPath: OcaONoPath

    public init(namePath: OcaNamePath, oNoPath: OcaONoPath) {
        self.namePath = namePath
        self.oNoPath = oNoPath
    }
}

extension OcaRoot {
    func getPath(methodID: OcaMethodID) async throws -> (OcaNamePath, OcaONoPath) {
        let responseParams: OcaGetPathParameters
        responseParams = try await sendCommandRrq(methodID: methodID)
        return (responseParams.namePath, responseParams.oNoPath)
    }
}

public struct OcaSetPortNameParameters: Codable, Sendable {
    public let portID: OcaPortID
    public let name: OcaString

    public init(portID: OcaPortID, name: OcaString) {
        self.portID = portID
        self.name = name
    }
}
