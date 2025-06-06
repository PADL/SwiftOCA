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

@preconcurrency
import AsyncExtensions
import SwiftOCA

@propertyWrapper
public struct OcaBoundedDeviceProperty<
  Value: Codable &
    Comparable & Sendable
>: OcaDevicePropertyRepresentable, Sendable {
  fileprivate var storage: Property

  public var propertyID: OcaPropertyID { storage.propertyID }
  public var getMethodID: OcaMethodID? { storage.getMethodID }
  public var setMethodID: OcaMethodID? { storage.setMethodID }

  public typealias Property = OcaDeviceProperty<OcaBoundedPropertyValue<Value>>

  public var wrappedValue: OcaBoundedPropertyValue<Value> {
    get { storage.subject.value }
    nonmutating set { fatalError() }
  }

  public var projectedValue: AnyAsyncSequence<Value> {
    async.map(\.value).eraseToAnyAsyncSequence()
  }

  var subject: AsyncCurrentValueSubject<OcaBoundedPropertyValue<Value>> {
    storage.subject
  }

  public init(
    wrappedValue: OcaBoundedPropertyValue<Value>,
    propertyID: OcaPropertyID,
    getMethodID: OcaMethodID? = nil,
    setMethodID: OcaMethodID? = nil
  ) {
    storage = OcaDeviceProperty(
      wrappedValue: wrappedValue,
      propertyID: propertyID,
      getMethodID: getMethodID,
      setMethodID: setMethodID
    )
  }

  func getOcp1Response() async throws -> Ocp1Response {
    try await storage.getOcp1Response()
  }

  func getJsonValue() throws -> Any {
    let valueDict: [String: Value] =
      ["v": storage.subject.value.value,
       "l": storage.subject.value.range.lowerBound,
       "u": storage.subject.value.range.upperBound]

    return valueDict
  }

  private func setAndNotifySubscribers(
    object: OcaRoot,
    _ newValue: OcaBoundedPropertyValue<Value>
  ) async {
    storage.subject.send(newValue)
    try? await notifySubscribers(object: object, newValue.value)
  }

  func set(object: OcaRoot, jsonValue: Any, device: OcaDevice) async throws {
    guard let valueDict = jsonValue as? [String: Value] else {
      throw Ocp1Error.status(.badFormat)
    }

    let value = valueDict["v"]
    let lowerBound = valueDict["l"]
    let upperBound = valueDict["u"]
    guard let value,
          let lowerBound,
          let upperBound,
          lowerBound <= upperBound,
          value >= lowerBound,
          value <= upperBound
    else {
      throw Ocp1Error.status(.badFormat)
    }

    await setAndNotifySubscribers(
      object: object,
      OcaBoundedPropertyValue<Value>(value: value, in: lowerBound...upperBound)
    )
  }

  private func _validate(value: Value) throws {
    // check it is in range
    if value < storage.wrappedValue.minValue ||
      value > storage.wrappedValue.maxValue
    {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
  }

  func set(object: OcaRoot, command: Ocp1Command) async throws {
    let value: Value = try object.decodeCommand(command)
    try _validate(value: value)
    await setAndNotifySubscribers(
      object: object,
      OcaBoundedPropertyValue<Value>(value: value, in: storage.wrappedValue.range)
    )
  }

  func set(
    object: OcaRoot,
    eventData: OcaPropertyChangedEventData<OcaBoundedPropertyValue<Value>>
  ) async throws {
    switch eventData.changeType {
    case .currentChanged:
      try _validate(value: eventData.propertyValue.value)
      await setAndNotifySubscribers(object: object, eventData.propertyValue)
    case .minChanged:
      fallthrough // TODO: implement
    case .maxChanged:
      fallthrough // TODO: implement
    default:
      throw Ocp1Error.unhandledEvent
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
    wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, OcaBoundedPropertyValue<Value>>,
    storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
  ) -> OcaBoundedPropertyValue<Value> {
    get {
      object[keyPath: storageKeyPath].storage.get()
    }
    set {
      let property = object[keyPath: storageKeyPath]

      Task {
        await property.setAndNotifySubscribers(object: object, newValue)
      }
    }
  }
}
