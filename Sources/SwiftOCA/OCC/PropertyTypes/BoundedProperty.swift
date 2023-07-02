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
#if canImport(SwiftUI)
import SwiftUI
#elseif canImport(TokamakShim)
import TokamakShim
#endif

public struct OcaBoundedPropertyValue<Value: Numeric & Codable>: Codable, OcaParameterCountReflectable {
    static var responseParameterCount: OcaUint8 { 3 }
    
    public var value: Value
    public var minValue: Value
    public var maxValue: Value
    
    public init(value: Value, minValue: Value, maxValue: Value) {
        self.value = value
        self.minValue = minValue
        self.maxValue = maxValue
    }
}

public extension OcaBoundedPropertyValue {
    var absoluteRange: Value {
        self.maxValue - self.minValue
    }
}

public extension OcaBoundedPropertyValue where Value: BinaryFloatingPoint {
    /// returns value between 0.0 and 1.0
    var relativeValue: OcaFloat32 {
        OcaFloat32((self.value + self.maxValue) / self.absoluteRange)
    }
}

@propertyWrapper
public struct OcaBoundedProperty<Value: Numeric & Codable>: OcaPropertyChangeEventNotifiable, Codable {
    public typealias Property = OcaProperty<OcaBoundedPropertyValue<Value>>
    public typealias State = Property.State
    
    public var propertyIDs: [OcaPropertyID] {
        [_storage.propertyID]
    }

    fileprivate var _storage: Property
    
    public init(from decoder: Decoder) throws {
        fatalError()
    }
    
    /// Placeholder only
    public func encode(to encoder: Encoder) throws {
        fatalError()
    }
        
    @available(*, unavailable, message: """
               @OcaBoundedProperty is only available on properties of classes
               """)
    public var wrappedValue: State {
        get { fatalError() }
        nonmutating set { fatalError() }
    }
    
    public func refresh(_ object: OcaRoot) async {
        await _storage.refresh(object)
    }
    
    public var currentValue: State {
        _storage.currentValue
    }

    public func subscribe(_ object: OcaRoot) async {
        await _storage.subscribe(object)
    }

    public var description: String {
        _storage.description
    }

    init(propertyID: OcaPropertyID,
         getMethodID: OcaMethodID,
         setMethodID: OcaMethodID? = nil) {
        self._storage = OcaProperty(propertyID: propertyID,
                                    getMethodID: getMethodID,
                                    setMethodID: setMethodID,
                                    setValueTransformer: { $1.value })
    }
    
    public static subscript<T: OcaRoot>(
        _enclosingInstance object: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, State>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>) -> State {
        get {
            object[keyPath: storageKeyPath]._storage._referenceObject(_enclosingInstance: object)
            return object[keyPath: storageKeyPath]._storage._get(_enclosingInstance: object)
        }
        set {
            object[keyPath: storageKeyPath]._storage._referenceObject(_enclosingInstance: object)
            object[keyPath: storageKeyPath]._storage._set(_enclosingInstance: object, newValue)
        }
    }
    
    func onEvent(_ object: OcaRoot, _ eventData: Ocp1EventData) throws {
        precondition(eventData.event.eventID == OcaPropertyChangedEventID)
        
        let decoder = BinaryDecoder(config: .ocp1Configuration)
        let eventData = try decoder.decode(OcaPropertyChangedEventData<Value>.self,
                                           from: eventData.eventParameters)
        precondition(self.propertyIDs.contains(eventData.propertyID))

        guard case .success(var value) = _storage.currentValue else {
            throw Ocp1Error.noInitialValue
        }
        
        switch eventData.changeType {
        case .currentChanged:
            value.value = eventData.propertyValue
        case .minChanged:
            value.minValue = eventData.propertyValue
        case .maxChanged:
            value.maxValue = eventData.propertyValue
        default:
            throw Ocp1Error.unhandledEvent
        }
        
        _storage._set(_enclosingInstance: object, .success(value))
    }

#if canImport(SwiftUI) || canImport(TokamakShim)
    public var projectedValue: Binding<State> {
        Binding(get: { _storage.projectedValue.wrappedValue },
                set: { _storage.projectedValue.wrappedValue = $0 })
    }
#endif
}

#if canImport(SwiftUI) || canImport(TokamakShim)
#if canImport(SwiftUI)
import SwiftUI
#elseif canImport(TokamakShim)
import TokamakShim
#endif

public extension OcaBoundedProperty {
}
#endif
