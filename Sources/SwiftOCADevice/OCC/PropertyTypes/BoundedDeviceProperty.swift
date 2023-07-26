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

import BinaryCoder
import Foundation
import SwiftOCA

@propertyWrapper
public struct OcaBoundedDeviceProperty<
    Value: Codable &
        Comparable
>: OcaDevicePropertyRepresentable {
    public let propertyID: OcaPropertyID
    public let getMethodID: OcaMethodID?
    public let setMethodID: OcaMethodID?

    public typealias Property = OcaDeviceProperty<OcaBoundedPropertyValue<Value>>
    fileprivate var _storage: Property

    public var wrappedValue: OcaBoundedPropertyValue<Value> {
        get {
            _storage.wrappedValue
        }
        set {
            fatalError()
        }
    }

    public init(
        wrappedValue: OcaBoundedPropertyValue<Value>,
        propertyID: OcaPropertyID,
        getMethodID: OcaMethodID? = nil,
        setMethodID: OcaMethodID? = nil
    ) {
        _storage = OcaDeviceProperty(
            wrappedValue: wrappedValue,
            propertyID: propertyID,
            getMethodID: getMethodID,
            setMethodID: setMethodID
        )

        self.propertyID = propertyID
        self.getMethodID = getMethodID
        self.setMethodID = setMethodID
    }

    private func get(object: OcaRoot) -> OcaBoundedPropertyValue<Value> {
        _storage.get(object: object)
    }

    private mutating func set(object: OcaRoot, _ newValue: OcaBoundedPropertyValue<Value>) {
        _storage.set(object: object, newValue)
    }

    func get(object: OcaRoot) async throws -> Ocp1Response {
        try await _storage.get(object: object)
    }

    func makeValue(_ value: Value) -> OcaBoundedPropertyValue<Value> {
        OcaBoundedPropertyValue<Value>(value: value, in: _storage.wrappedValue.range)
    }

    mutating func set(object: OcaRoot, command: Ocp1Command) async throws {
        let value: Value = try object.decodeCommand(command)
        _storage.set(
            object: object,
            makeValue(value)
        )
    }

    func didSet(object: OcaRoot, _ newValue: Value) async throws {
        let event = OcaEvent(emitterONo: object.objectNumber, eventID: OcaPropertyChangedEventID)
        let encoder = BinaryEncoder(config: .ocp1Configuration)
        let parameters = OcaPropertyChangedEventData<Value>(
            propertyID: propertyID,
            propertyValue: newValue,
            changeType: .currentChanged
        )

        try await object.deviceDelegate?.notifySubscribers(
            event,
            parameters: try encoder.encode(parameters)
        )
    }

    public static subscript<T: OcaRoot>(
        _enclosingInstance object: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, OcaBoundedPropertyValue<Value>>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> OcaBoundedPropertyValue<Value> {
        get {
            object[keyPath: storageKeyPath].get(object: object)
        }
        set {
            object[keyPath: storageKeyPath].set(object: object, newValue)
            Task {
                try? await object[keyPath: storageKeyPath]
                    .didSet(object: object, newValue.value)
            }
        }
    }
}
