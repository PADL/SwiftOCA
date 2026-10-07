//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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
import Synchronization

@OcaClass
open class OcaRoot: CustomStringConvertible, @unchecked Sendable, _OcaObjectKeyPathRepresentable {
  typealias Root = OcaRoot

  public internal(set) weak var connectionDelegate: OcaConnection?

  fileprivate var subscriptionCancellable: OcaConnection.SubscriptionCancellable?

  /// 1.1
  open class var classID: OcaClassID {
    OcaClassID("1")
  }

  private var _classID: StaticProperty<OcaClassID> {
    StaticProperty<OcaClassID>(propertyIDs: [OcaPropertyID("1.1")], value: Self.classID)
  }

  /// 1.2
  open class var classVersion: OcaClassVersionNumber {
    3
  }

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
  private static let _objectNumberPropertyID = OcaPropertyID("1.3")
  public let objectNumber: OcaONo
  private var _objectNumber: StaticProperty<OcaONo> {
    StaticProperty<OcaONo>(propertyIDs: [Self._objectNumberPropertyID], value: objectNumber)
  }

  @OcaProperty(
    propertyID: OcaPropertyID("1.4"),
    getMethodID: OcaMethodID("1.2")
  )
  public var lockable: OcaProperty<OcaBoolean>.PropertyValue

  // the property's getter, as the device declares it
  @OcaMethod("1.2", name: "GetLockable", resultNames: ["Lockable"])
  public func getLockable() async throws -> OcaBoolean

  @OcaProperty(
    propertyID: OcaPropertyID("1.5"),
    getMethodID: OcaMethodID("1.5")
  )
  public var role: OcaProperty<OcaString>.PropertyValue

  @OcaMethod("1.5", name: "GetRole", resultNames: ["Role"])
  public func getRole() async throws -> OcaString

  @_spi(SwiftOCAPrivate)
  public func _set(role: OcaString) {
    $role.subject.send(.success(role))
  }

  @OcaProperty(
    propertyID: OcaPropertyID("1.6"),
    getMethodID: OcaMethodID("1.7"),
    ocp2GetName: "State"
  )
  public var lockState: OcaProperty<OcaLockState>.PropertyValue

  @OcaMethod("1.7", name: "GetLockState", resultNames: ["State"])
  public func getLockState() async throws -> OcaLockState

  public required init(objectNumber: OcaONo) {
    self.objectNumber = objectNumber
  }

  deinit {
    // only the declared properties, not the computed StaticProperty instances, which
    // are made afresh each time
    for (_, keyPath) in allKeyPathsUncached {
      if let value = self[keyPath: keyPath] as? (any OcaPropertySubjectRepresentable) {
        value.finish()
      }
    }
  }

  @OcaMethod("1.1", name: "GetClassIdentification", resultNames: ["ClassIdentification"])
  public func getClassIdentification() async throws -> OcaClassIdentification

  @available(*, deprecated, renamed: "setLockNoReadWrite")
  public func lockTotal() async throws {
    try await setLockNoReadWrite()
  }

  @OcaMethod("1.3", name: "SetLockNoReadWrite")
  public func setLockNoReadWrite() async throws

  @OcaMethod("1.4", name: "Unlock")
  public func unlock() async throws

  @available(*, deprecated, renamed: "setLockNoWrite")
  public func lockReadOnly() async throws {
    try await setLockNoWrite()
  }

  @OcaMethod("1.6", name: "SetLockNoWrite")
  public func setLockNoWrite() async throws

  public var isContainer: Bool {
    false
  }

  public nonisolated var description: String {
    if case let .success(value) = $role.currentValue {
      "\(type(of: self))(objectNumber: \(objectNumber.oNoString), role: \(value))"
    } else {
      "\(type(of: self))(objectNumber: \(objectNumber.oNoString))"
    }
  }

