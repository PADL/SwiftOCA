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

  var subject: AsyncCurrentValueSubject<Value> { get }

  func getOcp1Response() async throws -> Ocp1Response
  func getJsonValue() throws -> Any

  /// setters take an object so that subscribers can be notified

  func set(object: OcaRoot, command: Ocp1Command) async throws
  func set(object: OcaRoot, jsonValue: Any, device: OcaDevice) async throws
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
  let subject: AsyncCurrentValueSubject<Value>

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

  func get() -> Value {
    subject.value
  }

  private func setAndNotifySubscribers(object: OcaRoot, _ newValue: Value) async {
    subject.send(newValue)
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
    let jsonValue: Any = if isNil(subject.value) {
      NSNull()
    } else if JSONSerialization.isValidJSONObject(subject.value) {
      subject.value
    } else {
      try JSONEncoder().reencodeAsValidJSONObject(subject.value)
    }

    return jsonValue
  }

  func set(object: OcaRoot, command: Ocp1Command) async throws {
    let newValue: Value = try OcaRoot.decodeCommand(command)
    await setAndNotifySubscribers(object: object, newValue)
  }

  func set(object: OcaRoot, jsonValue: Any, device: OcaDevice) async throws {
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
      await setAndNotifySubscribers(object: object, objects as! Value)
    } else {
      let isValidJSONObject = JSONSerialization.isValidJSONObject(subject.value)
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
