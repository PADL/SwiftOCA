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
#if canImport(Darwin)
import Observation
#endif

open class OcaRoot: CustomStringConvertible, @unchecked
Sendable,
  _OcaObjectKeyPathRepresentable, Observable
{
  typealias Root = OcaRoot

  public internal(set) weak var connectionDelegate: Ocp1Connection?

  fileprivate var subscriptionCancellable: Ocp1Connection.SubscriptionCancellable?
  #if canImport(Darwin)
  fileprivate let _$observationRegistrar = Observation.ObservationRegistrar()
  #endif

  // 1.1
  open class var classID: OcaClassID { OcaClassID("1") }

  private var _classID: StaticProperty<OcaClassID> {
    StaticProperty<OcaClassID>(propertyIDs: [OcaPropertyID("1.1")], value: Self.classID)
  }

  // 1.2
  open class var classVersion: OcaClassVersionNumber { 3 }

  private var _classVersion: StaticProperty<OcaClassVersionNumber> {
    StaticProperty<OcaClassVersionNumber>(
      propertyIDs: [OcaPropertyID("1.2")],
      value: Self.classVersion
    )
  }

  public class var classIdentification: OcaClassIdentification {
    OcaClassIdentification(classID: classID, classVersion: classVersion)
  }

  public var objectIdentification: OcaObjectIdentification {
    OcaObjectIdentification(
      oNo: objectNumber,
      classIdentification: Self.classIdentification
    )
  }

  // 1.3
  public let objectNumber: OcaONo
  private var _objectNumber: StaticProperty<OcaONo> {
    StaticProperty<OcaONo>(propertyIDs: [OcaPropertyID("1.3")], value: objectNumber)
  }

  @OcaProperty(
    propertyID: OcaPropertyID("1.4"),
    getMethodID: OcaMethodID("1.2")
  )
  public var lockable: OcaProperty<OcaBoolean>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("1.5"),
    getMethodID: OcaMethodID("1.5")
  )
  public var role: OcaProperty<OcaString>.PropertyValue

  @_spi(SwiftOCAPrivate)
  public func _set(role: OcaString) {
    $role.subject.send(.success(role))
  }

  @OcaProperty(
    propertyID: OcaPropertyID("1.6"),
    getMethodID: OcaMethodID("1.7")
  )
  public var lockState: OcaProperty<OcaLockState>.PropertyValue

  public required init(objectNumber: OcaONo) {
    self.objectNumber = objectNumber
  }

  deinit {
    for (_, keyPath) in allPropertyKeyPathsUncached {
      let value = self[keyPath: keyPath] as! (any OcaPropertySubjectRepresentable)
      value.finish()
    }
  }

  public func getClassIdentification() async throws -> OcaClassIdentification {
    try await sendCommandRrq(methodID: OcaMethodID("1.1"))
  }

  @available(*, deprecated, renamed: "setLockNoReadWrite")
  public func lockTotal() async throws {
    try await setLockNoReadWrite()
  }

  public func setLockNoReadWrite() async throws {
    try await sendCommandRrq(methodID: OcaMethodID("1.3"))
  }

  public func unlock() async throws {
    try await sendCommandRrq(methodID: OcaMethodID("1.4"))
  }

  @available(*, deprecated, renamed: "setLockNoWrite")
  public func lockReadOnly() async throws {
    try await setLockNoWrite()
  }

  public func setLockNoWrite() async throws {
    try await sendCommandRrq(methodID: OcaMethodID("1.6"))
  }

  public var isContainer: Bool {
    false
  }

  public var description: String {
    if case let .success(value) = role {
      "\(type(of: self))(objectNumber: \(objectNumber.oNoString), role: \(value))"
    } else {
      "\(type(of: self))(objectNumber: \(objectNumber.oNoString))"
    }
  }

  open func getJsonValue(
    flags: OcaPropertyResolutionFlags = .defaultFlags
  ) async -> [String: Any] {
    precondition(objectNumber != OcaInvalidONo)

    guard self is OcaWorker else {
      return [:]
    }

    let dict = await withTaskGroup(
      of: [String: Sendable].self,
      returning: [String: Sendable].self
    ) { taskGroup in
      for (_, propertyKeyPath) in await allPropertyKeyPaths {
        taskGroup.addTask {
          let property =
            self[keyPath: propertyKeyPath] as! (any OcaPropertySubjectRepresentable)
          var dict = [String: Sendable]()

          if let jsonValue = try? await property.getJsonValue(self, flags: flags),
             let jsonValue = jsonValue as? [String: Sendable]
          {
            dict.merge(jsonValue) { current, _ in current }
          }
          return dict
        }
      }
      return await taskGroup.collect()
        .reduce(into: [String: Sendable]()) { $0.merge($1) { $1 } }
    }

    return dict
  }

  public var jsonObject: [String: Any] {
    get async {
      await getJsonValue(flags: .defaultFlags)
    }
  }

  public func propertyKeyPath(for propertyID: OcaPropertyID) async -> AnyKeyPath? {
    await OcaPropertyKeyPathCache.shared.lookupProperty(byID: propertyID, for: self)
  }

  public func propertyKeyPath(for name: String) async -> AnyKeyPath? {
    await OcaPropertyKeyPathCache.shared.lookupProperty(byName: name, for: self)
  }
}