  #if NonEmbeddedBuild
  /// The object's properties as OCP.2 JSON: each property under its wire name with
  /// its AES70-4 marshaled value, the same encoding the protocol carries. Every member
  /// is a property; the class is identified by `ClassID` and `ClassVersion`.
  open func getJsonValue(
    flags: OcaPropertyResolutionFlags = .defaultFlags
  ) async -> [String: any Sendable] {
    precondition(objectNumber != OcaInvalidONo)

    guard self is OcaWorker else {
      return [:]
    }

    return await withTaskGroup(
      of: [String: Sendable].self,
      returning: [String: Sendable].self
    ) { taskGroup in
      for (_, propertyKeyPath) in await allPropertyKeyPaths {
        taskGroup.addTask { [weak self] in
          guard let self else { return [:] }
          let property =
            self[keyPath: propertyKeyPath] as! (any OcaPropertySubjectRepresentable)
          var dict = [String: Sendable]()

          if let jsonValue = try? await property.getJsonValue(
            self,
            keyPath: propertyKeyPath,
            flags: flags
          ) {
            dict.merge(jsonValue) { current, _ in current }
          }
          return dict
        }
      }
      return await taskGroup.collect()
        .reduce(into: [String: Sendable]()) { $0.merge($1) { $1 } }
    }
  }

  /// The OCP.2 wire name of a property for the JSON export, derived from its Swift
  /// name with no exceptions: the object number resolves to `ObjectNumber`, which is
  /// what AES70-2 calls that property (`ONo` is the model's name for object-number
  /// *parameters* and struct fields, not for this). A property the reflected table
  /// does not know falls back to its property ID.
  ///
  /// Private API, so that `ocacli` can name the properties it dumps from the device's own
  /// OCP.2 responses the same way.
  @_spi(SwiftOCAPrivate)
  public func _jsonPropertyName(for propertyID: OcaPropertyID) -> String {
    guard let name = propertyName(for: propertyID) else {
      return propertyID.description
    }
    return Ocp2Naming.wireName(name)
  }

  public var jsonObject: [String: any Sendable] {
    get async {
      await getJsonValue(flags: .defaultFlags)
    }
  }
  #endif

  public func propertyKeyPath(for propertyID: OcaPropertyID) -> AnyKeyPath? {
    OcaPropertyKeyPathCache.shared.lookupProperty(byID: propertyID, for: self)
  }

  public func propertyKeyPath(for name: String) -> AnyKeyPath? {
    OcaPropertyKeyPathCache.shared.lookupProperty(byName: name, for: self)
  }

  /// The Swift name of the property with `propertyID`, from which its OCP.2 wire name
  /// is derived.
  public func propertyName(for propertyID: OcaPropertyID) -> String? {
    OcaPropertyKeyPathCache.shared.lookupPropertyName(byID: propertyID, for: self)
  }
}

protocol _OcaObjectKeyPathRepresentable: AnyObject {}

extension _OcaObjectKeyPathRepresentable where Self: OcaRoot {
  fileprivate var _metaTypeObjectIdentifier: ObjectIdentifier {
    ObjectIdentifier(type(of: self))
  }

  var allKeyPaths: [String: AnyKeyPath] {
    OcaPropertyKeyPathCache.shared.keyPaths(for: self)
  }

  /// The storage of each property the object's classes declare, by the property's name.
  var allKeyPathsUncached: [String: AnyKeyPath] {
    type(of: self).propertyKeyPaths
  }
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

  @OcaConnectionActor
  var allPropertyKeyPaths: [String: AnyKeyPath] {
    get async {
      staticPropertyKeyPaths.merging(
        allKeyPaths.filter { self[keyPath: $0.value] is any OcaPropertySubjectRepresentable },
        uniquingKeysWith: { old, _ in old }
      )
    }
  }

  @OcaConnectionActor
  private func onPropertyEvent(event: OcaEvent, eventData: OcaEncodedEventData) {
    // the property with this ID from the class's key paths, worked out once, rather than
    // reading every property of the object in turn, computed ones included, and casting
    // each to find it
    guard let propertyID = try? OcaEventDataCoding.propertyID(from: eventData),
      let keyPath = OcaPropertyKeyPathCache.shared.lookupProperty(byID: propertyID, for: self),
      let value = self[keyPath: keyPath] as? (any OcaPropertyChangeEventNotifiable)
    else { return }

    try? value.onEvent(self, event: event, eventData: eventData)
  }

