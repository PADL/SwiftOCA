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

public struct OcaVector2D<T: Codable & Sendable & FixedWidthInteger>: OcaParametersReflectable,
  Codable, Sendable
{
  public var x, y: T

  public init(x: T, y: T) {
    self.x = x
    self.y = y
  }
}

/// A vector with each axis's bounds, in the order AES70-2 returns them from a
/// getter such as `OcaMatrix.GetSize`.
public struct OcaBoundedVector2D<T: Codable & Sendable & FixedWidthInteger>:
  OcaParametersReflectable, Codable, Sendable
{
  public var x, y: T
  public var minX, maxX: T
  public var minY, maxY: T

  public init(x: T, y: T, minX: T, maxX: T, minY: T, maxY: T) {
    self.x = x
    self.y = y
    self.minX = minX
    self.maxX = maxX
    self.minY = minY
    self.maxY = maxY
  }

  public var vector: OcaVector2D<T> {
    OcaVector2D(x: x, y: y)
  }
}

@propertyWrapper
public struct OcaVectorProperty<
  Value: Codable & Sendable &
    FixedWidthInteger
>: OcaPropertyChangeEventNotifiable, Codable, Sendable {
  public var valueType: Any.Type { Property.PropertyValue.self }

  @_spi(SwiftOCAPrivate)
  public var subject: AsyncCurrentValueSubject<PropertyValue> { _storage.subject }

  fileprivate var _storage: Property

  public typealias Property = OcaProperty<OcaVector2D<Value>>
  public typealias PropertyValue = Property.PropertyValue

  public var propertyIDs: [OcaPropertyID] {
    [xPropertyID, yPropertyID]
  }

  public let xPropertyID: OcaPropertyID
  public let yPropertyID: OcaPropertyID
  public let getMethodID: OcaMethodID?
  public let setMethodID: OcaMethodID?

  public init(from decoder: Decoder) throws {
    fatalError()
  }

  /// Placeholder only
  public func encode(to encoder: Encoder) throws {
    fatalError()
  }

  @available(*, unavailable, message: """
  @OcaVectorProperty is only available on properties of classes
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
    xPropertyID: OcaPropertyID,
    yPropertyID: OcaPropertyID,
    getMethodID: OcaMethodID,
    setMethodID: OcaMethodID? = nil,
    ocp2GetName: String? = nil
  ) {
    self.xPropertyID = xPropertyID
    self.yPropertyID = yPropertyID
    self.getMethodID = getMethodID
    self.setMethodID = setMethodID
    // The storage stands in for a pair of properties, so it has no property ID of
    // its own and must not borrow one: an ID that resolves (1.1 is OcaRoot's
    // `classID`) would name the OCP.2 parameters after that property. Leaving both
    // the ID unresolvable and `ocp2GetName` unset keeps `_ocp2GetName` nil, so the
    // encoder names the parameters after the vector record's own fields (`X`, `Y`),
    // which is what the model specifies. `ocp2GetName` still applies to the JSON export
    // through this wrapper's own `_ocp2GetName`.
    _storage = OcaProperty(
      propertyID: OcaPropertyID("0.0"),
      getMethodID: getMethodID,
      setMethodID: setMethodID
    )
  }

  public func _ocp2GetName(_ object: OcaRoot) -> String? {
    if let ocp2GetName = _storage.ocp2GetName { return ocp2GetName }
    guard let name = object.propertyName(for: xPropertyID) else { return nil }
    return Ocp2Naming.wireName(name)
  }

  public func _ocp2ResponseNames(_ object: OcaRoot) -> [String]? {
    _ocp2GetName(object).map { [$0] }
  }

  public static subscript<T: OcaRoot>(
    _enclosingInstance object: T,
    wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, PropertyValue>,
    storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
  ) -> PropertyValue {
    get {
      object[keyPath: storageKeyPath]._storage
        ._get(_enclosingInstance: object)
    }
    set {
      object[keyPath: storageKeyPath]._storage._set(_enclosingInstance: object, newValue)
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

    // TODO: support add/delete
    switch eventData.changeType {
    case .currentChanged:
      guard case let .success(subjectValue) = _storage.currentValue else {
        throw Ocp1Error.noInitialValue
      }

      let isX = eventData.propertyID == xPropertyID
      var xy = OcaVector2D<Value>(x: 0, y: 0)

      if isX {
        xy.x = eventData.propertyValue
        xy.y = subjectValue.y
      } else {
        xy.x = subjectValue.x
        xy.y = eventData.propertyValue
      }
      _storage._send(object, .success(xy))
    default:
      throw Ocp1Error.unhandledEvent
    }
  }

  public var projectedValue: Self {
    self
  }

  @_spi(SwiftOCAPrivate) @discardableResult
  public func _getValue(
    _ object: OcaRoot,
    flags: OcaPropertyResolutionFlags = .defaultFlags
  ) async throws -> OcaVector2D<Value> {
    try await _storage._getValue(object, flags: flags)
  }

  #if NonEmbeddedBuild
  public func getJsonValue(
    _ object: OcaRoot,
    keyPath: AnyKeyPath,
    flags: OcaPropertyResolutionFlags = .defaultFlags
  ) async throws -> [String: any Sendable] {
    let value = try await _getValue(object, flags: flags)
    let name = _ocp2GetName(object) ?? xPropertyID.description
    return [name: Ocp2JSON.sendable(try Ocp2Encoder().encodeValue(value))]
  }
  #endif

  @_spi(SwiftOCAPrivate)
  public func _setValue(_ object: OcaRoot, _ anyValue: Any) async throws {
    guard let value = anyValue as? OcaVector2D<Value> else {
      throw Ocp1Error.status(.badFormat)
    }
    try await _storage.setValueIfMutable(object, value)
  }
}

/// A property pair whose getter returns the pair with each axis's bounds and whose
/// setter takes the pair alone, as AES70-2 defines `OcaMatrix`'s size.
@propertyWrapper
public struct OcaBoundedVectorProperty<
  Value: Codable & Sendable &
    FixedWidthInteger
>: OcaPropertyChangeEventNotifiable, Codable, Sendable {
  public var valueType: Any.Type { Property.PropertyValue.self }

  @_spi(SwiftOCAPrivate)
  public var subject: AsyncCurrentValueSubject<PropertyValue> { _storage.subject }

  fileprivate var _storage: Property

  public typealias Property = OcaProperty<OcaBoundedVector2D<Value>>
  public typealias PropertyValue = Property.PropertyValue

  public var propertyIDs: [OcaPropertyID] {
    [xPropertyID, yPropertyID]
  }

  public let xPropertyID: OcaPropertyID
  public let yPropertyID: OcaPropertyID
  public let getMethodID: OcaMethodID?
  public let setMethodID: OcaMethodID?

  public init(from decoder: Decoder) throws {
    fatalError()
  }

  /// Placeholder only
  public func encode(to encoder: Encoder) throws {
    fatalError()
  }

  @available(*, unavailable, message: """
  @OcaBoundedVectorProperty is only available on properties of classes
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
    xPropertyID: OcaPropertyID,
    yPropertyID: OcaPropertyID,
    getMethodID: OcaMethodID,
    setMethodID: OcaMethodID? = nil
  ) {
    self.xPropertyID = xPropertyID
    self.yPropertyID = yPropertyID
    self.getMethodID = getMethodID
    self.setMethodID = setMethodID
    // the bounds are read-only, so the setter sends the pair alone
    _storage = OcaProperty(
      propertyID: OcaPropertyID("1.1"),
      getMethodID: getMethodID,
      setMethodID: setMethodID,
      setValueTransformer: { $1.vector }
    )
  }

  /// AES70-2 names the size parameters, and the device answers with those names; the
  /// record's own fields would derive `X` and `MinX`, which no conforming peer sends.
  public func _ocp2ResponseNames(_ object: OcaRoot) -> [String]? {
    ["xSize", "ySize", "minXSize", "maxXSize", "minYSize", "maxYSize"]
  }

  public func _ocp2GetName(_ object: OcaRoot) -> String? {
    _ocp2ResponseNames(object)?.first
  }

  public static subscript<T: OcaRoot>(
    _enclosingInstance object: T,
    wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, PropertyValue>,
    storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
  ) -> PropertyValue {
    get {
      object[keyPath: storageKeyPath]._storage
        ._get(_enclosingInstance: object)
    }
    set {
      object[keyPath: storageKeyPath]._storage._set(_enclosingInstance: object, newValue)
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

    // TODO: support add/delete
    switch eventData.changeType {
    case .currentChanged:
      guard case let .success(currentValue) = _storage.currentValue else {
        throw Ocp1Error.noInitialValue
      }
      var value = currentValue
      if eventData.propertyID == xPropertyID {
        value.x = eventData.propertyValue
      } else {
        value.y = eventData.propertyValue
      }
      _storage._send(object, .success(value))
    default:
      throw Ocp1Error.unhandledEvent
    }
  }

  public var projectedValue: Self {
    self
  }

  @_spi(SwiftOCAPrivate) @discardableResult
  public func _getValue(
    _ object: OcaRoot,
    flags: OcaPropertyResolutionFlags = .defaultFlags
  ) async throws -> OcaBoundedVector2D<Value> {
    try await _storage._getValue(object, flags: flags)
  }

  #if NonEmbeddedBuild
  public func getJsonValue(
    _ object: OcaRoot,
    keyPath: AnyKeyPath,
    flags: OcaPropertyResolutionFlags = .defaultFlags
  ) async throws -> [String: any Sendable] {
    let value = try await _getValue(object, flags: flags)
    let name = object._jsonPropertyName(for: xPropertyID)
    return [name: Ocp2JSON.sendable(try Ocp2Encoder().encodeValue(value))]
  }
  #endif

  @_spi(SwiftOCAPrivate)
  public func _setValue(_ object: OcaRoot, _ anyValue: Any) async throws {
    guard let value = anyValue as? OcaBoundedVector2D<Value> else {
      throw Ocp1Error.status(.badFormat)
    }
    try await _storage.setValueIfMutable(object, value)
  }
}
