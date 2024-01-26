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
import SwiftOCA

private let OcaVectorPropertyParameterCount: OcaUint8 = 2

@propertyWrapper
public struct OcaVectorDeviceProperty<
    Value: Codable &
        Comparable & FixedWidthInteger & Sendable
>: OcaDevicePropertyRepresentable, Sendable {
    fileprivate var storage: Property

    // FIXME: support vector properties with multiple property IDs

    public var propertyID: OcaPropertyID { storage.propertyID }
    public var xPropertyID: OcaPropertyID { propertyID }
    public let yPropertyID: OcaPropertyID
    public var getMethodID: SwiftOCA.OcaMethodID? { storage.getMethodID }
    public var setMethodID: SwiftOCA.OcaMethodID? { storage.setMethodID }

    public typealias Property = OcaDeviceProperty<OcaVector2D<Value>>

    public var wrappedValue: OcaVector2D<Value> {
        get { storage.subject.value }
        nonmutating set { fatalError() }
    }

    public var projectedValue: AnyAsyncSequence<OcaVector2D<Value>> {
        async
    }

    var subject: AsyncCurrentValueSubject<OcaVector2D<Value>> {
        storage.subject
    }

    public init(
        wrappedValue: OcaVector2D<Value>,
        xPropertyID: OcaPropertyID,
        yPropertyID: OcaPropertyID,
        getMethodID: OcaMethodID? = nil,
        setMethodID: OcaMethodID? = nil
    ) {
        storage = OcaDeviceProperty(
            wrappedValue: wrappedValue,
            propertyID: xPropertyID,
            getMethodID: getMethodID,
            setMethodID: setMethodID
        )

        self.yPropertyID = yPropertyID
    }

    func getOcp1Response() async throws -> Ocp1Response {
        try await storage.getOcp1Response(parameterCount: OcaVectorPropertyParameterCount)
    }

    func getJsonValue() throws -> Any {
        let valueDict: [String: Value] =
            ["x": storage.subject.value.x,
             "y": storage.subject.value.y]

        return valueDict
    }

    func set(object: OcaRoot, _ newValue: OcaVector2D<Value>) {
        storage.set(object: object, newValue)
        notifySubscribers(object: object)
    }

    func set(object: OcaRoot, jsonValue: Any, device: OcaDevice) async throws {
        guard let valueDict = jsonValue as? [String: Value] else {
            throw Ocp1Error.status(.badFormat)
        }

        let x = valueDict["x"]
        let y = valueDict["y"]
        guard let x, let y else {
            throw Ocp1Error.status(.badFormat)
        }

        set(object: object, OcaVector2D(x: x, y: y))
    }

    func set(object: OcaRoot, command: Ocp1Command) async throws {
        let newValue: OcaVector2D<Value> = try object
            .decodeCommand(command, responseParameterCount: OcaVectorPropertyParameterCount)
        storage.set(object: object, newValue)
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

    private func notifySubscribers(object: OcaRoot, _ newValue: OcaVector2D<Value>) async throws {
        let event = OcaEvent(emitterONo: object.objectNumber, eventID: OcaPropertyChangedEventID)
        let xParameters = OcaPropertyChangedEventData<Value>(
            propertyID: xPropertyID,
            propertyValue: newValue.x,
            changeType: .currentChanged
        )

        try await object.deviceDelegate?.notifySubscribers(
            event,
            parameters: xParameters
        )

        let yParameters = OcaPropertyChangedEventData<Value>(
            propertyID: yPropertyID,
            propertyValue: newValue.y,
            changeType: .currentChanged
        )

        try await object.deviceDelegate?.notifySubscribers(
            event,
            parameters: yParameters
        )
    }

    public static subscript<T: OcaRoot>(
        _enclosingInstance object: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, OcaVector2D<Value>>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> OcaVector2D<Value> {
        get {
            object[keyPath: storageKeyPath].storage.get()
        }
        set {
            object[keyPath: storageKeyPath].storage.set(object: object, newValue)
            object[keyPath: storageKeyPath].notifySubscribers(object: object)
        }
    }
}