  @OcaConnectionActor
  func subscribe() async throws {
    guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
    if let subscriptionCancellable, connectionDelegate.isSubscribed(subscriptionCancellable) {
      return // already subscribed
    }
    // a cancellable the connection no longer holds is stale; re-register
    subscriptionCancellable = nil
    let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
    do {
      // per-object label: aliased proxies for the same ONo (e.g. a resolved
      // subclass alongside a connection's built-in manager) must each register
      // their own callback, or the loser's property subjects never see events
      subscriptionCancellable = try await connectionDelegate.addEventDataSubscription(
        label: "com.padl.SwiftOCA.OcaRoot.\(ObjectIdentifier(self))",
        event: event
      ) { [weak self] event, eventData in
        await self?.onPropertyEvent(event: event, eventData: eventData)
      }
    } catch Ocp1Error.alreadySubscribedToEvent(_) {
    } catch Ocp1Error.status(.invalidRequest) {
      // FIXME: in our device implementation not all properties can be subcribed to
    }
  }

  @OcaConnectionActor
  func unsubscribe() async throws {
    guard let subscriptionCancellable else { throw Ocp1Error.notSubscribedToEvent }
    guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
    self.subscriptionCancellable = nil
    try await connectionDelegate.removeSubscription(subscriptionCancellable)
  }

  @OcaConnectionActor
  func refreshAll() async {
    for (_, keyPath) in await allPropertyKeyPaths {
      let property = (self[keyPath: keyPath] as! any OcaPropertyRepresentable)
      await property.refresh(self)
    }
  }

  @OcaConnectionActor
  package func refreshAllSubscribed() async {
    for (_, keyPath) in await allPropertyKeyPaths {
      let property = (self[keyPath: keyPath] as! any OcaPropertySubjectRepresentable)
      guard property.hasValueOrError else { continue }
      await property.refreshAndSubscribe(self)
    }
  }

  internal var isSubscribed: Bool {
    get async throws {
      guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
      // this object's own live registration: another component's handler
      // doesn't feed our property subjects, and a cancellable the connection
      // has dropped is stale
      guard let subscriptionCancellable else { return false }
      return await connectionDelegate.isSubscribed(subscriptionCancellable)
    }
  }

  internal struct StaticProperty<T: Codable & Sendable>: OcaPropertySubjectRepresentable, Sendable {
    var valueType: Any.Type {
      T.self
    }

    typealias Value = T

    var getMethodID: OcaMethodID? {
      nil
    }

    var setMethodID: OcaMethodID? {
      nil
    }

    func _ocp2GetName(_ object: OcaRoot) -> String? {
      object._jsonPropertyName(for: propertyIDs[0])
    }

    func _ocp2ResponseNames(_ object: OcaRoot) -> [String]? {
      _ocp2GetName(object).map { [$0] }
    }

    var propertyIDs: [OcaPropertyID]
    var value: T
    let subject: AsyncCurrentValueSubject<PropertyValue>

    init(propertyIDs: [OcaPropertyID], value: T) {
      self.propertyIDs = propertyIDs
      self.value = value
      subject = AsyncCurrentValueSubject(.success(value))
    }

    func refresh(_ object: SwiftOCA.OcaRoot) async {}
    func subscribe(_ object: OcaRoot) async {}

    var description: String {
      String(describing: value)
    }

    var currentValue: OcaProperty<Value>.PropertyValue {
      OcaProperty<Value>.PropertyValue.success(value)
    }

    @_spi(SwiftOCAPrivate) @discardableResult
    public func _getValue(
      _ object: OcaRoot,
      flags: OcaPropertyResolutionFlags = .defaultFlags
    ) async throws -> Value {
      value
    }

    #if NonEmbeddedBuild
    func getJsonValue(
      _ object: OcaRoot,
      keyPath: AnyKeyPath,
      flags: OcaPropertyResolutionFlags = .defaultFlags
    ) async throws -> [String: any Sendable] {
      let name = _ocp2GetName(object) ?? propertyIDs[0].description
      return try [name: Ocp2JSON.sendable(Ocp2Encoder().encodeValue(value))]
    }
    #endif

    @_spi(SwiftOCAPrivate)
    public func _setValue(_ object: OcaRoot, _ anyValue: Any) async throws {
      throw Ocp1Error.propertyIsImmutable
    }
  }
}

extension AnyKeyPath: @retroactive @unchecked Sendable {}

/// Each class's property key paths, worked out once and shared by every instance of the
/// class. Synchronous, and safe to use from any thread: building an entry reads the
/// object's property wrappers, whose stored fields are constants, their values living in
/// their subjects.
private final class OcaPropertyKeyPathCache: Sendable {
  fileprivate static let shared = OcaPropertyKeyPathCache()

