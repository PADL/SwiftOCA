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
import Combine

@propertyWrapper
public struct OcaProperty<Value: Codable>: Codable, OcaPropertyChangeEventNotifiable {
    var propertyIDs: [OcaPropertyID] {
        [propertyID]
    }
    
    public let propertyID: OcaPropertyID
    public let getMethodID: OcaMethodID
    public let setMethodID: OcaMethodID?
    
    public enum State {
        case initial
        case requesting
        // TODO: rename to set
        case success(Value)
        case failure(Error)
        // TODO: add, remove, replace member
    }
    
    public init(from decoder: Decoder) throws {
        fatalError()
    }
    
    public func encode(to encoder: Encoder) throws {
        if case let .success(value) = self.wrappedValue {
            try value.encode(to: encoder)
        } else {
            fatalError()
        }
    }
    
    private let subject: CurrentValueSubject<State, Never>
    
    public var wrappedValue: State {
        get { fatalError() }
        nonmutating set { fatalError() }
    }
    
    typealias GetValueCallback = (OcaRoot) async throws -> Value
    private let getValueCallback: GetValueCallback?
    
    typealias SetValueCallback = (OcaRoot, Value) async throws -> Void
    private let setValueCallback: SetValueCallback?
    
    init(propertyID: OcaPropertyID,
         getMethodID: OcaMethodID,
         setMethodID: OcaMethodID? = nil,
         getValue: GetValueCallback? = nil,
         setValue: SetValueCallback? = nil) {
        self.propertyID = propertyID
        self.getMethodID = getMethodID
        self.setMethodID = setMethodID
        self.subject = CurrentValueSubject(State.initial)
        self.getValueCallback = getValue
        self.setValueCallback = setValue
    }
    
    public var projectedValue: AnyPublisher<State, Never> {
        return self.getPublisher()
    }
    
    func getPublisher() -> AnyPublisher<State, Never> {
        subject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    private func subscribeAndGetValue(_ instance: OcaRoot) async throws -> Value {
        //try await instance.subscribe()
        if let getValueCallback {
            return try await getValueCallback(instance)
        } else {
            return try await instance.sendCommandRrq(methodID: getMethodID)
        }
    }
    
    private func setValueIfMutable(_ instance: OcaRoot, _ value: Value) async throws {
        guard let setMethodID else { throw Ocp1Error.status(.notImplemented) }
        
        if let setValueCallback {
            try await setValueCallback(instance, value)
        } else {
            try await instance.sendCommandRrq(methodID: setMethodID, parameter: value)
        }
    }
    
    private func perform(_ instance: OcaRoot, _ block: @escaping (_ storage: Self) async throws -> Value) {
        guard let connectionDelegate = instance.connectionDelegate else {
            subject.send(.failure(Ocp1Error.notConnected))
            return
        }

        Task { @MainActor in
            if connectionDelegate.requestMonitor == nil {
                precondition(connectionDelegate.responseMonitor == nil)
                // connection state semaphore will be signalled when we are connected
                await connectionDelegate.connectionStateSemaphore.wait()
            }
            subject.send(.requesting)
            
            do {
                let value = try await block(self)
                subject.send(.success(value))
            } catch let error {
                subject.send(.failure(error))
            }
            
            instance.objectWillChange.send()
        }
    }
    
    public static subscript<T: OcaRoot>(
        _enclosingInstance instance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, State>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>) -> State {
        get {
            let subject = instance[keyPath: storageKeyPath].subject
            if case .initial = subject.value {
                instance[keyPath: storageKeyPath].perform(instance) {
                    try await $0.subscribeAndGetValue(instance)
                }
            }
            return subject.value
        }
        set {
            guard case let .success(value) = newValue else {
                preconditionFailure("setter called with non-success value \(newValue)")
            }
            instance[keyPath: storageKeyPath].perform(instance) {
                try await $0.setValueIfMutable(instance, value)
                return value
            }
        }
    }

    @MainActor
    func onEvent(_ eventData: Ocp1EventData) throws {
        precondition(eventData.event.eventID == OcaPropertyChangedEventID)
        
        let decoder = BinaryDecoder(config: .ocp1Configuration)
        let eventData = try decoder.decode(OcaPropertyChangedEventData<Value>.self, from: eventData.eventParameters)
        guard eventData.propertyID == self.propertyID else { return }
        
        // TODO: support add/delete perhaps with new State cases
        switch eventData.changeType {
        case .currentChanged:
            self.subject.send(.success(eventData.propertyValue))
            break
        default:
            break
        }
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
