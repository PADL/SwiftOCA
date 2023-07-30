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

protocol OcaDevicePropertyRepresentable {
    associatedtype Value: Codable

    // FIXME: support vector properties with multiple property IDs
    var propertyID: OcaPropertyID { get }
    var getMethodID: OcaMethodID? { get }
    var setMethodID: OcaMethodID? { get }
    var wrappedValue: Value { get }

    var subject: AsyncCurrentValueSubject<Value> { get }

    func get(object: OcaRoot) async throws -> Ocp1Response
    func set(object: OcaRoot, command: Ocp1Command) async throws
}

extension OcaDevicePropertyRepresentable {
    func finish() {
        subject.send(.finished)
    }

    public var async: AnyAsyncSequence<Value> {
        subject.eraseToAnyAsyncSequence()
    }

    public var projectedValue: AnyAsyncSequence<Value> {
        async
    }
}

@propertyWrapper
public struct OcaDeviceProperty<Value: Codable>: OcaDevicePropertyRepresentable {
    var subject: AsyncCurrentValueSubject<Value>

    /// The OCA property ID
    public let propertyID: OcaPropertyID

    /// The OCA get method ID
    public let getMethodID: OcaMethodID?

    /// The OCA set method ID, if present
    public let setMethodID: OcaMethodID?

    /// Placeholder only
    public var wrappedValue: Value {
        get { fatalError() }
        nonmutating set { fatalError() }
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

    func set(object: OcaRoot, command: Ocp1Command) async throws {
        let newValue: Value = try object.decodeCommand(command)
        set(object: object, newValue)

        if object.notificationTasks[propertyID] == nil {
            object.notificationTasks[propertyID] = Task<(), Error> {
                for try await value in self.async {
                    try? await notifySubscribers(object: object, value)
                }
            }
        }
    }

    func notifySubscribers(object: OcaRoot, _ newValue: Value) async throws {
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
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value {
        get {
            object[keyPath: storageKeyPath].get(object: object)
        }
        set {
            object[keyPath: storageKeyPath].set(object: object, newValue)
        }
    }
}
