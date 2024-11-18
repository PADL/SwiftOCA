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
@_spi(SwiftOCAPrivate)
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
    get { storage.wrappedValue }
    nonmutating set { fatalError() }
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
    let value = storage.wrappedValue
    let valueDict: [String: Value] =
      ["v": value.value,
       "l": value.range.lowerBound,
       "u": value.range.upperBound]

    return valueDict
  }

  private func setAndNotifySubscribers(
    object: OcaRoot,
    _ newValue: OcaBoundedPropertyValue<Value>
  ) async {
    storage.setWithoutNotifyingSubscribers(newValue)
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

  func set(object: OcaRoot, command: Ocp1Command) async throws {
    let value: Value = try object.decodeCommand(command)
    // check it is in range
    if value < storage.wrappedValue.minValue ||
      value > storage.wrappedValue.maxValue
    {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    await setAndNotifySubscribers(
      object: object,
      OcaBoundedPropertyValue<Value>(value: value, in: storage.wrappedValue.range)
    )
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
