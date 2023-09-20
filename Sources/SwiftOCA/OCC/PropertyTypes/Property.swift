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

import AsyncAlgorithms
import AsyncExtensions
import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public protocol OcaPropertyRepresentable: CustomStringConvertible {
    associatedtype Value: Codable
    typealias State = OcaProperty<Value>.State

    var propertyIDs: [OcaPropertyID] { get }
    var currentValue: State { get }
    var async: AnyAsyncSequence<State> { get }

    func refresh(_ object: OcaRoot) async
    func subscribe(_ object: OcaRoot) async
}

public extension OcaPropertyRepresentable {
    var hasValueOrError: Bool {
        currentValue.hasValueOrError
    }
}

protocol OcaPropertySubjectRepresentable: OcaPropertyRepresentable {
    var subject: AsyncCurrentValueSubject<State> { get }
}

extension OcaPropertySubjectRepresentable {
    public var async: AnyAsyncSequence<State> {
        subject.eraseToAnyAsyncSequence()
    }

    func finish() {
        subject.send(.finished)
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
        /// no value retrieved from device yet
        case initial
        /// value retrieved from device
        case success(Value)
        /// value could not be retrieved from device
        case failure(Error)

        public var hasValueOrError: Bool {
            if case .initial = self {
                return false
            } else {
                return true
            }
        }

        public func asOptionalResult() -> Result<Value?, Error> {
            switch self {
            case .initial:
                return .success(nil)
            case let .success(value):
                return .success(value)
            case let .failure(error):
                return .failure(error)
            }
        }
    }

    let subject: AsyncCurrentValueSubject<State>

