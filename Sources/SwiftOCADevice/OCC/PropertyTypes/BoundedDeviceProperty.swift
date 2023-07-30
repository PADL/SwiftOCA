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
import SwiftOCA

@propertyWrapper
public struct OcaBoundedDeviceProperty<
    Value: Codable &
        Comparable
>: OcaDevicePropertyRepresentable {
    fileprivate var storage: Property

    public var propertyID: OcaPropertyID { storage.propertyID }
    public var getMethodID: OcaMethodID? { storage.getMethodID }
    public var setMethodID: OcaMethodID? { storage.setMethodID }

    public typealias Property = OcaDeviceProperty<OcaBoundedPropertyValue<Value>>

    public var wrappedValue: OcaBoundedPropertyValue<Value> {
        get { fatalError() }
        nonmutating set { fatalError() }
    }

    public var projectedValue: AnyAsyncSequence<Value> {
        async.map(\.value).eraseToAnyAsyncSequence()
    }

    var subject: AsyncCurrentValueSubject<OcaBoundedPropertyValue<Value>> {
        storage.subject
    }

    public init(
        wrappedValue: OcaBoundedPropertyValue<Value>,
        propertyID: OcaPropertyID,
        getMethodID: OcaMethodID? = nil,
        setMethodID: OcaMethodID? = nil
    ) {
        storage = OcaDeviceProperty(
            wrappedValue: wrappedValue,
            propertyID: propertyID,
            getMethodID: getMethodID,
            setMethodID: setMethodID
        )
    }

    func get(object: OcaRoot) async throws -> Ocp1Response {
        try await storage.get(object: object)
    }

    func set(object: OcaRoot, command: Ocp1Command) async throws {
        let value: Value = try object.decodeCommand(command)
        storage.set(
            object: object,
            OcaBoundedPropertyValue<Value>(value: value, in: storage.wrappedValue.range)
        )
    }

    public static subscript<T: OcaRoot>(
        _enclosingInstance object: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, OcaBoundedPropertyValue<Value>>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> OcaBoundedPropertyValue<Value> {
        get {
            object[keyPath: storageKeyPath].storage.get(object: object)
        }
        set {
            object[keyPath: storageKeyPath].storage.set(object: object, newValue)
        }
    }
}
