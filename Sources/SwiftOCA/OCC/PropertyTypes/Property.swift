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
#if canImport(Darwin)
import Observation
#endif

public struct OcaPropertyResolutionFlags: OptionSet, Sendable {
  public typealias RawValue = UInt32

  public let rawValue: RawValue

  public init(rawValue: RawValue) {
    self.rawValue = rawValue
  }

  /// return a cached value, if one is preent
  public static let returnCachedValue = OcaPropertyResolutionFlags(rawValue: 1 << 0)
  /// if previous error was cached, return that
  public static let throwCachedError = OcaPropertyResolutionFlags(rawValue: 1 << 1)
  /// cache new values
  public static let cacheValue = OcaPropertyResolutionFlags(rawValue: 1 << 2)
  /// subscribe to property events
  public static let subscribeEvents = OcaPropertyResolutionFlags(rawValue: 1 << 3)
  public static let cacheErrors = OcaPropertyResolutionFlags(rawValue: 1 << 4)

  public static let defaultFlags =
    OcaPropertyResolutionFlags([.returnCachedValue, .throwCachedError, .cacheValue,
                                .subscribeEvents, .cacheErrors])
}

public protocol OcaPropertyRepresentable: CustomStringConvertible {
  associatedtype Value: Codable & Sendable
  typealias PropertyValue = OcaProperty<Value>.PropertyValue

  var valueType: Any.Type { get }

  var async: AnyAsyncSequence<Result<Any, Error>> { get }

  var propertyIDs: [OcaPropertyID] { get }
  var currentValue: PropertyValue { get }

  func refresh(_ object: OcaRoot) async
  func subscribe(_ object: OcaRoot) async

  func getJsonValue(_ object: OcaRoot, flags: OcaPropertyResolutionFlags) async throws
    -> [String: Any]
}

public extension OcaPropertyRepresentable {
  var hasValueOrError: Bool {
    currentValue.hasValueOrError
  }
}

/// this is private API because it allows the underlying storage to be accessed without
/// updating the value on the controlled device. it's useful for the `ocacli` command
/// line tool which manages its own cache but shouldn't be used by applications generally
@_spi(SwiftOCAPrivate)
public
protocol OcaPropertySubjectRepresentable: OcaPropertyRepresentable {
  var setMethodID: OcaMethodID? { get }

  var subject: AsyncCurrentValueSubject<PropertyValue> { get }

  func _setValue(_ object: OcaRoot, _ anyValue: Any) async throws

  func _getValue(_ object: OcaRoot, flags: OcaPropertyResolutionFlags) async throws -> Value
}

extension OcaPropertySubjectRepresentable {
  public var async: AnyAsyncSequence<Result<Any, Error>> {
    subject.compactMap { value in
      switch value {
      case .initial:
        nil
      case let .success(value):
        .success(value)
      case let .failure(error):
        .failure(error)
      }
    }.eraseToAnyAsyncSequence()
  }

  var isImmutable: Bool {
    setMethodID == nil
  }

  func finish() {
    subject.send(.finished)
  }

  func refreshAndSubscribe(_ object: OcaRoot) async {
    await refresh(object)
    _ = try? await _getValue(object, flags: .defaultFlags)
  }
}

