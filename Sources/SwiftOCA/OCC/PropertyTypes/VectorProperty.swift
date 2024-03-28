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
#if canImport(SwiftUI)
import SwiftUI
#endif

public struct OcaVector2D<T: Codable & Sendable & FixedWidthInteger>: Ocp1ParametersReflectable,
    Codable, Sendable
{
    public var x, y: T

    public init(x: T, y: T) {
        self.x = x
        self.y = y
    }
}

@propertyWrapper
public struct OcaVectorProperty<
    Value: Codable & Sendable &
        FixedWidthInteger
>: OcaPropertyChangeEventNotifiable, Codable, Sendable {
    public var valueType: Any.Type { Property.PropertyValue.self }

    @_spi(SwiftOCAPrivate)
    public var subject: AsyncCurrentValueSubject<PropertyValue> { _storage.subject }

    fileprivate var _storage: Property

    public typealias Property = OcaProperty<OcaVector2D<Value>>
    public typealias PropertyValue = Property.PropertyValue

    public var propertyIDs: [OcaPropertyID] {
        [xPropertyID, yPropertyID]
    }

    public let xPropertyID: OcaPropertyID
    public let yPropertyID: OcaPropertyID
    public let getMethodID: OcaMethodID
    public let setMethodID: OcaMethodID?

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
    public var wrappedValue: PropertyValue {
        get { fatalError() }
        nonmutating set { fatalError() }
    }

    public func refresh(_ object: OcaRoot) async {
        await _storage.refresh(object)
    }

    public var currentValue: PropertyValue {
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
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, PropertyValue>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> PropertyValue {
        get {
            #if canImport(SwiftUI)
            object[keyPath: storageKeyPath]._storage._referenceObject(_enclosingInstance: object)
            #endif
            return object[keyPath: storageKeyPath]._storage
                ._get(_enclosingInstance: object)
        }
        set {
            #if canImport(SwiftUI)
            object[keyPath: storageKeyPath]._storage._referenceObject(_enclosingInstance: object)
            #endif
            object[keyPath: storageKeyPath]._storage._set(_enclosingInstance: object, newValue)
        }
    }

    func onEvent(_ object: OcaRoot, event: OcaEvent, eventData data: Data) throws {
        precondition(event.eventID == OcaPropertyChangedEventID)

        let decoder = Ocp1Decoder()
        let eventData = try decoder.decode(
            OcaPropertyChangedEventData<Value>.self,
            from: data
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

    public var projectedValue: Self {
        self
    }

    @_spi(SwiftOCAPrivate) @discardableResult
    public func _getValue(
        _ object: OcaRoot,
        flags: OcaPropertyResolutionFlags = .defaultFlags
    ) async throws -> OcaVector2D<Value> {
        try await _storage._getValue(object, flags: flags)
    }

    public func getJsonValue(
        _ object: OcaRoot,
        flags: OcaPropertyResolutionFlags = .defaultFlags
    ) async throws -> [String: Any] {
        let value = try await _getValue(object, flags: flags)

        let valueDict: [String: Value] =
            [xPropertyID.description: value.x,
             yPropertyID.description: value.y]

        return valueDict
    }

    @_spi(SwiftOCAPrivate)
    public func _setValue(_ object: OcaRoot, _ anyValue: Any) async throws {
        throw Ocp1Error.notImplemented
    }
}

#if canImport(SwiftUI)
public extension OcaVectorProperty {
    var binding: Binding<PropertyValue> {
        Binding(
            get: {
                if let object = _storage.object {
                    return _storage._get(_enclosingInstance: object)
                } else {
                    return .initial
                }
            },
            set: {
                guard let object = _storage.object else { return }
                _storage._set(_enclosingInstance: object, $0)
            }
        )
    }
}
#endif
