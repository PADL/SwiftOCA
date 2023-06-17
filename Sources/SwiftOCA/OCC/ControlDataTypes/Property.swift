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
import AsyncAlgorithms
import AsyncExtensions

public protocol OcaPropertyRepresentable {
    associatedtype Value: Codable
    
    var propertyIDs: [OcaPropertyID] { get }
    var currentValue: OcaProperty<Value>.State { get }

    func refresh(_ instance: OcaRoot) async
}

public extension OcaPropertyRepresentable {
    var isRequesting: Bool {
        currentValue.isRequesting
    }
}

protocol OcaPropertyChangeEventNotifiable: OcaPropertyRepresentable {
    @MainActor
    func onEvent(_ eventData: Ocp1EventData) throws
}

@propertyWrapper
public struct OcaProperty<Value: Codable>: Codable, OcaPropertyChangeEventNotifiable {
    /// All property IDs supported by this property
    public var propertyIDs: [OcaPropertyID] {
        [propertyID]
    }
    
    /// The OCA property ID
    let propertyID: OcaPropertyID
    
    /// The OCA get method ID
    let getMethodID: OcaMethodID
    
    /// The OCA set method ID, if present
    let setMethodID: OcaMethodID?
    
    public enum State {
        case initial
        case requesting
        case success(Value)
        case failure(Error)
        
        public var isRequesting: Bool {
            if case .initial = self {
                return true
            } else if case .requesting = self {
                return true
            } else {
                return false
            }
        }
    }
    
    private let subject: AsyncCurrentValueSubject<State>

    public init(from decoder: Decoder) throws {
        fatalError()
    }
    
    /// Placeholder only
    public func encode(to encoder: Encoder) throws {
        if case let .success(value) = self.wrappedValue {
            try value.encode(to: encoder)
        } else {
            fatalError()
        }
    }
        
    /// Placeholder only
    public var wrappedValue: State {
        get { fatalError() }
        nonmutating set { fatalError() }
    }
    
    public var projectedValue: any OcaPropertyRepresentable {
        self
    }
    
    public var currentValue: State {
        subject.value
    }
    
    public static subscript<T: OcaRoot>(
        _enclosingInstance instance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, State>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>) -> State {
        get {
            let subject = instance[keyPath: storageKeyPath].subject
            if case .initial = subject.value {
                Task { @MainActor in
                    await instance[keyPath: storageKeyPath].perform(instance) {
                        try await $0.getValueAndSubscribe(instance)
                    }
                }
            }
            return subject.value
        }
        set {
            Task { @MainActor in
                if case let .success(value) = newValue {
                    await instance[keyPath: storageKeyPath].perform(instance) {
                        try await $0.setValueIfMutable(instance, value)
                        return value
                    }
                } else if case .initial = newValue {
                    await instance[keyPath: storageKeyPath].refresh(instance)
                } else {
                    preconditionFailure("setter called with invalid value \(newValue)")
                }
            }
        }
    }

    /// setValueTransformer is a helper for OcaBoundedProperty
    typealias SetValueTransformer = (OcaRoot, Value) async throws -> Encodable
    private let setValueTransformer: SetValueTransformer?
    
    init(propertyID: OcaPropertyID,
         getMethodID: OcaMethodID,
         setMethodID: OcaMethodID? = nil,
         setValueTransformer: SetValueTransformer? = nil) {
        self.propertyID = propertyID
        self.getMethodID = getMethodID
        self.setMethodID = setMethodID
        self.subject = AsyncCurrentValueSubject(State.initial)
        self.setValueTransformer = setValueTransformer
    }
        
    @MainActor
    private func getValueAndSubscribe(_ instance: OcaRoot) async throws -> Value {
        let value: Value
        
        value = try await instance.sendCommandRrq(methodID: getMethodID)
        try await instance.subscribe()
        return value
    }
    
    @MainActor
    private func setValueIfMutable(_ instance: OcaRoot, _ value: Value) async throws {
        guard let setMethodID else { throw Ocp1Error.status(.notImplemented) }
        
        let newValue: Encodable
        
        if let setValueTransformer {
            newValue = try await setValueTransformer(instance, value)
        } else {
            newValue = value
        }
        
        // we'll get a notification so, don't require a reply
        try await instance.sendCommand(methodID: setMethodID, parameter: newValue)
    }
    
    @MainActor
    private func perform(_ instance: OcaRoot, _ block: @escaping (_ storage: Self) async throws -> Value) async {
        guard let connectionDelegate = instance.connectionDelegate else {
            subject.send(.failure(Ocp1Error.notConnected))
            return
        }

        if connectionDelegate.requestMonitor == nil {
            // connection state semaphore will be signalled when we are connected
            await connectionDelegate.connectionStateSemaphore.wait()
        }

        subject.send(.requesting)

        do {
            let value = try await block(self)
            subject.send(.success(value))
        } catch let error {
            debugPrint("performer received error \(error)")
            subject.send(.failure(error))
        }
        
        instance.objectWillChange.send()
    }
    
    @MainActor
    public func refresh(_ instance: OcaRoot) async {
        subject.send(.initial)
        instance.objectWillChange.send()
    }
    
    @MainActor
    func onEvent(_ eventData: Ocp1EventData) throws {
        precondition(eventData.event.eventID == OcaPropertyChangedEventID)
        
        let decoder = BinaryDecoder(config: .ocp1Configuration)
        let eventData = try decoder.decode(OcaPropertyChangedEventData<Value>.self, from: eventData.eventParameters)
        precondition(self.propertyIDs.contains(eventData.propertyID))

        // TODO: how to handle items being deleted
        if .currentChanged == eventData.changeType {
            self.subject.send(.success(eventData.propertyValue))
        } else {
            throw Ocp1Error.unhandledEvent
        }
    }
    
    @MainActor
    func onCompletion<T>(_ instance: OcaRoot,
                         _ block: @escaping (_ value: Value) async throws -> T) async throws -> T {
        repeat {
            if case .initial = self.subject.value {
                await perform(instance) {
                    try await $0.getValueAndSubscribe(instance)
                }
            }
            
            if case .success(let value) = self.subject.value {
                return try await block(value)
            } else if case .failure(let error) = self.subject.value {
                throw error
            }
        } while self.subject.value.isRequesting
        
        fatalError("should not be reached")
    }
}

extension OcaProperty.State: Equatable where Value: Equatable & Codable {
    public static func == (lhs: OcaProperty.State, rhs: OcaProperty.State) -> Bool {
        if case .initial = lhs,
           case .initial = rhs {
            return true
        } else if case .requesting = lhs,
                  case .requesting = rhs {
            return true
        } else if case let .success(lhsValue) = lhs,
                  case let .success(rhsValue) = rhs,
                  lhsValue == rhsValue {
            return true
        } else {
            return false
        }
    }
}