protocol _OcaObjectKeyPathRepresentable: OcaRoot {}

extension _OcaObjectKeyPathRepresentable {
  fileprivate var _metaTypeObjectIdentifier: ObjectIdentifier {
    ObjectIdentifier(type(of: self))
  }

  @OcaConnection
  var allKeyPaths: [String: AnyKeyPath] {
    OcaPropertyKeyPathCache.shared.keyPaths(for: self)
  }

  var allKeyPathsUncached: [String: AnyKeyPath] {
    _allKeyPaths(value: self).reduce(into: [:]) {
      if $1.key.hasPrefix("_") {
        $0[String($1.key.dropFirst())] = $1.value
      }
    }
  }

  #if canImport(Darwin)
  nonisolated func access(
    keyPath: KeyPath<Self, some Any>
  ) {
    _$observationRegistrar.access(self, keyPath: keyPath)
  }

  nonisolated func withMutation<T>(
    keyPath: KeyPath<Self, some Any>,
    _ mutation: () throws -> T
  ) rethrows -> T {
    try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
  }
  #endif
}

public extension OcaRoot {
  private var staticPropertyKeyPaths: [String: AnyKeyPath] {
    ["classID": \OcaRoot._classID,
     "classVersion": \OcaRoot._classVersion,
     "objectNumber": \OcaRoot._objectNumber]
  }

  var allPropertyKeyPathsUncached: [String: AnyKeyPath] {
    staticPropertyKeyPaths.merging(
      allKeyPathsUncached.filter { self[keyPath: $0.value] is any OcaPropertySubjectRepresentable },
      uniquingKeysWith: { old, _ in old }
    )
  }

  @OcaConnection
  var allPropertyKeyPaths: [String: AnyKeyPath] {
    get async {
      staticPropertyKeyPaths.merging(
        allKeyPaths.filter { self[keyPath: $0.value] is any OcaPropertySubjectRepresentable },
        uniquingKeysWith: { old, _ in old }
      )
    }
  }

  @OcaConnection
  private func onPropertyEvent(event: OcaEvent, eventData data: Data) {
    let decoder = Ocp1Decoder()
    guard let propertyID = try? decoder.decode(
      OcaPropertyID.self,
      from: data
    ) else { return }

    for (_, keyPath) in allKeyPaths {
      if let value = self[keyPath: keyPath] as? (any OcaPropertyChangeEventNotifiable),
         value.propertyIDs.contains(propertyID)
      {
        try? value.onEvent(self, event: event, eventData: data)
        break
      }
    }
  }

  @OcaConnection
  func subscribe() async throws {
    guard subscriptionCancellable == nil else { return } // already subscribed
    guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
    let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
    do {
      subscriptionCancellable = try await connectionDelegate.addSubscription(
        label: "com.padl.SwiftOCA.OcaRoot",
        event: event,
        callback: onPropertyEvent
      )
    } catch Ocp1Error.alreadySubscribedToEvent {
    } catch Ocp1Error.status(.invalidRequest) {
      // FIXME: in our device implementation not all properties can be subcribed to
    }
  }

  @OcaConnection
  func unsubscribe() async throws {
    guard let subscriptionCancellable else { throw Ocp1Error.notSubscribedToEvent }
    guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
    try await connectionDelegate.removeSubscription(subscriptionCancellable)
  }

  @OcaConnection
  func refreshAll() async {
    for (_, keyPath) in await allPropertyKeyPaths {
      let property = (self[keyPath: keyPath] as! any OcaPropertyRepresentable)
      await property.refresh(self)
    }
  }

  @OcaConnection
  package func refreshAllSubscribed() async {
    for (_, keyPath) in await allPropertyKeyPaths {
      let property = (self[keyPath: keyPath] as! any OcaPropertySubjectRepresentable)
      // make an exception for role because it is immutable, otherwise refreshing device
      // tree at initial connection time will then force many needless subscriptions at
      // reconnection time
      guard property.hasValueOrError, !property.isImmutable else { continue }
      await property.refreshAndSubscribe(self)
    }
  }

