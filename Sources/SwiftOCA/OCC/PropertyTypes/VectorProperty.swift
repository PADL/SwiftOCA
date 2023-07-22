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
#if canImport(SwiftUI)
import SwiftUI
#endif

public struct OcaVector2D<T: Codable & FixedWidthInteger>: Codable, OcaParameterCountReflectable {
    static var responseParameterCount: OcaUint8 { 2 }

    var x, y: T
}

@propertyWrapper
public struct OcaVectorProperty<
    Value: Codable &
        FixedWidthInteger
>: OcaPropertyChangeEventNotifiable, Codable {
    public typealias Property = OcaProperty<OcaVector2D<Value>>
    public typealias State = Property.State

    public var propertyIDs: [OcaPropertyID] {
        [xPropertyID, yPropertyID]
    }

    public let xPropertyID: OcaPropertyID
    public let yPropertyID: OcaPropertyID
    public let getMethodID: OcaMethodID
    public let setMethodID: OcaMethodID?
    public var subject: AsyncCurrentValueSubject<State> { _storage.subject }

    fileprivate var _storage: Property

    public init(from decoder: Decoder) throws {
        fatalError()
    }

    /// Placeholder only
    public func encode(to encoder: Encoder) throws {
        fatalError()
    }

    @available(*, unavailable, message: """
    @OcaVectorProperty is only available on properties of classes
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

    init(
        xPropertyID: OcaPropertyID,
        yPropertyID: OcaPropertyID,
        getMethodID: OcaMethodID,
        setMethodID: OcaMethodID? = nil
    ) {
        self.xPropertyID = xPropertyID
        self.yPropertyID = yPropertyID
        self.getMethodID = getMethodID
        self.setMethodID = setMethodID
        _storage = OcaProperty(
            propertyID: OcaPropertyID("1.1"),
            getMethodID: getMethodID,
            setMethodID: setMethodID
        )
    }

    public static subscript<T: OcaRoot>(
        _enclosingInstance object: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, State>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> State {
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
        let eventData = try decoder.decode(
            OcaPropertyChangedEventData<Value>.self,
            from: eventData.eventParameters
        )
        precondition(propertyIDs.contains(eventData.propertyID))

        // TODO: support add/delete
        switch eventData.changeType {
        case .currentChanged:
            guard case let .success(subjectValue) = _storage.currentValue else {
                throw Ocp1Error.noInitialValue
            }

            let isX = eventData.propertyID == xPropertyID
            var xy = OcaVector2D<Value>(x: 0, y: 0)

            if isX {
                xy.x = eventData.propertyValue
                xy.y = subjectValue.y
            } else {
                xy.x = subjectValue.x
                xy.y = eventData.propertyValue
            }
            _storage._send(_enclosingInstance: object, .success(xy))
        default:
            throw Ocp1Error.unhandledEvent
        }
    }

    #if canImport(SwiftUI)
    public var projectedValue: Binding<State> {
        Binding(
            get: { _storage.projectedValue.wrappedValue },
            set: { _storage.projectedValue.wrappedValue = $0 }
        )
    }
    #endif
}
