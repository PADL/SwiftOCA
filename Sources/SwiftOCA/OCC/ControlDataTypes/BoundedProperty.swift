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

public struct OcaBoundedPropertyValue<T: Codable>: Codable {
    var value: T
    var minValue: T?
    var maxValue: T?
}

@propertyWrapper
public struct OcaBoundedProperty<Value: Codable>: OcaPropertyChangeEventNotifiable {
    var propertyIDs: [OcaPropertyID] {
        [wrappedValue.propertyID]
    }

    public var wrappedValue: OcaProperty<OcaBoundedPropertyValue<Value>>
    
    init(propertyID: OcaPropertyID,
         getMethodID: OcaMethodID,
         setMethodID: OcaMethodID? = nil) {
        self.wrappedValue = OcaProperty(propertyID: propertyID,
                                        getMethodID: getMethodID,
                                        setMethodID: setMethodID,
                                        setValue: { instance, value in
            try await instance.sendCommandRrq(methodID: setMethodID!, parameter: value.value)
        })
    }
    
    public var projectedValue: AnyPublisher<OcaProperty<OcaBoundedPropertyValue<Value>>.State, Never> {
        return wrappedValue.getPublisher()
    }

    func onEvent(_ eventData: Ocp1EventData) throws {
        precondition(eventData.event.eventID == OcaPropertyChangedEventID)
        
        let decoder = BinaryDecoder(config: .ocp1Configuration)
        let eventData = try decoder.decode(OcaPropertyChangedEventData<Value>.self,
                                           from: eventData.eventParameters)
        
        // TODO: support add/delete
        switch eventData.changeType {
        case .currentChanged:
            let value: OcaBoundedPropertyValue<Value>
            if case .success(let subjectValue) = wrappedValue.wrappedValue {
                value = OcaBoundedPropertyValue(value: eventData.propertyValue,
                                                minValue: subjectValue.minValue,
                                                maxValue: subjectValue.maxValue)
            } else {
                value = OcaBoundedPropertyValue(value: eventData.propertyValue)
            }
            wrappedValue.wrappedValue = .success(value)
            break
        default:
            break
        }
    }
}