  internal var isSubscribed: Bool {
    get async throws {
      guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
      let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
      return await connectionDelegate.isSubscribed(event: event)
    }
  }

  internal struct StaticProperty<T: Codable & Sendable>: OcaPropertySubjectRepresentable {
    var valueType: Any.Type { T.self }

    typealias Value = T

    var setMethodID: OcaMethodID? { nil }
    var propertyIDs: [OcaPropertyID]
    var value: T

    func refresh(_ object: SwiftOCA.OcaRoot) async {}
    func subscribe(_ object: OcaRoot) async {}

    var description: String {
      String(describing: value)
    }

    var currentValue: OcaProperty<Value>.PropertyValue {
      OcaProperty<Value>.PropertyValue.success(value)
    }

    var subject: AsyncCurrentValueSubject<PropertyValue> {
      AsyncCurrentValueSubject(currentValue)
    }

    @_spi(SwiftOCAPrivate) @discardableResult
    public func _getValue(
      _ object: OcaRoot,
      flags: OcaPropertyResolutionFlags = .defaultFlags
    ) async throws -> Value {
      value
    }

    func getJsonValue(
      _ object: OcaRoot,
      flags: OcaPropertyResolutionFlags = .defaultFlags
    ) async throws -> [String: Any] {
      [propertyIDs[0].description: String(describing: value)]
    }

    @_spi(SwiftOCAPrivate)
    public func _setValue(_ object: OcaRoot, _ anyValue: Any) async throws {
      throw Ocp1Error.propertyIsImmutable
    }
  }
}

@OcaConnection
private final class OcaPropertyKeyPathCache {
  fileprivate static let shared = OcaPropertyKeyPathCache()

  private struct CacheEntry {
    let keyPaths: [String: AnyKeyPath]
    let propertiesByID: [OcaPropertyID: AnyKeyPath]
    let propertiesByName: [String: AnyKeyPath]

    private init(keyPaths: [String: AnyKeyPath], object: some OcaRoot) {
      self.keyPaths = keyPaths
      propertiesByID = keyPaths.reduce(into: [:]) {
        guard let value = object[keyPath: $1.value] as? any OcaPropertySubjectRepresentable else {
          return
        }

        for propertyID in value.propertyIDs {
          $0[propertyID] = $1.value
        }
      }
      propertiesByName = keyPaths.reduce(into: [:]) {
        guard object[keyPath: $1.value] is any OcaPropertySubjectRepresentable else {
          return
        }

        $0[$1.key] = $1.value
      }
    }

    fileprivate init(object: some OcaRoot) {
      let keyPaths = object.allPropertyKeyPathsUncached
      self.init(keyPaths: keyPaths, object: object)
    }
  }

  private var _cache = [ObjectIdentifier: CacheEntry]()

  private func addCacheEntry(for object: some OcaRoot) -> CacheEntry {
    let cacheEntry = CacheEntry(object: object)
    _cache[object._metaTypeObjectIdentifier] = cacheEntry
    return cacheEntry
  }

  @OcaConnection
  fileprivate func keyPaths(for object: some OcaRoot) -> [String: AnyKeyPath] {
    if let cacheEntry = _cache[object._metaTypeObjectIdentifier] {
      return cacheEntry.keyPaths
    }

    return addCacheEntry(for: object).keyPaths
  }

  @OcaConnection
  fileprivate func lookupProperty(
    byID propertyID: OcaPropertyID,
    for object: some OcaRoot
  ) -> AnyKeyPath? {
    if let cacheEntry = _cache[object._metaTypeObjectIdentifier] {
      return cacheEntry.propertiesByID[propertyID]
    }

    return addCacheEntry(for: object).propertiesByID[propertyID]
  }

  @OcaConnection
  fileprivate func lookupProperty(
    byName name: String,
    for object: some OcaRoot
  ) -> AnyKeyPath? {
    if let cacheEntry = _cache[object._metaTypeObjectIdentifier] {
      return cacheEntry.propertiesByName[name]
    }

    return addCacheEntry(for: object).propertiesByName[name]
  }
}

extension OcaRoot: Equatable {
  public static func == (lhs: OcaRoot, rhs: OcaRoot) -> Bool {
    lhs.connectionDelegate == rhs.connectionDelegate &&
      lhs.objectNumber == rhs.objectNumber
  }
}

extension OcaRoot: Hashable {
  public func hash(into hasher: inout Hasher) {
    connectionDelegate?.hash(into: &hasher)
    hasher.combine(objectNumber)
  }
}

public struct OcaGetPathParameters: Ocp1ParametersReflectable {
  public var namePath: OcaNamePath
  public var oNoPath: OcaONoPath

  public init(namePath: OcaNamePath, oNoPath: OcaONoPath) {
    self.namePath = namePath
    self.oNoPath = oNoPath
  }
}

