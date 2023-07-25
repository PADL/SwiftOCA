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

public protocol OcaDevicePropertyRepresentable {
    associatedtype Value = Codable

    var propertyIDs: [OcaPropertyID] { get }
    var getMethodID: OcaMethodID? { get }
    var setMethodID: OcaMethodID? { get }
    var wrappedValue: Value { get }

    func get(object: OcaRoot) async throws -> Ocp1Response
    mutating func set(object: OcaRoot, command: Ocp1Command) async throws
}

@propertyWrapper
public struct OcaDeviceProperty<Value: Codable>: OcaDevicePropertyRepresentable {
    /// All property IDs supported by this property
    public var propertyIDs: [OcaPropertyID] {
        [propertyID]
    }

    /// The OCA property ID
    public let propertyID: OcaPropertyID

    /// The OCA get method ID
    public let getMethodID: OcaMethodID?

    /// The OCA set method ID, if present
    public let setMethodID: OcaMethodID?

    /// Placeholder only
    public var wrappedValue: Value {
        get { _storage }
        nonmutating set { fatalError() }
    }

    private var _storage: Value

    public init(
        wrappedValue: Value,
        propertyID: OcaPropertyID,
        getMethodID: OcaMethodID? = nil,
        setMethodID: OcaMethodID? = nil
    ) {
        self.propertyID = propertyID
        self.getMethodID = getMethodID
        self.setMethodID = setMethodID
        _storage = wrappedValue
    }

    public init(
        propertyID: OcaPropertyID,
        getMethodID: OcaMethodID? = nil,
        setMethodID: OcaMethodID? = nil
    ) where Value: ExpressibleByNilLiteral {
        self.propertyID = propertyID
        self.getMethodID = getMethodID
        self.setMethodID = setMethodID
        _storage = nil
    }

    func _get(_enclosingInstance object: OcaRoot) -> Value {
        _storage
    }

    mutating func _set(_enclosingInstance object: OcaRoot, _ newValue: Value) {
        _storage = newValue
    }

    private func _didSet(_enclosingInstance object: OcaRoot, _ newValue: Value) async throws {
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
            object[keyPath: storageKeyPath]._get(_enclosingInstance: object)
        }
        set {
            object[keyPath: storageKeyPath]._set(_enclosingInstance: object, newValue)
            Task {
                try? await object[keyPath: storageKeyPath]
                    ._didSet(_enclosingInstance: object, newValue)
            }
        }
    }

    public func get(object: OcaRoot) async throws -> Ocp1Response {
        let value = _get(_enclosingInstance: object)
        if isNil(value) {
            throw Ocp1Error.status(.parameterOutOfRange)
        }
        return try object.encodeResponse(value)
    }

    public mutating func set(object: OcaRoot, command: Ocp1Command) async throws {
        let newValue: Value = try object.decodeCommand(command)
        _set(_enclosingInstance: object, newValue)
        try await _didSet(_enclosingInstance: object, newValue)
    }
}

func isNil<Value: Codable>(_ value: Value) -> Bool {
    if let value = value as? ExpressibleByNilLiteral,
       let value = value as? Value?,
       case .none = value
    {
        return true
    } else {
        return false
    }
}
