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
import BinaryCoder
import Foundation
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#else
protocol ObservableObject {} // placeholder
#endif

open class OcaRoot: CustomStringConvertible, ObservableObject {
    typealias Root = OcaRoot

    weak var connectionDelegate: AES70OCP1Connection?

    // 1.1
    open class var classID: OcaClassID { OcaClassID("1") }
    private var _classID: StaticProperty<OcaClassID> {
        StaticProperty<OcaClassID>(propertyIDs: [OcaPropertyID("1.1")], value: Self.classID)
    }

    // 1.2
    open class var classVersion: OcaClassVersionNumber { 2 }
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
    public var lockable: OcaProperty<OcaBoolean>.State

    @OcaProperty(
        propertyID: OcaPropertyID("1.5"),
        getMethodID: OcaMethodID("1.5")
    )
    public var role: OcaProperty<OcaString>.State

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

    func get(classIdentification: inout OcaClassIdentification) async throws {
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

    func lockReadOnly() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("1.6"))
    }

    public var isContainer: Bool {
        false
    }

    public var description: String {
        if case let .success(value) = role {
            return "\(type(of: self))(objectNumber: \(objectNumber), role: \(value))"
        } else {
            return "\(type(of: self))(objectNumber: \(objectNumber))"
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

    @MainActor
    internal func propertyDidChange(event: OcaEvent, eventData data: Data) {
        let decoder = BinaryDecoder(config: .ocp1Configuration)
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

    internal struct StaticProperty<T: Codable>: OcaPropertySubjectRepresentable {
        typealias Value = T

        var propertyIDs: [OcaPropertyID]
        var value: T

        func refresh(_ object: SwiftOCA.OcaRoot) async {}
        func subscribe(_ object: OcaRoot) async {}

        var description: String {
            String(describing: value)
        }

        var currentValue: OcaProperty<Value>.State {
            OcaProperty<Value>.State.success(value)
        }

        var subject: AsyncCurrentValueSubject<State> {
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