extension OcaRoot {
  func getPath(methodID: OcaMethodID) async throws -> (OcaNamePath, OcaONoPath) {
    let responseParams: OcaGetPathParameters
    responseParams = try await sendCommandRrq(methodID: methodID)
    return (responseParams.namePath, responseParams.oNoPath)
  }
}

public struct OcaGetPortNameParameters: Ocp1ParametersReflectable {
  public let portID: OcaPortID

  public init(portID: OcaPortID) {
    self.portID = portID
  }
}

public struct OcaSetPortNameParameters: Ocp1ParametersReflectable {
  public let portID: OcaPortID
  public let name: OcaString

  public init(portID: OcaPortID, name: OcaString) {
    self.portID = portID
    self.name = name
  }
}

public protocol OcaOwnable: OcaRoot {
  var owner: OcaProperty<OcaONo>.PropertyValue { get set }

  var path: (OcaNamePath, OcaONoPath) { get async throws }

  @_spi(SwiftOCAPrivate)
  func _getOwner(flags: OcaPropertyResolutionFlags) async throws -> OcaONo
}

protocol OcaOwnablePrivate: OcaOwnable {
  func _set(owner: OcaONo)
}

@_spi(SwiftOCAPrivate)
public extension OcaOwnable {
  func _getOwnerObject(flags: OcaPropertyResolutionFlags = .defaultFlags) async throws
    -> OcaBlock
  {
    let owner = try await _getOwner(flags: flags)
    if owner == OcaInvalidONo {
      throw Ocp1Error.status(.parameterOutOfRange)
    }

    guard let ownerObject = try await connectionDelegate?
      .resolve(object: OcaObjectIdentification(
        oNo: owner,
        classIdentification: OcaBlock.classIdentification
      )) as? OcaBlock
    else {
      throw Ocp1Error.invalidObject(owner)
    }
    return ownerObject
  }
}

@_spi(SwiftOCAPrivate)
public extension OcaRoot {
  func _getRole() async throws -> String {
    try await $role._getValue(self, flags: [.cacheValue, .returnCachedValue])
  }

  private func getRolePathFallback(flags: OcaPropertyResolutionFlags = .defaultFlags) async throws
    -> OcaNamePath?
  {
    if objectNumber == OcaRootBlockONo {
      return []
    }

    var path = [String]()
    var currentObject = self

    repeat {
      guard let role = try? await currentObject._getRole() else {
        return nil
      }

      guard let ownableObject = currentObject as? OcaOwnable else {
        return nil
      }

      if ownableObject.objectNumber == OcaRootBlockONo {
        break
      }

      let ownerONo = await (try? ownableObject._getOwner(flags: flags)) ?? OcaInvalidONo
      guard ownerONo != OcaInvalidONo else {
        break // we are at the root
      }

      path.insert(role, at: 0)

      guard let cachedObject = await connectionDelegate?.resolve(cachedObject: ownerONo)
      else {
        return nil
      }
      currentObject = cachedObject
    } while true

    return path
  }

  func _getRolePath(flags: OcaPropertyResolutionFlags = .defaultFlags) async throws
    -> OcaNamePath
  {
    if objectNumber == OcaRootBlockONo {
      return []
    } else if let localRolePath = try await getRolePathFallback(flags: flags) {
      return localRolePath
    } else if let self = self as? OcaOwnable {
      return try await self.path.0
    } else {
      throw Ocp1Error.objectClassMismatch
    }
  }
}

package extension OcaONo {
  var oNoString: String {
    "<\(String(format: "0x%08x", self))>"
  }

  init?(oNoString: String) {
    guard oNoString.hasPrefix("<") && oNoString.hasSuffix(">") else {
      return nil
    }
    let offset: Int
    offset = oNoString.hasPrefix("<0x") ? 3 : 1
    let start = oNoString.index(oNoString.startIndex, offsetBy: offset)
    let end = oNoString.index(oNoString.endIndex, offsetBy: -1)
    guard let oNo = OcaONo(String(oNoString[start..<end]), radix: offset == 1 ? 10 : 16) else {
      return nil
    }
    self = oNo
  }
}

public extension OcaRoot {
  @_spi(SwiftOCAPrivate) @OcaConnection
  func forward(event: OcaEvent, eventData: OcaAnyPropertyChangedEventData) async throws {
    for (_, keyPath) in allKeyPaths {
      if let property = self[keyPath: keyPath] as? (any OcaPropertyChangeEventNotifiable),
         property.propertyIDs.contains(eventData.propertyID)
      {
        try await sendCommand(
          methodID: property.setMethodID!,
          parameters: eventData.propertyValue
        )
        break
      }
    }
  }
}
