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
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Marks a bounded property value, whose OCP.2 response is named after the property
/// (`Gain`, `minGain`, `maxGain`) rather than after its fields.
public protocol OcaBoundedPropertyValueRepresentable {}

public struct OcaBoundedPropertyValue<
  Value: Codable & Comparable &
    Sendable
>: Ocp1ParametersReflectable, Codable, Equatable, Sendable, OcaBoundedPropertyValueRepresentable {
  public var value: Value
  public var minValue: Value
  public var maxValue: Value

  public var range: ClosedRange<Value> {
    get {
      minValue...maxValue
    }
    set {
      minValue = newValue.lowerBound
      maxValue = newValue.upperBound
    }
  }

  public init(value: Value, in range: ClosedRange<Value>) {
    self.value = value
    minValue = range.lowerBound
    maxValue = range.upperBound
  }

  public init(value: Value, minValue: Value, maxValue: Value) {
    self.value = value
    self.minValue = minValue
    self.maxValue = maxValue
  }
}

public extension OcaBoundedPropertyValue where Value: BinaryFloatingPoint {
  var absoluteRange: Value {
    range.upperBound - range.lowerBound
  }

  /// returns value between 0.0 and 1.0
  var relativeValue: OcaFloat32 {
    OcaFloat32((value + range.upperBound) / absoluteRange)
  }
}

@propertyWrapper
public struct OcaBoundedProperty<
  Value: Codable & Comparable &
    Sendable
>: OcaPropertyChangeEventNotifiable,
  Codable, Sendable
{
  public var valueType: Any.Type { Value.self }

  @_spi(SwiftOCAPrivate)
  public var subject: AsyncCurrentValueSubject<PropertyValue> { _storage.subject }

  public typealias Property = OcaProperty<OcaBoundedPropertyValue<Value>>
  public typealias PropertyValue = Property.PropertyValue

  public var propertyIDs: [OcaPropertyID] {
    [_storage.propertyID]
  }

  public var getMethodID: OcaMethodID? { _storage.getMethodID }
  public var setMethodID: OcaMethodID? { _storage.setMethodID }

  fileprivate var _storage: Property

  public init(from decoder: Decoder) throws {
    fatalError()
  }

  /// Placeholder only
  public func encode(to encoder: Encoder) throws {
    fatalError()
  }

  @available(*, unavailable, message: """
  @OcaBoundedProperty is only available on properties of classes
  """)
  public var wrappedValue: PropertyValue {
    get { fatalError() }
    nonmutating set { fatalError() }
  }

  public func refresh(_ object: OcaRoot) async {
    await _storage.refresh(object)
  }

  public var currentValue: PropertyValue {
    _storage.currentValue
  }

  public func subscribe(_ object: OcaRoot) async {
    await _storage.subscribe(object)
  }

  public var description: String {
    _storage.description
  }

  public init(
    propertyID: OcaPropertyID,
    getMethodID: OcaMethodID,
    setMethodID: OcaMethodID? = nil,
    ocp2GetName: String? = nil,
    ocp2SetName: String? = nil
  ) {
    _storage = OcaProperty(
      propertyID: propertyID,
      getMethodID: getMethodID,
      setMethodID: setMethodID,
      ocp2GetName: ocp2GetName,
      ocp2SetName: ocp2SetName,
      setValueTransformer: { $1.value }
    )
  }

  public func _ocp2GetName(_ object: OcaRoot) -> String? {
    _storage._ocp2GetName(object)
  }

  public func _ocp2SetName(_ object: OcaRoot) -> String? {
    _storage._ocp2SetName(object)
  }

  public func _ocp2ResponseNames(_ object: OcaRoot) -> [String]? {
    _storage._ocp2ResponseNames(object)
  }

  public static subscript<T: OcaRoot>(
    _enclosingInstance object: T,
    wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, PropertyValue>,
    storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
  ) -> PropertyValue {
    get {
      object[keyPath: storageKeyPath]._storage
        ._get(
          _enclosingInstance: object
        )
    }
    set {
      object[keyPath: storageKeyPath]._storage._set(
        _enclosingInstance: object,
        newValue
      )
    }
  }

  func onEvent(
    _ object: OcaRoot,
    event: OcaEvent,
    eventData encodedEventData: OcaEncodedEventData
  ) throws {
    precondition(event.eventID == OcaPropertyChangedEventID)

    let eventData = try OcaEventDataCoding.decode(
      OcaPropertyChangedEventData<Value>.self,
      from: encodedEventData
    )
    precondition(propertyIDs.contains(eventData.propertyID))

    guard case var .success(value) = _storage.currentValue else {
      throw Ocp1Error.noInitialValue
    }

    switch eventData.changeType {
    case .currentChanged:
      value.value = eventData.propertyValue
    case .minChanged:
      value.minValue = eventData.propertyValue
    case .maxChanged:
      value.maxValue = eventData.propertyValue
    default:
      throw Ocp1Error.unhandledEvent
    }

    _storage._send(object, .success(value))
  }

  public var projectedValue: Self {
    self
  }

  @_spi(SwiftOCAPrivate) @discardableResult
  public func _getValue(
    _ object: OcaRoot,
    flags: OcaPropertyResolutionFlags = .defaultFlags
  ) async throws -> OcaBoundedPropertyValue<Value> {
    try await _storage._getValue(object, flags: flags)
  }

  #if NonEmbeddedBuild
  public func getJsonValue(
    _ object: OcaRoot,
    keyPath: AnyKeyPath,
    flags: OcaPropertyResolutionFlags = .defaultFlags
  ) async throws -> [String: any Sendable] {
    let value = try await _getValue(object, flags: flags)
    // the shape of the getter response (Gain, MinGain, MaxGain) under the property's
    // own name, as accessor parameter names repeat within a class
    let names = Ocp2Naming.boundedWireNames(object._jsonPropertyName(for: propertyIDs[0]))
    let encoder = Ocp2Encoder()
    return [
      names[0]: Ocp2JSON.sendable(try encoder.encodeValue(value.value)),
      names[1]: Ocp2JSON.sendable(try encoder.encodeValue(value.minValue)),
      names[2]: Ocp2JSON.sendable(try encoder.encodeValue(value.maxValue)),
    ]
  }
  #endif

  @_spi(SwiftOCAPrivate)
  public func _setValue(_ object: OcaRoot, _ anyValue: Any) async throws {
    // use flags to avoid subscribing
    var value = try await _getValue(object, flags: [.cacheValue, .returnCachedValue])
    if let boundedValue = anyValue as? OcaBoundedPropertyValue<Value> {
      value.value = boundedValue.value
    } else if let innerValue = anyValue as? Value {
      value.value = innerValue
    } else {
      throw Ocp1Error.status(.badFormat)
    }
    try await _storage.setValueIfMutable(object, value)
  }
}