@propertyWrapper
public struct OcaProperty<Value: Codable & Sendable>: Codable, Sendable,
  OcaPropertyChangeEventNotifiable
{
  public var valueType: Any.Type { Value.self }

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

  public enum PropertyValue: Sendable {
    /// no value retrieved from device yet
    case initial
    /// value retrieved from device
    case success(Value)
    /// value could not be retrieved from device
    case failure(Error)

    public var hasValueOrError: Bool {
      if case .initial = self {
        false
      } else {
        true
      }
    }

    public func asOptionalResult() -> Result<Value?, Error> {
      switch self {
      case .initial:
        .success(nil)
      case let .success(value):
        .success(value)
      case let .failure(error):
        .failure(error)
      }
    }
  }

  private(set) var _send: @Sendable (_: OcaRoot?, _: PropertyValue) -> ()

  @_spi(SwiftOCAPrivate)
  public let subject: AsyncCurrentValueSubject<PropertyValue>

  public var description: String {
    if case let .success(value) = subject.value {
      String(describing: value)
    } else {
      ""
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
  public var wrappedValue: PropertyValue {
    get { fatalError() }
    nonmutating set { fatalError() }
  }

  public var currentValue: PropertyValue {
    subject.value
  }

  /// It's not possible to wrap `subscript(_enclosingInstance:wrapped:storage:)` because we can't
  /// cast struct key paths to `ReferenceWritableKeyPath`. For property wrapper wrappers, use
  /// these internal get/set functions.

  func _get(
    _enclosingInstance object: OcaRoot
  ) -> PropertyValue {
    switch subject.value {
    case .initial:
      Task {
        try await _getValue(object)
      }
    default:
      break
    }
    return subject.value
  }

  func _set(
    _enclosingInstance object: OcaRoot,
    _ newValue: PropertyValue
  ) {
    Task {
      switch newValue {
      case let .success(value):
        do {
          try await setValueIfMutable(object, value)
        } catch is CancellationError {
          // if task cancelled due to a view being dismissed, reset state to initial
          _send(object, .initial)
        } catch {
          _send(object, .failure(error))
          await object.connectionDelegate?.logger.trace(
            "set property handler for \(object) property \(propertyID) received error from device: \(error)"
          )
        }
      case .initial:
        await refresh(object)
      default:
        preconditionFailure("setter called with invalid value \(newValue)")
      }
    }
  }

  mutating func _registerObservable<T: OcaRoot>(
    _enclosingInstance object: T,
    wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, PropertyValue>
  ) {
    #if canImport(Darwin)
    object.access(keyPath: wrappedKeyPath)
    _send = { @Sendable [subject] object, newValue in
      guard let object else { return }
      (object as! T).withMutation(keyPath: wrappedKeyPath) {
        subject.send(newValue)
      }
    }
    #endif
  }

  public static subscript<T: OcaRoot>(
    _enclosingInstance object: T,
    wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, PropertyValue>,
    storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
  ) -> PropertyValue {
    get {
      object[keyPath: storageKeyPath]._registerObservable(
        _enclosingInstance: object,
        wrapped: wrappedKeyPath
      )
      return object[keyPath: storageKeyPath]
        ._get(_enclosingInstance: object)
    }
    set {
      object[keyPath: storageKeyPath]
        ._set(_enclosingInstance: object, newValue)
    }
  }

  /// setValueTransformer is a helper for OcaBoundedProperty
  typealias SetValueTransformer = @Sendable (OcaRoot, Value) async throws -> Encodable
  private let setValueTransformer: SetValueTransformer?

  init(
    propertyID: OcaPropertyID,
    getMethodID: OcaMethodID?,
    setMethodID: OcaMethodID?,
    setValueTransformer: SetValueTransformer?
  ) {
    self.propertyID = propertyID
    self.getMethodID = getMethodID
    self.setMethodID = setMethodID
    subject = AsyncCurrentValueSubject(PropertyValue.initial)
    self.setValueTransformer = setValueTransformer
    _send = { @Sendable [subject] in subject.send($1) }
  }

  public init(
    propertyID: OcaPropertyID,
    getMethodID: OcaMethodID? = nil,
    setMethodID: OcaMethodID? = nil
  ) {
    self.init(
      propertyID: propertyID,
      getMethodID: getMethodID,
      setMethodID: setMethodID,
      setValueTransformer: nil
    )
  }

  @_spi(SwiftOCAPrivate) @discardableResult
  public func _getValue(
    _ object: OcaRoot,
    flags: OcaPropertyResolutionFlags = .defaultFlags
  ) async throws -> Value {
    do {
      guard let getMethodID else {
        throw Ocp1Error.propertyIsSettableOnly
      }

      if flags.contains(.subscribeEvents) {
        let isSubscribed = await (try? object.isSubscribed) ?? false
        if !isSubscribed {
          Task.detached { try await object.subscribe() }
        }
      }

      if flags.contains(.returnCachedValue), hasValueOrError {
        if case let .success(value) = currentValue {
          return value
        } else if case let .failure(error) = currentValue,
                  flags
                  .contains(.throwCachedError) || (error as? Ocp1Error) ==
                  .status(.notImplemented)
        {
          // we always throw notImplemented errors as we presume the device isn't going to
          // change its implementation status
          throw error
        }
      }

      let returnValue: Value = try await object.sendCommandRrq(methodID: getMethodID)
      if flags.contains(.cacheValue) {
        _send(object, .success(returnValue))
      }

      return returnValue
    } catch is CancellationError {
      if flags.contains(.cacheErrors) {
        _send(object, .initial)
      }
      throw CancellationError()
    } catch {
      if flags.contains(.cacheErrors) {
        _send(object, .failure(error))
      }
      await object.connectionDelegate?.logger
        .trace(
          "get property handler for \(object) property \(propertyID) received error from device: \(error)"
        )
      throw error
    }
  }

  func setValueIfMutable(
    _ object: OcaRoot,
    _ value: Value
  ) async throws {
    guard !isImmutable else {
      throw Ocp1Error.propertyIsImmutable
    }

    let newValue: Encodable = if let setValueTransformer {
      try await setValueTransformer(object, value)
    } else {
      value
    }

    // setters need to support variable parameter counts
    if try await object.isSubscribed {
      // we'll get a notification (hoepfully) so, don't require a reply
      try await object.sendCommand(
        methodID: setMethodID!,
        parameters: newValue
      )
    } else {
      try await object.sendCommandRrq(
        methodID: setMethodID!,
        parameters: newValue
      )

      // if we're not expecting an event, then be sure to update it here
      _send(object, .success(value))
    }
  }

  public func subscribe(_ object: OcaRoot) async {
    _ = try? await _getValue(object)
  }

  public func refresh(_ object: OcaRoot) async {
    _send(object, .initial)
  }

  func onEvent(_ object: OcaRoot, event: OcaEvent, eventData data: Data) throws {
    precondition(event.eventID == OcaPropertyChangedEventID)

    let eventData = try Ocp1Decoder().decode(
      OcaPropertyChangedEventData<Value>.self,
      from: data
    )
    precondition(propertyIDs.contains(eventData.propertyID))

    switch eventData.changeType {
    case .itemAdded:
      fallthrough
    case .itemChanged:
      fallthrough
    case .itemDeleted:
      if !(
        Value.self is any Ocp1ListRepresentable.Type || Value
          .self is any Ocp1MapRepresentable.Type || Value
          .self is any Ocp1Array2DRepresentable.Type
      ) {
        throw Ocp1Error.status(.parameterError)
      }
      fallthrough
    case .currentChanged:
      _send(object, .success(eventData.propertyValue))
    default:
      throw Ocp1Error.unhandledEvent
    }
  }

  func onCompletion<T: Sendable>(
    _ object: OcaRoot,
    _ block: @Sendable @escaping (_ value: Value) async throws -> T
  ) async throws -> T {
    try await block(_getValue(object))
  }

  public var projectedValue: Self {
    self
  }

  private func isNil(_ value: Value) -> Bool {
    if let value = value as? ExpressibleByNilLiteral,
       let value = value as? Value?,
       case .none = value
    {
      true
    } else {
      false
    }
  }

  public func getJsonValue(
    _ object: OcaRoot,
    flags: OcaPropertyResolutionFlags = .defaultFlags
  ) async throws -> [String: Any] {
    let value = try await _getValue(object, flags: flags)
    let jsonValue: Any = if isNil(value) {
      NSNull()
    } else if JSONSerialization.isValidJSONObject(value) {
      value
    } else {
      try JSONEncoder().reencodeAsValidJSONObject(value)
    }

    return [propertyID.description: jsonValue]
  }

  @_spi(SwiftOCAPrivate)
  public func _setValue(_ object: OcaRoot, _ anyValue: Any) async throws {
    guard let value = anyValue as? Value else {
      throw Ocp1Error.status(.badFormat)
    }
    try await setValueIfMutable(object, value)
  }
}

extension OcaProperty.PropertyValue: Equatable where Value: Equatable & Codable {
  public static func == (lhs: OcaProperty.PropertyValue, rhs: OcaProperty.PropertyValue) -> Bool {
    if case .initial = lhs,
       case .initial = rhs
    {
      true
    } else if case let .success(lhsValue) = lhs,
              case let .success(rhsValue) = rhs,
              lhsValue == rhsValue
    {
      true
    } else {
      false
    }
  }
}

extension OcaProperty.PropertyValue: Hashable where Value: Hashable & Codable {
  public func hash(into hasher: inout Hasher) {
    switch self {
    case let .success(value):
      hasher.combine(value)
    default:
      break
    }
  }
}