    public var description: String {
        if case let .success(value) = subject.value {
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
        fatalError()
    }

    /// Placeholder only
    @available(*, unavailable, message: """
    @OcaProperty is only available on properties of classes
    """)
    public var wrappedValue: State {
        get { fatalError() }
        nonmutating set { fatalError() }
    }

    #if canImport(SwiftUI)
    private weak var object: OcaRoot?

    mutating func _referenceObject(_enclosingInstance object: OcaRoot) {
        self.object = object
    }
    #endif

    public var currentValue: State {
        subject.value
    }

    func _send(_enclosingInstance object: OcaRoot, _ state: State) {
        #if canImport(Combine) || canImport(OpenCombine)
        DispatchQueue.main.async {
            object.objectWillChange.send()
        }
        #endif
        subject.send(state)
    }

    /// It's not possible to wrap `subscript(_enclosingInstance:wrapped:storage:)` because we can't
    /// cast struct key paths to `ReferenceWritableKeyPath`. For property wrapper wrappers, use
    /// these internal
    /// get/set functions.

    func _get(_enclosingInstance object: OcaRoot) -> State {
        switch subject.value {
        case .initial:
            Task {
                await perform(object) {
                    try await $0.getValueAndSubscribe(object)
                }
            }
        default:
            break
        }
        return subject.value
    }

    func _set(_enclosingInstance object: OcaRoot, _ newValue: State) {
        Task {
            switch newValue {
            case let .success(value):
                await perform(object) {
                    try await $0.setValueIfMutable(object, value)
                }
            case .initial:
                await refresh(object)
            default:
                preconditionFailure("setter called with invalid value \(newValue)")
            }
        }
    }

    public static subscript<T: OcaRoot>(
        _enclosingInstance object: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, State>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> State {
        get {
            #if canImport(SwiftUI)
            object[keyPath: storageKeyPath]._referenceObject(_enclosingInstance: object)
            #endif
            return object[keyPath: storageKeyPath]._get(_enclosingInstance: object)
        }
        set {
            #if canImport(SwiftUI)
            object[keyPath: storageKeyPath]._referenceObject(_enclosingInstance: object)
            #endif
            object[keyPath: storageKeyPath]._set(_enclosingInstance: object, newValue)
        }
    }

    /// setValueTransformer is a helper for OcaBoundedProperty
    typealias SetValueTransformer = (OcaRoot, Value) async throws -> Encodable
    private let setValueTransformer: SetValueTransformer?

    init(
        propertyID: OcaPropertyID,
        getMethodID: OcaMethodID? = nil,
        setMethodID: OcaMethodID? = nil,
        setValueTransformer: SetValueTransformer? = nil
    ) {
        self.propertyID = propertyID
        self.getMethodID = getMethodID
        self.setMethodID = setMethodID
        subject = AsyncCurrentValueSubject(State.initial)
        self.setValueTransformer = setValueTransformer
    }

    private func getValueAndSubscribe(_ object: OcaRoot) async throws {
        guard let getMethodID else {
            throw Ocp1Error.propertyIsImmutable
        }

        let value: Value = try await object.sendCommandRrq(methodID: getMethodID)

        // do this in the background, otherwise UI refresh performance is poor
        Task.detached {
            try await object.subscribe()
        }

        _send(_enclosingInstance: object, .success(value))
    }

    private func setValueIfMutable(_ object: OcaRoot, _ value: Value) async throws {
        guard let setMethodID else {
            throw Ocp1Error.propertyIsImmutable
        }

        let newValue: Encodable

        if let setValueTransformer {
            newValue = try await setValueTransformer(object, value)
        } else {
            newValue = value
        }

        if try await object.isSubscribed {
            // we'll get a notification (hoepfully) so, don't require a reply
            try await object.sendCommand(methodID: setMethodID, parameter: newValue)
        } else {
            try await object.sendCommandRrq(methodID: setMethodID, parameter: newValue)
        }
    }

    private func perform(
        _ object: OcaRoot,
        _ block: @escaping (_ storage: Self) async throws -> ()
    ) async {
        guard let connectionDelegate = object.connectionDelegate else {
            subject.send(.failure(Ocp1Error.noConnectionDelegate))
            return
        }

        guard await connectionDelegate.isConnected else {
            debugPrint("property handler called before connection established")
            return
        }

        do {
            try await block(self)
        } catch is CancellationError {
            // if task cancelled due to a view being dismissed, reset state to initial
            _send(_enclosingInstance: object, .initial)
        } catch {
            debugPrint(
                "property handler for \(object) property \(propertyID) received error from device: \(error)"
            )
            _send(_enclosingInstance: object, .failure(error))
        }
    }

    public func subscribe(_ object: OcaRoot) async {
        guard case .initial = subject.value else {
            return
        }

        await perform(object) {
            try await $0.getValueAndSubscribe(object)
        }
    }

    public func refresh(_ object: OcaRoot) async {
        _send(_enclosingInstance: object, .initial)
    }

    func onEvent(_ object: OcaRoot, event: OcaEvent, eventData data: Data) throws {
        precondition(event.eventID == OcaPropertyChangedEventID)

        let decoder = Ocp1BinaryDecoder()
        let eventData = try decoder.decode(
            OcaPropertyChangedEventData<Value>.self,
            from: data
        )
        precondition(propertyIDs.contains(eventData.propertyID))

        // TODO: how to handle items being deleted
        if eventData.changeType == .currentChanged {
            _send(_enclosingInstance: object, .success(eventData.propertyValue))
        } else {
            throw Ocp1Error.unhandledEvent
        }
    }

    func onCompletion<T>(
        _ object: OcaRoot,
        _ block: @escaping (_ value: Value) async throws -> T
    ) async throws -> T {
        guard let connectionDelegate = object.connectionDelegate else {
            throw Ocp1Error.noConnectionDelegate
        }

        guard await connectionDelegate.isConnected else {
            throw Ocp1Error.notConnected
        }

        let result = try await withThrowingTimeout(seconds: connectionDelegate.options.responseTimeout) {
            await Task {
                repeat {
                    await subscribe(object)

                    if case let .success(value) = self.subject.value {
                        return try await block(value)
                    } else if case let .failure(error) = self.subject.value {
                        throw error
                    } else {
                        await Task.yield()
                    }
                } while !Task.isCancelled
                debugPrint("property completion handler was cancelled")
                throw Ocp1Error.responseTimeout
            }.result
        }

        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            debugPrint("property completion handler failed \(error)")
            throw error
        }
    }

    #if canImport(SwiftUI)
    public var projectedValue: Binding<State> {
        Binding(
            get: {
                if let object {
                    return _get(_enclosingInstance: object)
                } else {
                    return .initial
                }
            },
            set: {
                guard let object else { return }
                _set(_enclosingInstance: object, $0)
            }
        )
    }
    #endif
}

extension OcaProperty.State: Equatable where Value: Equatable & Codable {
    public static func == (lhs: OcaProperty.State, rhs: OcaProperty.State) -> Bool {
        if case .initial = lhs,
           case .initial = rhs
        {
            return true
        } else if case let .success(lhsValue) = lhs,
                  case let .success(rhsValue) = rhs,
                  lhsValue == rhsValue
        {
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
