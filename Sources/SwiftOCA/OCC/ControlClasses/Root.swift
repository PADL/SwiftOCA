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
import BinaryCoder
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#elseif canImport(SwiftCrossUI)
import SwiftCrossUI
typealias ObservableObject = Observable
#endif

public class OcaRoot: CustomStringConvertible, ObservableObject {
    typealias Root = OcaRoot
    
    weak var connectionDelegate: AES70OCP1Connection? = nil
    
    // 1.1
    public class var classID: OcaClassID { OcaClassID("1") }
    private var _classID: StaticProperty<OcaClassID> {
        StaticProperty<OcaClassID>(propertyIDs: [OcaPropertyID("1.1")], value: Self.classID)
    }

    // 1.2
    public class var classVersion: OcaClassVersionNumber { return 2 }
    private var _classVersion: StaticProperty<OcaClassVersionNumber> {
        StaticProperty<OcaClassVersionNumber>(propertyIDs: [OcaPropertyID("1.2")], value: Self.classVersion)
    }

    public class var classIdentification: OcaClassIdentification {
        OcaClassIdentification(classID: classID, classVersion: classVersion)
    }
    
    // 1.3
    public let objectNumber: OcaONo
    private var _objectNumber: StaticProperty<OcaONo> {
        StaticProperty<OcaONo>(propertyIDs: [OcaPropertyID("1.3")], value: objectNumber)
    }

    @OcaProperty(propertyID: OcaPropertyID("1.4"),
                 getMethodID: OcaMethodID("1.2"))
    public var lockable: OcaProperty<OcaBoolean>.State
    
    @OcaProperty(propertyID: OcaPropertyID("1.5"),
                 getMethodID: OcaMethodID("1.5"))
    public var role: OcaProperty<OcaString>.State
    
    required init(objectNumber: OcaONo = OcaInvalidONo) {
        self.objectNumber = objectNumber
    }
    
    func get(classIdentification: inout OcaClassIdentification) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("1.1"),
                                 responseParameterCount: 1,
                                 responseParameters: &classIdentification)
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
        if case .success(let value) = self.role {
            return "\(type(of: self))(objectNumber: \(objectNumber), role: \(value))"
        } else {
            return "\(type(of: self))(objectNumber: \(objectNumber))"
        }
    }
}

fileprivate extension String {
    func deletingPrefix(_ prefix: String) -> String? {
        guard self.hasPrefix(prefix) else { return nil }
        return String(self.dropFirst(prefix.count))
    }
}

extension OcaRoot {
    private subscript(checkedMirrorDescendant key: String) -> Any {
        return Mirror(reflecting: self).descendant(key)!
    }

    private var allKeyPaths: [String: PartialKeyPath<OcaRoot>] {
        // TODO: Mirror is inefficient
        var membersToKeyPaths = [String: PartialKeyPath<OcaRoot>]()
        let mirror = Mirror(reflecting: self)
        for case (let key?, _) in mirror.children {
            guard let dictionaryKey = key.deletingPrefix("_") else { continue }
            membersToKeyPaths[dictionaryKey] = \Self.[checkedMirrorDescendant: key] as PartialKeyPath
        }
        return membersToKeyPaths
    }
    
    private var staticPropertyKeyPaths: [String: PartialKeyPath<OcaRoot>] {
        ["classID": \._classID,
         "classVersion": \._classVersion,
         "objectNumber": \._objectNumber]
    }
    
    public var allPropertyKeyPaths: [String: PartialKeyPath<OcaRoot>] {
        staticPropertyKeyPaths.merging(
            allKeyPaths.filter { self[keyPath: $0.value] is any OcaPropertyRepresentable },
            uniquingKeysWith: { old, _ in old })
    }

    public func property<Value: Codable>(keyPath: PartialKeyPath<OcaRoot>) -> OcaProperty<Value>.State {
        let storageKeyPath = keyPath as! ReferenceWritableKeyPath<OcaRoot, OcaProperty<Value>>
        let wrappedKeyPath = keyPath.appending(path: \OcaProperty<Value>.currentValue) as! ReferenceWritableKeyPath<OcaRoot, OcaProperty<Value>.State>
        return OcaProperty<Value>[_enclosingInstance: self, wrapped: wrappedKeyPath, storage: storageKeyPath]
    }
    
    @MainActor
    func propertyDidChange(eventData: Ocp1EventData) {
        let decoder = BinaryDecoder(config: .ocp1Configuration)
        guard let propertyID = try? decoder.decode(OcaPropertyID.self,
                                                   from: eventData.eventParameters) else { return }
        
        allKeyPaths.forEach { (keyPathString, keyPath) in
            if let value = self[keyPath: keyPath] as? (any OcaPropertyChangeEventNotifiable),
               value.propertyIDs.contains(propertyID) {
                try? value.onEvent(self, eventData)
                return
            }
        }
    }
        
    public func subscribe() async throws {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
        let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
        do {
            try await connectionDelegate.addSubscription(event: event, callback: propertyDidChange)
        } catch Ocp1Error.alreadySubscribedToEvent {
        } catch Ocp1Error.status(.invalidRequest) {
            // FIXME: in our device implementation not all properties can be subcribed to
        }
    }
    
    public func unsubscribe() async throws {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
        let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
        try await connectionDelegate.removeSubscription(event: event)
    }
    
    public func refreshAll() async {
        for (_, keyPath) in allPropertyKeyPaths {
            let property = (self[keyPath: keyPath] as! any OcaPropertyRepresentable)
            await property.refresh(self)
        }
    }

    public func refresh() async {
        for (_, keyPath) in allPropertyKeyPaths {
            let property = (self[keyPath: keyPath] as! any OcaPropertyRepresentable)
            if !property.isInitial {
                await property.refresh(self)
            }
        }
    }

    var isSubscribed: Bool {
        get async throws {
            guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
            let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
            return await connectionDelegate.isSubscribed(event: event)
        }
    }
    
    struct StaticProperty<T: Codable>: OcaPropertyRepresentable {
        typealias Value = T
        
        var propertyIDs: [OcaPropertyID]
        var value: T
        
        func refresh(_ instance: SwiftOCA.OcaRoot) async {}
        func subscribe(_ instance: OcaRoot) async {}

        var description: String {
            String(describing: value)
        }
        
        var currentValue: OcaProperty<Value>.State {
            OcaProperty<Value>.State.success(value)
        }
    }
}
