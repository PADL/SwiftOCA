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
import Foundation
@_spi(SwiftOCAPrivate)
import SwiftOCA

protocol OcaDevicePropertyRepresentable: Sendable {
  associatedtype Value: Codable & Sendable

  var propertyID: OcaPropertyID { get }
  var getMethodID: OcaMethodID? { get }
  var setMethodID: OcaMethodID? { get }
  var wrappedValue: Value { get }

  func getOcp1Response() async throws -> Ocp1Response
  func getJsonValue() throws -> Any

  /// setters take an object so that subscribers can be notified

  func set(object: OcaRoot, command: Ocp1Command) async throws
  func set(object: OcaRoot, jsonValue: Any, device: OcaDevice) async throws
}

fileprivate protocol ManagedCriticalStateNilRepresentable {
  func _setNil()
}

extension ManagedCriticalState: ManagedCriticalStateNilRepresentable
  where State: ExpressibleByNilLiteral
{
  func _setNil() {
    withCriticalRegion { $0 = nil }
  }
}

@propertyWrapper
public struct OcaDeviceProperty<Value: Codable & Sendable>: OcaDevicePropertyRepresentable,
  Sendable
{
  private var _value: ManagedCriticalState<Value>

  /// The OCA property ID
  public let propertyID: OcaPropertyID

  /// The OCA get method ID
  public let getMethodID: OcaMethodID?

  /// The OCA set method ID, if present
  public let setMethodID: OcaMethodID?

  /// Placeholder only
  public var wrappedValue: Value {
    get { _value.withCriticalRegion { $0 } }
    nonmutating set { fatalError() }
  }

  public init(
    wrappedValue: Value,
    propertyID: OcaPropertyID,
    getMethodID: OcaMethodID? = nil,
    setMethodID: OcaMethodID? = nil
  ) {
    _value = ManagedCriticalState(wrappedValue)
    self.propertyID = propertyID
    self.getMethodID = getMethodID
    self.setMethodID = setMethodID
  }

  public init(
    propertyID: OcaPropertyID,
    getMethodID: OcaMethodID? = nil,
    setMethodID: OcaMethodID? = nil
  ) where Value: ExpressibleByNilLiteral {
    _value = ManagedCriticalState(nil)
    self.propertyID = propertyID
    self.getMethodID = getMethodID
    self.setMethodID = setMethodID
  }

  func get() -> Value {
    wrappedValue
  }
  
  func setWithoutNotifyingSubscribers(_ value: Value) {
    _value.withCriticalRegion { $0 = value }
  }

  private func setAndNotifySubscribers(object: OcaRoot, _ newValue: Value) async {
    _value.withCriticalRegion { $0 = newValue }
    try? await notifySubscribers(object: object, newValue)
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

  func getOcp1Response() async throws -> Ocp1Response {
    let value: Value = get()
    if isNil(value) {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return try OcaRoot.encodeResponse(value)
  }

  func getJsonValue() throws -> Any {
    let value = wrappedValue

    let jsonValue: Any = if isNil(value) {
      NSNull()
    } else if JSONSerialization.isValidJSONObject(value) {
      value
    } else {
      try JSONEncoder().reencodeAsValidJSONObject(value)
    }

    return jsonValue
  }

  func set(object: OcaRoot, command: Ocp1Command) async throws {
    let newValue: Value = try OcaRoot.decodeCommand(command)
    await setAndNotifySubscribers(object: object, newValue)
  }

  func set(object: OcaRoot, jsonValue: Any, device: OcaDevice) async throws {
    if jsonValue is NSNull {
      if let value = _value as? any ManagedCriticalStateNilRepresentable {
        value._setNil()
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
      await setAndNotifySubscribers(object: object, objects as! Value)
    } else {
      let isValidJSONObject = JSONSerialization.isValidJSONObject(_value)
      if !isValidJSONObject,
         let jsonValue = jsonValue as? Codable
      {
        try await setAndNotifySubscribers(
          object: object,
          JSONEncoder().reencodeAsValidJSONObject(jsonValue)
        )
      } else if !isValidJSONObject,
                Value.self is any RawRepresentable.Type,
                let jsonValue = jsonValue as? Int
      {
        try await setAndNotifySubscribers(
          object: object,
          JSONEncoder().reencodeAsValidJSONObject(jsonValue)
        )
      } else {
        guard let newValue = jsonValue as? Value else {
          throw Ocp1Error.status(.badFormat)
        }
        await setAndNotifySubscribers(object: object, newValue)
      }
    }
  }

  private func notifySubscribers(object: OcaRoot, _ newValue: Value) async throws {
    let event = OcaEvent(emitterONo: object.objectNumber, eventID: OcaPropertyChangedEventID)
    let parameters = OcaPropertyChangedEventData<Value>(
      propertyID: propertyID,
      propertyValue: newValue,
      changeType: .currentChanged
    )

    try await object.deviceDelegate?.notifySubscribers(
      event,
      parameters: parameters
    )
  }

  public static subscript<T: OcaRoot>(
    _enclosingInstance object: T,
    wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
    storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
  ) -> Value {
    get {
      object[keyPath: storageKeyPath].get()
    }
    set {
      let property = object[keyPath: storageKeyPath]

      Task {
        await property.setAndNotifySubscribers(object: object, newValue)
      }
    }
  }
}
