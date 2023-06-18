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

public class OcaRoot: ObservableObject {
    typealias Root = OcaRoot
    
    weak var connectionDelegate: AES70OCP1Connection? = nil

    // 1.1
    public class var classID: OcaClassID { OcaClassID("1") }
    
    // 1.2
    public class var classVersion: OcaClassVersionNumber { return 2 }
    
    public class var classIdentification: OcaClassIdentification {
        OcaClassIdentification(classID: classID, classVersion: classVersion)
    }
    
    // 1.3
    public let objectNumber: OcaONo
    
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
}

extension OcaRoot {

    private subscript(checkedMirrorDescendant key: String) -> Any {
        return Mirror(reflecting: self).descendant(key)!
    }

    var allKeyPaths: [String: PartialKeyPath<OcaRoot>] {
        var membersTokeyPaths = [String: PartialKeyPath<OcaRoot
                                 >]()
        let mirror = Mirror(reflecting: self)
        for case (let key?, _) in mirror.children {
            membersTokeyPaths[key] = \Self.[checkedMirrorDescendant: key] as PartialKeyPath
        }
        return membersTokeyPaths
    }


    @MainActor
    func propertyDidChange(eventData: Ocp1EventData) {
        let decoder = BinaryDecoder(config: .ocp1Configuration)
        guard let propertyID = try? decoder.decode(OcaPropertyID.self,
                                                   from: eventData.eventParameters) else { return }
        
        // TODO: Mirror is inefficient
        Mirror.allKeyPaths(for: self).forEach {
            if $0.value.propertyIDs.contains(propertyID) {
                try? $0.value.onEvent(eventData)
                return
            }
        }
    }
    
    struct StaticProperty<T: Codable>: OcaPropertyRepresentable {
        typealias Value = T
        
        var propertyIDs: [OcaPropertyID]
        var value: T

        func refresh(_ instance: SwiftOCA.OcaRoot) async {}
        
        var description: String {
            String(describing: value)
        }
        
        var currentValue: OcaProperty<Value>.State {
            OcaProperty<Value>.State.success(value)
        }
    }

    var staticProperties: [String: any OcaPropertyRepresentable] {
        let classID = StaticProperty<OcaClassID>(propertyIDs: [OcaPropertyID("1.1")], value: Self.classID)
        let classVersion = StaticProperty<OcaClassVersionNumber>(propertyIDs: [OcaPropertyID("1.2")], value: Self.classVersion)
        let objectNumber = StaticProperty<OcaONo>(propertyIDs: [OcaPropertyID("1.3")], value: objectNumber)
        return ["classID": classID, "classVersion": classVersion, "objectNumber": objectNumber]
    }

    public var allProperties: [String: any OcaPropertyRepresentable] {
        self.staticProperties.merging(Mirror.allKeyPaths(for: self)) { (_, new) in new }
    }
    
    public func subscribe() async throws {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
        let event = OcaEvent(emitterONo: self.objectNumber, eventID: OcaPropertyChangedEventID)
        do {
            try await connectionDelegate.addSubscription(event: event, callback: propertyDidChange)
        } catch Ocp1Error.alreadySubscribedToEvent {
        } catch Ocp1Error.status(.invalidRequest) {
            // FIXME: in our device implementation not all properties can be subcribed to
        }
    }
    
    public func unsubscribe() async throws {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
        let event = OcaEvent(emitterONo: self.objectNumber, eventID: OcaPropertyChangedEventID)
        try await connectionDelegate.removeSubscription(event: event)
    }
    
    public func refresh() async throws {
        for keyPath in Mirror.allKeyPaths(for: self) {
            await keyPath.value.refresh(self)
        }
    }
    
    var isSubscribed: Bool {
        get async throws {
            guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
            let event = OcaEvent(emitterONo: self.objectNumber, eventID: OcaPropertyChangedEventID)
            return await connectionDelegate.isSubscribed(event: event)
        }
    }
}

struct OcaGetPathParameters: Codable {
    var namePath: OcaNamePath
    var oNoPath: OcaONoPath
}
