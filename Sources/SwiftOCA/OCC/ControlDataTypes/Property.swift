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

public protocol OcaPropertyRepresentable: CustomStringConvertible {
    associatedtype Value: Codable
    
    var propertyIDs: [OcaPropertyID] { get }
    var currentValue: OcaProperty<Value>.State { get }

    func refresh(_ instance: OcaRoot) async
    func subscribe(_ instance: OcaRoot) async
}

public extension OcaPropertyRepresentable {
    var isRequesting: Bool {
        currentValue.isRequesting
    }
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
    let getMethodID: OcaMethodID?
    
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

    public var description: String {
        if case .success(let value) = subject.value {
            return String(describing: value)
        } else {
            return ""
        }
    }
    
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
    
    /// It's not possible to wrap `subscript(_enclosingInstance:wrapped:storage:)` because we can't
    /// cast struct key paths to `ReferenceWritableKeyPath`. For property wrapper wrappers, use these internal
    /// get/set functions.

    func _get(_enclosingInstance instance: OcaRoot) -> State {
        switch subject.value {
        case .initial:
            Task { @MainActor in
                await perform(instance) {
                    try await $0.getValueAndSubscribe(instance)
                }
            }
        default:
            break
        }
        return subject.value
    }

    func _set(_enclosingInstance instance: OcaRoot, _ newValue: State) {
        Task { @MainActor in
            if case let .success(value) = newValue {
                await perform(instance) {
                    try await $0.setValueIfMutable(instance, value)
                    return value
                }
            } else if case .initial = newValue {
                await refresh(instance)
            } else {
                preconditionFailure("setter called with invalid value \(newValue)")
            }
        }
    }
        
    public static subscript<T: OcaRoot>(
        _enclosingInstance instance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, State>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>) -> State {
        get {
            instance[keyPath: storageKeyPath]._get(_enclosingInstance: instance)
        }
        set {
            instance[keyPath: storageKeyPath]._set(_enclosingInstance: instance, newValue)
        }
    }

    /// setValueTransformer is a helper for OcaBoundedProperty
    typealias SetValueTransformer = (OcaRoot, Value) async throws -> Encodable
    private let setValueTransformer: SetValueTransformer?
    
    init(propertyID: OcaPropertyID,
         getMethodID: OcaMethodID? = nil,
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
        guard let getMethodID else {
            throw Ocp1Error.propertyIsImmutable
        }

        let value: Value = try await instance.sendCommandRrq(methodID: getMethodID)

        // do this in the background, otherwise UI refresh performance is poor
        Task.detached {
            try await instance.subscribe()
        }
        
        return value
    }
    
    @MainActor
    private func setValueIfMutable(_ instance: OcaRoot, _ value: Value) async throws {
        guard let setMethodID else {
            throw Ocp1Error.propertyIsImmutable
        }
        
        let newValue: Encodable
        
        if let setValueTransformer {
            newValue = try await setValueTransformer(instance, value)
        } else {
            newValue = value
        }
        
        if try await instance.isSubscribed {
            // we'll get a notification (hoepfully) so, don't require a reply
            try await instance.sendCommand(methodID: setMethodID, parameter: newValue)
        } else {
            try await instance.sendCommandRrq(methodID: setMethodID, parameter: newValue)
        }
    }
    
    private func perform(_ instance: OcaRoot, _ block: @escaping (_ storage: Self) async throws -> Value) async {
        guard let connectionDelegate = instance.connectionDelegate else {
            subject.send(.failure(Ocp1Error.noConnectionDelegate))
            return
        }
        
        subject.send(.requesting)
        
        guard await connectionDelegate.isConnected else {
            debugPrint("property handler called before connection established")
            return
        }
        
        do {
            let value = try await block(self)
            subject.send(.success(value))
        } catch is CancellationError {
            // if task cancelled due to a view being dismissed, reset state to initial
            subject.send(.initial)
        } catch let error {
            debugPrint("property handler received error from device: \(error)")
            subject.send(.failure(error))
        }
        
        Task { @MainActor in
            instance.objectWillChange.send()
        }
    }
    
    public func subscribe(_ instance: OcaRoot) async {
        guard case .initial = subject.value else {
            return
        }
        
        // FIXME: is this safe to run off main thread?
        await perform(instance) {
            try await $0.getValueAndSubscribe(instance)
        }
    }

    public func refresh(_ instance: OcaRoot) async {
        subject.send(.initial)
        Task { @MainActor in
            instance.objectWillChange.send()
        }
    }
    
    func onEvent(_ instance: OcaRoot, _ eventData: Ocp1EventData) throws {
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
        guard let connectionDelegate = instance.connectionDelegate else {
            throw Ocp1Error.noConnectionDelegate
        }
        
        guard await connectionDelegate.isConnected else {
            throw Ocp1Error.notConnected
        }

        let result = try await withTimeout(seconds: connectionDelegate.responseTimeout) {
            await Task {
                repeat {
                    await subscribe(instance)
                    
                    if case .success(let value) = self.subject.value {
                        return try await block(value)
                    } else if case .failure(let error) = self.subject.value {
                        throw error
                    } else {
                        await Task.yield()
                    }
                } while !Task.isCancelled
                throw Ocp1Error.responseTimeout
            }.result
        }
        
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            debugPrint("property completion handler failed \(error)")
            throw error
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

extension OcaProperty.State: Hashable where Value: Hashable & Codable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .success(value):
            hasher.combine(value)
        default:
            break
        }
    }
}
