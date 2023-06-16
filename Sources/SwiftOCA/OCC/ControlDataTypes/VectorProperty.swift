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
import Combine
import BinaryCoder

public struct OcaVector2D<T: Codable & FixedWidthInteger>: Codable {
    var x, y: T
}

@propertyWrapper
public struct OcaVectorProperty<Value: Codable & FixedWidthInteger>: OcaPropertyRepresentable, OcaPropertyChangeEventNotifiable {
    var propertyIDs: [OcaPropertyID] {
        [xPropertyID, yPropertyID]
    }
        
    public let xPropertyID: OcaPropertyID
    public let yPropertyID: OcaPropertyID
    public let getMethodID: OcaMethodID
    public let setMethodID: OcaMethodID?
    
    public var wrappedValue: OcaProperty<OcaVector2D<Value>>

    init(xPropertyID: OcaPropertyID,
         yPropertyID: OcaPropertyID,
         getMethodID: OcaMethodID,
         setMethodID: OcaMethodID? = nil) {
        self.xPropertyID = xPropertyID
        self.yPropertyID = yPropertyID
        self.getMethodID = getMethodID
        self.setMethodID = setMethodID
        self.wrappedValue = OcaProperty(propertyID: OcaPropertyID("1"), // deliberately invalid
                                        getMethodID: getMethodID,
                                        setMethodID: setMethodID)
    }
  
    public var projectedValue: AnyPublisher<OcaProperty<OcaVector2D<Value>>.State, Never> {
        return wrappedValue.getPublisher()
    }

    func onEvent(_ eventData: Ocp1EventData) throws {
        precondition(eventData.event.eventID == OcaPropertyChangedEventID)
        
        let decoder = BinaryDecoder(config: .ocp1Configuration)
        let eventData = try decoder.decode(OcaPropertyChangedEventData<Value>.self,
                                           from: eventData.eventParameters)
        precondition(self.propertyIDs.contains(eventData.propertyID))

        // TODO: support add/delete
        switch eventData.changeType {
        case .currentChanged:
            guard case .success(var subjectValue) = wrappedValue.wrappedValue else {
                throw Ocp1Error.noInitialValue
            }

            let isX = eventData.propertyID == self.xPropertyID
            var xy = OcaVector2D<Value>(x: 0, y: 0)
                        
            if isX {
                xy.x = eventData.propertyValue
                xy.y = subjectValue.y
            } else {
                xy.x = subjectValue.x
                xy.y = eventData.propertyValue
            }
            wrappedValue.wrappedValue = .success(xy)
        default:
            throw Ocp1Error.unhandledEvent
        }
    }
}
