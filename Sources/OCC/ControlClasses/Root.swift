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
    var lockable: OcaProperty<OcaBoolean>.State
    
    @OcaProperty(propertyID: OcaPropertyID("1.5"),
                 getMethodID: OcaMethodID("1.5"))
    var role: OcaProperty<OcaString>.State
    
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

    @MainActor
    func propertyDidChange(eventData: Ocp1EventData) {
        let decoder = BinaryDecoder(config: .ocp1Configuration)
        guard let propertyID = try? decoder.decode(OcaPropertyID.self,
                                                   from: eventData.eventParameters) else { return }
        
        // TODO: Mirror is inefficient
        
        let mirror = Mirror(reflecting: self)
        for case (let key?, _) in mirror.children {
            let keyPath = \Self.[checkedMirrorDescendant: key]

            if let keyPath = keyPath as? ReferenceWritableKeyPath,
                  let property = (self as! Self)[keyPath: keyPath] as? OcaPropertyChangeEventNotifiable,
               property.propertyIDs.contains(propertyID) {
                try? property.onEvent(eventData)
                break
            }
        }
    }
    
    public func subscribe() async throws {
        guard let connectionDelegate else { throw Ocp1Error.notConnected }
        let event = OcaEvent(emitterONo: self.objectNumber, eventID: OcaPropertyChangedEventID)
        try await connectionDelegate.addSubscription(event: event, callback: propertyDidChange)
    }
    
    public func unsubscribe() async throws {
        guard let connectionDelegate else { throw Ocp1Error.notConnected }
        let event = OcaEvent(emitterONo: self.objectNumber, eventID: OcaPropertyChangedEventID)
        try await connectionDelegate.removeSubscription(event: event, callback: propertyDidChange)
    }
}

struct OcaGetPathParameters: Codable {
    var namePath: OcaNamePath
    var oNoPath: OcaONoPath
}
