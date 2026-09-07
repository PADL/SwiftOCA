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
#if canImport(FoundationEssentials) && !NonEmbeddedBuild
import FoundationEssentials
#else
import Foundation
#endif
@_spi(SwiftOCAPrivate)
import SwiftOCA

@propertyWrapper
public struct OcaVectorDeviceProperty<
  Value: Codable &
    Comparable & FixedWidthInteger & Sendable
>: OcaDevicePropertyRepresentable, Sendable {
  fileprivate var storage: Property

  // FIXME: support vector properties with multiple property IDs

  public var propertyID: OcaPropertyID { storage.propertyID }
  public var xPropertyID: OcaPropertyID { propertyID }
  public let yPropertyID: OcaPropertyID
  public var getMethodID: SwiftOCA.OcaMethodID? { storage.getMethodID }
  public var setMethodID: SwiftOCA.OcaMethodID? { storage.setMethodID }

  public typealias Property = OcaDeviceProperty<OcaVector2D<Value>>

  public var wrappedValue: OcaVector2D<Value> {
    get { storage.subject.value }
    nonmutating set { fatalError() }
  }

  public var projectedValue: AnyAsyncSequence<OcaVector2D<Value>> {
    async
  }

  var subject: AsyncCurrentValueSubject<OcaVector2D<Value>> {
    storage.subject
  }

  public init(
    wrappedValue: OcaVector2D<Value>,
    xPropertyID: OcaPropertyID,
    yPropertyID: OcaPropertyID,
    getMethodID: OcaMethodID? = nil,
    setMethodID: OcaMethodID? = nil,
    ocp2Name: String? = nil
  ) {
    storage = OcaDeviceProperty(
      wrappedValue: wrappedValue,
      propertyID: xPropertyID,
      getMethodID: getMethodID,
      setMethodID: setMethodID,
      ocp2Name: ocp2Name
    )

    self.yPropertyID = yPropertyID
  }

  public var ocp2Name: String? { storage.ocp2Name }

  /// A vector's getter returns one record with two fields, so it supplies no explicit
  /// names: the encoder derives `X` and `Y` from the record. A single name would be
  /// assigned to the first field and the second derived, which matches neither the
  /// model nor what this library's own controller asks for.
  func responseNames(propertyName: String) -> [String] {
    []
  }

  func getResponse(for controller: any OcaController, names: [String]?) async throws
    -> Ocp1Response
  {
    try await storage.getResponse(for: controller, names: names)
  }

  #if NonEmbeddedBuild
  func getJsonValue() throws -> any Sendable {
    let valueDict: [String: Value] =
      ["x": storage.subject.value.x,
       "y": storage.subject.value.y]

    return valueDict
  }
  #endif

  private func setAndNotifySubscribers(object: OcaRoot, _ newValue: OcaVector2D<Value>) async {
    storage.subject.send(newValue)
    try? await notifySubscribers(object: object, newValue)
  }

  #if NonEmbeddedBuild
  func set(object: OcaRoot, jsonValue: Any, device: OcaDevice) async throws {
    let valueDict: [String: Value]
    if let dict = jsonValue as? [String: Value] {
      valueDict = dict
    } else if JSONSerialization.isValidJSONObject(jsonValue) {
      let data = try JSONSerialization.data(withJSONObject: jsonValue)
      valueDict = try JSONDecoder().decode([String: Value].self, from: data)
    } else {
      throw Ocp1Error.status(.badFormat)
    }

    let x = valueDict["x"]
    let y = valueDict["y"]
    guard let x, let y else {
      throw Ocp1Error.status(.badFormat)
    }

    await setAndNotifySubscribers(object: object, OcaVector2D(x: x, y: y))
  }
  #endif

  func set(object: OcaRoot, command: Ocp1Command) async throws {
    let newValue: OcaVector2D<Value> = try object.decodeCommand(command)
    await setAndNotifySubscribers(object: object, newValue)
  }

  func set(
    object: OcaRoot,
    eventData: OcaPropertyChangedEventData<OcaVector2D<Value>>
  ) async throws {
    switch eventData.changeType {
    case .currentChanged:
      await setAndNotifySubscribers(object: object, eventData.propertyValue)
    case .minChanged:
      fallthrough // TODO: implement
    case .maxChanged:
      fallthrough // TODO: implement
    default:
      throw Ocp1Error.unhandledEvent
    }
  }

  /// Handle type-erased event data by decoding the inner component value and
  /// updating the corresponding axis. Notifications contain individual x/y
  /// components, not the full `OcaVector2D`.
  func set(
    object: OcaRoot,
    eventData typeErasedEventData: OcaAnyPropertyChangedEventData
  ) async throws {
    let componentEventData = try OcaPropertyChangedEventData<Value>(
      eventData: typeErasedEventData
    )
    var current = storage.subject.value
    if typeErasedEventData.propertyID == xPropertyID {
      current.x = componentEventData.propertyValue
    } else if typeErasedEventData.propertyID == yPropertyID {
      current.y = componentEventData.propertyValue
    } else {
      throw Ocp1Error.unhandledEvent
    }
    try await set(
      object: object,
      eventData: OcaPropertyChangedEventData<OcaVector2D<Value>>(
        propertyID: typeErasedEventData.propertyID,
        propertyValue: current,
        changeType: componentEventData.changeType
      )
    )
  }

  private func notifySubscribers(object: OcaRoot, _ newValue: OcaVector2D<Value>) async throws {
    let event = OcaEvent(emitterONo: object.objectNumber, eventID: OcaPropertyChangedEventID)
    let xParameters = OcaPropertyChangedEventData<Value>(
      propertyID: xPropertyID,
      propertyValue: newValue.x,
      changeType: .currentChanged
    )

    try await object.deviceDelegate?.notifySubscribers(
      event,
      parameters: xParameters
    )

    let yParameters = OcaPropertyChangedEventData<Value>(
      propertyID: yPropertyID,
      propertyValue: newValue.y,
      changeType: .currentChanged
    )

    try await object.deviceDelegate?.notifySubscribers(
      event,
      parameters: yParameters
    )
  }

  public static subscript<T: OcaRoot>(
    _enclosingInstance object: T,
    wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, OcaVector2D<Value>>,
    storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
  ) -> OcaVector2D<Value> {
    get {
      object[keyPath: storageKeyPath].storage.get()
    }
    // NOTE: as for OcaDeviceProperty, the value is stored at once so that a read
    // straight after the set sees it; only the notification needs the Task.
    set {
      let property = object[keyPath: storageKeyPath]
      property.storage.subject.send(newValue)

      Task {
        try? await property.notifySubscribers(object: object, newValue)
      }
    }
  }
}
