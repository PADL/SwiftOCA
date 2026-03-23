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
  func getJsonValue() throws -> any Sendable

  /// setters take an object so that subscribers can be notified

  func set(object: OcaRoot, command: Ocp1Command) async throws
  func set(object: OcaRoot, jsonValue: Any, device: OcaDevice) async throws
  func set(object: OcaRoot, eventData: OcaPropertyChangedEventData<Value>) async throws
}

extension OcaDevicePropertyRepresentable {
  func finish() {
    subject.send(.finished)
  }

  var async: AnyAsyncSequence<Value> {
    subject.eraseToAnyAsyncSequence()
  }

  func set(
    object: OcaRoot,
    eventData typeErasedEventData: OcaAnyPropertyChangedEventData
  ) async throws {
    try await set(
      object: object,
      eventData: OcaPropertyChangedEventData<Value>(eventData: typeErasedEventData)
    )
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

  func getJsonValue() throws -> any Sendable {
    let jsonValue: any Sendable = if isNil(subject.value) {
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

  func set(object: OcaRoot, eventData: OcaPropertyChangedEventData<Value>) async throws {
    switch eventData.changeType {
    case .currentChanged:
      await setAndNotifySubscribers(object: object, eventData.propertyValue)
    default:
      throw Ocp1Error.unhandledEvent
    }
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
        if let object = try? await device.deserialize(jsonObject: value, flags: .ignoreAllErrors) {
          objects.append(object)
        }
      }
      guard let objects = objects as? Value else {
        throw Ocp1Error.status(.badFormat)
      }
      await setAndNotifySubscribers(object: object, objects)
    } else if subject.value is [OcaRoot], let objectNumbers = jsonValue as? [OcaONo] {
      // resolve an array of object numbers to objects (only when property holds OcaRoot references)
      var objects = [OcaRoot]()
      for oNo in objectNumbers {
        if let resolved = await device.objects[oNo] {
          objects.append(resolved)
        }
      }
      guard let objects = objects as? Value else {
        throw Ocp1Error.status(.badFormat)
      }
      await setAndNotifySubscribers(object: object, objects)
    } else if subject.value is OcaRoot, let objectNumber = jsonValue as? OcaONo {
      // resolve a single object number to an object (only when property holds an OcaRoot reference)
      guard let resolved = await device.objects[objectNumber] as? Value else {
        throw Ocp1Error.status(.badFormat)
      }
      await setAndNotifySubscribers(object: object, resolved)
    } else {
      if JSONSerialization.isValidJSONObject(subject.value) {
        // Value is a JSON-native type (e.g. dictionary, array) — direct cast
        guard let newValue = jsonValue as? Value else {
          throw Ocp1Error.status(.badFormat)
        }
        await setAndNotifySubscribers(object: object, newValue)
      } else if let codableValue = jsonValue as? Codable {
        // Value is a non-JSON Codable type and input conforms to Codable —
        // round-trip through JSONEncoder to decode as Value
        try await setAndNotifySubscribers(
          object: object,
          JSONEncoder().reencodeAsValidJSONObject(codableValue)
        )
      } else if JSONSerialization.isValidJSONObject(jsonValue) {
        // Value is a non-JSON Codable type and input is a Foundation container
        // (e.g. NSDictionary/NSArray from a JSONSerialization round-trip that
        // doesn't conform to Codable) — serialize to JSON data then decode
        let data = try JSONSerialization.data(withJSONObject: jsonValue)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        await setAndNotifySubscribers(object: object, decoded)
      } else if Value.self is any RawRepresentable.Type,
                let jsonValue = jsonValue as? Int
      {
        // Value is a RawRepresentable and input is an integer — needed because
        // NSNumber (from JSONSerialization) doesn't conform to Codable but does
        // bridge to Int
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
      property.subject.send(newValue)

      Task {
        try? await property.notifySubscribers(object: object, newValue)
      }
    }
  }
}

extension OcaDevicePropertyRepresentable {
  func _forward(to remoteObject: SwiftOCA.OcaRoot) async throws {
    let encodedValue: Data = try Ocp1Encoder().encode(wrappedValue)
    let eventData = OcaAnyPropertyChangedEventData(
      propertyID: propertyID,
      propertyValue: encodedValue,
      changeType: .currentChanged
    )
    let event = OcaEvent(
      emitterONo: remoteObject.objectNumber,
      eventID: OcaPropertyChangedEventID
    )
    try await remoteObject.forward(event: event, eventData: eventData)
  }
}
