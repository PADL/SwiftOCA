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

@_implementationOnly
import AnyCodable
import AsyncExtensions
import Foundation
import SwiftOCA

protocol OcaDevicePropertyRepresentable {
    associatedtype Value: Codable & Sendable

    // FIXME: support vector properties with multiple property IDs
    var propertyID: OcaPropertyID { get }
    var getMethodID: OcaMethodID? { get }
    var setMethodID: OcaMethodID? { get }
    var wrappedValue: Value { get }

    var subject: AsyncCurrentValueSubject<Value> { get }

    func get(object: OcaRoot) async throws -> Ocp1Response
    func getJsonValue(object: OcaRoot) throws -> Any

    func set(object: OcaRoot, command: Ocp1Command) async throws
    func set(object: OcaRoot, jsonValue: Any, device: AES70Device) async throws
}

extension OcaDevicePropertyRepresentable {
    func finish() {
        subject.send(.finished)
    }

    var async: AnyAsyncSequence<Value> {
        subject.eraseToAnyAsyncSequence()
    }
}

extension AsyncCurrentValueSubject: AsyncCurrentValueSubjectNilRepresentable
    where Element: ExpressibleByNilLiteral
{
    func sendNil() {
        send(nil)
    }
}

private protocol AsyncCurrentValueSubjectNilRepresentable {
    func sendNil()
}

@propertyWrapper
public struct OcaDeviceProperty<Value: Codable & Sendable>: OcaDevicePropertyRepresentable,
    Sendable
{
    var subject: AsyncCurrentValueSubject<Value>

    /// The OCA property ID
    public let propertyID: OcaPropertyID

    /// The OCA get method ID
    public let getMethodID: OcaMethodID?

    /// The OCA set method ID, if present
    public let setMethodID: OcaMethodID?

    /// Placeholder only
    public var wrappedValue: Value {
        get { subject.value }
        nonmutating set { fatalError() }
    }

    public var projectedValue: AnyAsyncSequence<Value> {
        async
    }

    public init(
        wrappedValue: Value,
        propertyID: OcaPropertyID,
        getMethodID: OcaMethodID? = nil,
        setMethodID: OcaMethodID? = nil
    ) {
        subject = AsyncCurrentValueSubject(wrappedValue)
        self.propertyID = propertyID
        self.getMethodID = getMethodID
        self.setMethodID = setMethodID
    }

    public init(
        propertyID: OcaPropertyID,
        getMethodID: OcaMethodID? = nil,
        setMethodID: OcaMethodID? = nil
    ) where Value: ExpressibleByNilLiteral {
        subject = AsyncCurrentValueSubject(nil)
        self.propertyID = propertyID
        self.getMethodID = getMethodID
        self.setMethodID = setMethodID
    }

    func get(object: OcaRoot) -> Value {
        subject.value
    }

    func set(object: OcaRoot, _ newValue: Value) {
        subject.send(newValue)
    }

    private func isNil(_ value: Value) -> Bool {
        if let value = value as? ExpressibleByNilLiteral,
           let value = value as? Value?,
           case .none = value
        {
            return true
        } else {
            return false
        }
    }

    func get(object: OcaRoot) async throws -> Ocp1Response {
        let value: Value = get(object: object)
        if isNil(value) {
            throw Ocp1Error.status(.parameterOutOfRange)
        }
        return try object.encodeResponse(value)
    }

    func getJsonValue(object: OcaRoot) throws -> Any {
        let jsonValue: Any

        if isNil(subject.value) {
            jsonValue = NSNull()
        } else if let value = subject.value as? [OcaRoot] {
            jsonValue = value.map(\.jsonObject)
        } else if !JSONSerialization.isValidJSONObject(subject.value) {
            let data = try JSONEncoder().encode(subject.value)
            jsonValue = try JSONDecoder().decode(AnyDecodable.self, from: data).value
        } else {
            jsonValue = subject.value
        }

        return jsonValue
    }

    func set(object: OcaRoot, command: Ocp1Command) async throws {
        let newValue: Value = try object.decodeCommand(command)
        set(object: object, newValue)
        notifySubscribers(object: object)
    }

    func set(object: OcaRoot, jsonValue: Any, device: AES70Device) async throws {
        if jsonValue is NSNull {
            if let subject = subject as? AsyncCurrentValueSubjectNilRepresentable {
                subject.sendNil()
            } else {
                throw Ocp1Error.status(.badFormat)
            }
        } else if let values = jsonValue as? [[String: Sendable]] {
            var objects = [OcaRoot]()
            for value in values {
                if let object = try? await device.deserialize(jsonObject: value) {
                    objects.append(object)
                }
            }
            subject.send(objects as! Value)
        } else if !JSONSerialization.isValidJSONObject(subject.value),
                  let jsonValue = jsonValue as? Codable
        {
            let data = try JSONEncoder().encode(jsonValue)
            let decodedValue = try JSONDecoder().decode(Value.self, from: data)
            subject.send(decodedValue)
        } else {
            guard let newValue = jsonValue as? Value else {
                throw Ocp1Error.status(.badFormat)
            }
            subject.send(newValue)
        }
        notifySubscribers(object: object)
    }

    private func notifySubscribers(object: OcaRoot) {
        if object.notificationTasks[propertyID] == nil {
            object.notificationTasks[propertyID] = Task<(), Error> {
                for try await value in self.async {
                    try? await notifySubscribers(object: object, value)
                }
            }
        }
    }

    private func notifySubscribers(object: OcaRoot, _ newValue: Value) async throws {
        let event = OcaEvent(emitterONo: object.objectNumber, eventID: OcaPropertyChangedEventID)
        let encoder = Ocp1Encoder()
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
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value {
        get {
            object[keyPath: storageKeyPath].get(object: object)
        }
        set {
            object[keyPath: storageKeyPath].set(object: object, newValue)
            object[keyPath: storageKeyPath].notifySubscribers(object: object)
        }
    }
}