  private struct CacheEntry: Sendable {
    let keyPaths: [String: AnyKeyPath]
    let propertiesByID: [OcaPropertyID: AnyKeyPath]
    let propertiesByName: [String: AnyKeyPath]
    let propertyNamesByID: [OcaPropertyID: String]

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
      propertyNamesByID = keyPaths.reduce(into: [:]) {
        guard let value = object[keyPath: $1.value] as? any OcaPropertySubjectRepresentable else {
          return
        }

        for propertyID in value.propertyIDs {
          $0[propertyID] = $1.key
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

  private let _cache = Mutex([ObjectIdentifier: CacheEntry]())

  private func cacheEntry(for object: some OcaRoot) -> CacheEntry {
    let key = object._metaTypeObjectIdentifier
    if let cacheEntry = _cache.withLock({ $0[key] }) {
      return cacheEntry
    }

    // built outside the lock, as it reflects over the object; two threads building the
    // same class's entry at once build the same thing, and the first stored is kept
    let cacheEntry = CacheEntry(object: object)
    return _cache.withLock { cache in
      if let existing = cache[key] {
        return existing
      }
      cache[key] = cacheEntry
      return cacheEntry
    }
  }

  fileprivate func keyPaths(for object: some OcaRoot) -> [String: AnyKeyPath] {
    cacheEntry(for: object).keyPaths
  }

  fileprivate func lookupProperty(
    byID propertyID: OcaPropertyID,
    for object: some OcaRoot
  ) -> AnyKeyPath? {
    cacheEntry(for: object).propertiesByID[propertyID]
  }

  fileprivate func lookupProperty(
    byName name: String,
    for object: some OcaRoot
  ) -> AnyKeyPath? {
    cacheEntry(for: object).propertiesByName[name]
  }

  fileprivate func lookupPropertyName(
    byID propertyID: OcaPropertyID,
    for object: some OcaRoot
  ) -> String? {
    cacheEntry(for: object).propertyNamesByID[propertyID]
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

public struct OcaGetPathParameters: OcaParametersReflectable {
  public var rolePath: OcaNamePath
  public var oNoPath: OcaONoPath

  public init(rolePath: OcaNamePath, oNoPath: OcaONoPath) {
    self.rolePath = rolePath
    self.oNoPath = oNoPath
  }
}

public struct OcaGetPortNameParameters: OcaParametersReflectable {
  public let portID: OcaPortID

  public init(portID: OcaPortID) {
    self.portID = portID
  }
}

public struct OcaSetPortNameParameters: OcaParametersReflectable {
  public let portID: OcaPortID
  public let name: OcaString

  public init(portID: OcaPortID, name: OcaString) {
    self.portID = portID
    self.name = name
  }
}

public protocol OcaOwnable: OcaRoot {
  var owner: OcaProperty<OcaONo>.PropertyValue { get set }

  func getPath() async throws -> OcaGetPathParameters

  @_spi(SwiftOCAPrivate)
  func _getOwner(flags: OcaPropertyResolutionFlags) async throws -> OcaONo
}

public extension OcaOwnable {
  var objectNumberPath: OcaONoPath {
    get async throws {
      try await getPath().oNoPath
    }
  }

  var objectNumberPathString: String {
    get async throws {
      try await "/" + objectNumberPath.map(\.description).joined(separator: "/")
    }
  }

  var rolePath: OcaNamePath {
    get async throws {
      try await getPath().rolePath
    }
  }

  var rolePathString: String {
    get async throws {
      try await "/" + rolePath.joined(separator: "/")
    }
  }
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
      return try await self.getPath().rolePath
    } else {
      throw Ocp1Error.objectClassMismatch
    }
  }
}

public extension OcaRoot {
  @_spi(SwiftOCAPrivate) @OcaConnectionActor
  func forward(event: OcaEvent, eventData: OcaAnyPropertyChangedEventData) async throws {
    for (_, keyPath) in allKeyPaths {
      if let property = self[keyPath: keyPath] as? (any OcaPropertyChangeEventNotifiable),
         property.propertyIDs.contains(eventData.propertyID),
         let setMethodID = property.setMethodID
      {
        try await sendCommand(
          methodID: setMethodID,
          parameters: eventData.propertyValue
        )
        break
      }
    }
  }
}
