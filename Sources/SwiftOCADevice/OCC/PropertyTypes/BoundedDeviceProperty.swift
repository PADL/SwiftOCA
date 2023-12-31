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

@preconcurrency
import AsyncExtensions
import SwiftOCA

@propertyWrapper
public struct OcaBoundedDeviceProperty<
    Value: Codable &
        Comparable & Sendable
>: OcaDevicePropertyRepresentable, Sendable {
    fileprivate var storage: Property

    public var propertyID: OcaPropertyID { storage.propertyID }
    public var getMethodID: OcaMethodID? { storage.getMethodID }
    public var setMethodID: OcaMethodID? { storage.setMethodID }

    public typealias Property = OcaDeviceProperty<OcaBoundedPropertyValue<Value>>

    public var wrappedValue: OcaBoundedPropertyValue<Value> {
        get { storage.subject.value }
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

    func getJsonValue(object: OcaRoot) throws -> Any {
        let valueDict: [String: Value] =
            ["v": storage.subject.value.value,
             "l": storage.subject.value.range.lowerBound,
             "u": storage.subject.value.range.upperBound]

        return valueDict
    }

    func set(object: OcaRoot, _ newValue: OcaBoundedPropertyValue<Value>) {
        storage.set(object: object, newValue)
        notifySubscribers(object: object)
    }

    func set(object: OcaRoot, jsonValue: Any, device: AES70Device) async throws {
        guard let valueDict = jsonValue as? [String: Value] else {
            throw Ocp1Error.status(.badFormat)
        }

        let value = valueDict["v"]
        let lowerBound = valueDict["l"]
        let upperBound = valueDict["u"]
        guard let value,
              let lowerBound,
              let upperBound,
              lowerBound <= upperBound,
              value >= lowerBound,
              value <= upperBound
        else {
            throw Ocp1Error.status(.badFormat)
        }

        set(
            object: object,
            OcaBoundedPropertyValue<Value>(value: value, in: lowerBound...upperBound)
        )
    }

    func set(object: OcaRoot, command: Ocp1Command) async throws {
        let value: Value = try object.decodeCommand(command)
        // check it is in range
        if value < storage.wrappedValue.range.lowerBound ||
            value > storage.wrappedValue.range.upperBound
        {
            throw Ocp1Error.status(.parameterOutOfRange)
        }
        storage.set(
            object: object,
            OcaBoundedPropertyValue<Value>(value: value, in: storage.wrappedValue.range)
        )
        notifySubscribers(object: object)
    }

    private func notifySubscribers(object: OcaRoot) {
        if object.notificationTasks[propertyID] == nil {
            object.notificationTasks[propertyID] = Task<(), Error> {
                for try await value in self.async {
                    try? await notifySubscribers(object: object, value.value)
                }
            }
        }
    }

    private func notifySubscribers(object: OcaRoot, _ newValue: Value) async throws {
        let event = OcaEvent(emitterONo: object.objectNumber, eventID: OcaPropertyChangedEventID)
        let encoder = Ocp1BinaryEncoder()
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
            object[keyPath: storageKeyPath].storage.get(object: object)
        }
        set {
            object[keyPath: storageKeyPath].storage.set(object: object, newValue)
            object[keyPath: storageKeyPath].notifySubscribers(object: object)
        }
    }
}
