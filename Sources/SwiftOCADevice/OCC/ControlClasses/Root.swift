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
@_spi(SwiftOCAPrivate)
import SwiftOCA

extension OcaController {
  typealias ID = ObjectIdentifier

  nonisolated var id: ID {
    ObjectIdentifier(self)
  }
}

@OcaDevice
open class OcaRoot: CustomStringConvertible, Codable, Sendable, _OcaObjectKeyPathRepresentable {
  open nonisolated class var classID: OcaClassID { OcaClassID("1") }
  open nonisolated class var classVersion: OcaClassVersionNumber { 2 }

  public nonisolated let objectNumber: OcaONo
  public nonisolated let lockable: OcaBoolean
  public nonisolated let role: OcaString

  public internal(set) weak var deviceDelegate: OcaDevice?

  enum LockState: Equatable, Sendable, CustomStringConvertible {
    /// Oca-1-2023 uses this confusing `NoReadWrite` and `NoWrite` nomenclature
    case unlocked
    case lockedNoWrite(OcaController.ID)
    case lockedNoReadWrite(OcaController.ID)

    var lockState: OcaLockState {
      switch self {
      case .unlocked:
        .noLock
      case .lockedNoWrite:
        .lockNoWrite
      case .lockedNoReadWrite:
        .lockNoReadWrite
      }
    }

    var description: String {
      switch self {
      case .unlocked:
        "Unlocked"
      case .lockedNoWrite:
        "Read locked"
      case .lockedNoReadWrite:
        "Read/write locked"
      }
    }
  }

  var lockStateSubject = AsyncCurrentValueSubject<LockState>(.unlocked)

  private func notifySubscribers(
    lockState: LockState
  ) async throws {
    let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
    let parameters = OcaPropertyChangedEventData<OcaLockState>(
      propertyID: OcaPropertyID("1.6"),
      propertyValue: lockState.lockState,
      changeType: .currentChanged
    )

    try await deviceDelegate?.notifySubscribers(
      event,
      parameters: parameters
    )
  }

  var lockState: LockState {
    get {
      lockStateSubject.value
    }
    set {
      lockStateSubject.value = newValue
    }
  }

  private func setLockState(_ newValue: LockState) async {
    lockState = newValue
    try? await notifySubscribers(lockState: newValue)
  }

  public nonisolated class var classIdentification: OcaClassIdentification {
    OcaClassIdentification(classID: classID, classVersion: classVersion)
  }

  public var objectIdentification: OcaObjectIdentification {
    OcaObjectIdentification(oNo: objectNumber, classIdentification: Self.classIdentification)
  }

  public required init(
    objectNumber: OcaONo? = nil,
    lockable: OcaBoolean = true,
    role: OcaString? = nil,
    deviceDelegate: OcaDevice? = nil,
    addToRootBlock: Bool = true
  ) async throws {
    if let objectNumber {
      precondition(objectNumber != OcaInvalidONo)
      self.objectNumber = objectNumber
    } else {
      self.objectNumber = await deviceDelegate?.allocateObjectNumber() ?? OcaInvalidONo
    }
    self.lockable = lockable
    self.role = role ?? String(self.objectNumber)
    self.deviceDelegate = deviceDelegate
    if let deviceDelegate {
      try await deviceDelegate.register(object: self, addToRootBlock: addToRootBlock)
    }
  }

  deinit {
    for (_, propertyKeyPath) in allDevicePropertyKeyPathsUncached {
      let property = self[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)
      property.finish()
    }
  }

  enum CodingKeys: String, CodingKey {
    case objectNumber = "oNo"
    case classIdentification = "1.1"
    case lockable = "1.2"
    case role = "1.3"
  }

  public nonisolated func encode(to encoder: Encoder) throws {
    // Always encode as just the object number. Deep serialization of object
    // state is handled by OcaBlock.serialize() which calls serialize() on
    // each action object directly, not through Codable.
    var container = encoder.singleValueContainer()
    try container.encode(objectNumber)
  }

  public required nonisolated init(from decoder: Decoder) throws {
    throw Ocp1Error.notImplemented
  }

  open nonisolated var description: String {
    let objectNumberString = "0x\(objectNumber.hexString(width: 8))"
    return "\(type(of: self))(objectNumber: \(objectNumberString), role: \(role))"
  }

  private func handlePropertyAccessor(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    guard let method = OcaDevicePropertyKeyPathCache.shared
      .lookupMethod(command.methodID, for: self)
    else {
      await deviceDelegate?.logger.info("unknown property accessor method \(command)")
      throw Ocp1Error.status(.notImplemented)
    }

    let property = self[keyPath: method.1] as! (any OcaDevicePropertyRepresentable)

    switch method.0 {
    case .getter:
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try await property.getOcp1Response()
    case .setter:
      try await ensureWritable(by: controller, command: command)
      try await property.set(object: self, command: command)
      return Ocp1Response()
    }
  }

  open func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("1.1"):
      struct GetClassIdentificationParameters: Ocp1ParametersReflectable {
        let classIdentification: OcaClassIdentification
      }
      let response =
        GetClassIdentificationParameters(
          classIdentification: objectIdentification
            .classIdentification
        )
      return try encodeResponse(response)
    case OcaMethodID("1.2"):
      try decodeNullCommand(command)
      return try encodeResponse(lockable)
    case OcaMethodID("1.3"):
      try decodeNullCommand(command)
      try await lockNoReadWrite(controller: controller)
    case OcaMethodID("1.4"):
      try decodeNullCommand(command)
      try await unlock(controller: controller)
    case OcaMethodID("1.5"):
      try decodeNullCommand(command)
      return try encodeResponse(role)
    case OcaMethodID("1.6"):
      try decodeNullCommand(command)
      try await lockNoWrite(controller: controller)
    case OcaMethodID("1.7"):
      try decodeNullCommand(command)
      return try encodeResponse(lockState.lockState)
    default:
      return try await handlePropertyAccessor(command, from: controller)
    }
    return Ocp1Response()
  }

  public var isContainer: Bool {
    false
  }

  open func ensureReadable(
    by controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    if let deviceManager = await deviceDelegate?.deviceManager, deviceManager != self {
      try await deviceManager.ensureReadable(by: controller, command: command)
    }

    switch lockState {
    case .unlocked:
      break
    case .lockedNoWrite:
      break
    case let .lockedNoReadWrite(lockholder):
      guard controller.id == lockholder else {
        throw Ocp1Error.status(.locked)
      }
    }
  }

  /// Important note: when subclassing you will typically want to override ensureWritable() to
  /// implement your own form of access control.
  open func ensureWritable(
    by controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    if let deviceManager = await deviceDelegate?.deviceManager, deviceManager != self {
      try await deviceManager.ensureWritable(by: controller, command: command)
    }

    switch lockState {
    case .unlocked:
      break
    case let .lockedNoWrite(lockholder):
      fallthrough
    case let .lockedNoReadWrite(lockholder):
      guard controller.id == lockholder else {
        throw Ocp1Error.status(.locked)
      }
    }
  }

  func lockNoWrite(controller: any OcaController) async throws {
    guard controller.flags.contains(.supportsLocking) else {
      throw Ocp1Error.status(.permissionDenied)
    }

    if !lockable {
      throw Ocp1Error.status(.notImplemented)
    }

    switch lockState {
    case .unlocked:
      await setLockState(.lockedNoWrite(controller.id))
    case .lockedNoWrite:
      throw Ocp1Error.status(.locked)
    case let .lockedNoReadWrite(lockholder):
      guard controller.id == lockholder else {
        throw Ocp1Error.status(.locked)
      }
      // downgrade lock
      await setLockState(.lockedNoWrite(controller.id))
    }
  }

  func lockNoReadWrite(controller: any OcaController) async throws {
    guard controller.flags.contains(.supportsLocking) else {
      throw Ocp1Error.status(.permissionDenied)
    }

    if !lockable {
      throw Ocp1Error.status(.notImplemented)
    }

    switch lockState {
    case .unlocked:
      await setLockState(.lockedNoReadWrite(controller.id))
    case let .lockedNoWrite(lockholder):
      guard controller.id == lockholder else {
        throw Ocp1Error.status(.locked)
      }
      await setLockState(.lockedNoReadWrite(controller.id))
    case .lockedNoReadWrite:
      throw Ocp1Error.status(.locked)
    }
  }

  func unlock(controller: any OcaController) async throws {
    guard controller.flags.contains(.supportsLocking) else {
      throw Ocp1Error.status(.permissionDenied)
    }

    if !lockable {
      throw Ocp1Error.status(.notImplemented)
    }

    switch lockState {
    case .unlocked:
      throw Ocp1Error.status(.invalidRequest)
    case let .lockedNoWrite(lockholder):
      fallthrough
    case let .lockedNoReadWrite(lockholder):
      guard controller.id == lockholder else {
        throw Ocp1Error.status(.locked)
      }
      await setLockState(.unlocked)
    }
  }

  func setLockState(to lockState: OcaLockState, controller: any OcaController) async -> Bool {
    do {
      switch lockState {
      case .noLock:
        try await unlock(controller: controller)
      case .lockNoWrite:
        try await lockNoWrite(controller: controller)
      case .lockNoReadWrite:
        try await lockNoReadWrite(controller: controller)
      }
      return true
    } catch {
      return false
    }
  }

  open func serialize(
    flags: SerializationFlags = [],
    filter: SerializationFilterFunction? = nil
  ) throws -> [String: any Sendable] {
    var dict = [String: any Sendable]()

    precondition(objectNumber != OcaInvalidONo)

    guard self is OcaWorker || self is OcaManager || self is OcaAgent else {
      return [:]
    }

    dict[objectNumberJSONKey] = objectNumber
    dict[classIDJSONKey] = Self.classID.description
    for (_, propertyKeyPath) in allDevicePropertyKeyPaths {
      let property = self[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)
      if let filter {
        switch filter(self, property.propertyID, property.wrappedValue) {
        case .ok:
          break
        case .ignore:
          continue
        case let .replace(newValue):
          dict[property.propertyID.description] = newValue
          continue
        }
      }
      do {
        dict[property.propertyID.description] = try property.getJsonValue()
      } catch {
        guard flags.contains(.ignoreEncodingErrors) else {
          throw error
        }
      }
    }

    return dict
  }

  private static let _globalTypePropertyID = OcaPropertyID("3.5")

  open func deserialize(
    jsonObject: [String: Sendable],
    flags: DeserializationFlags = [],
    filter: DeserializationFilterFunction? = nil
  ) async throws {
    guard let deviceDelegate else { throw Ocp1Error.notConnected }
    let logger = await deviceDelegate.logger

    guard let classIDString = jsonObject[classIDJSONKey] as? String else {
      logger.warning("bad or missing object class when deserializing")
      throw Ocp1Error.objectClassMismatch
    }

    let classID = try OcaClassID(unsafeString: classIDString)

    guard objectIdentification.classIdentification.classID.isSubclass(of: classID) else {
      logger.warning("object class mismatch between \(self) and \(classID)")
      throw Ocp1Error.objectClassMismatch
    }

    if let blockGlobalType = (self as? any OcaBlockContainer)?.globalType,
       let jsonGlobalType = jsonObject[Self._globalTypePropertyID.description] as? [String: Any]
    {
      guard let jsonGlobalType = OcaGlobalTypeIdentifier(jsonObject: jsonGlobalType) else {
        logger.warning("bad or missing global type ID when deserializing")
        throw Ocp1Error.status(.badFormat)
      }

      guard jsonGlobalType == blockGlobalType else {
        logger
          .warning(
            "global type ID mismatch between: decoded \(jsonGlobalType), but expected \(blockGlobalType)"
          )
        throw Ocp1Error.globalTypeMismatch
      }
    } else {
      guard let oNo = jsonObject[objectNumberJSONKey] as? OcaONo else {
        logger.warning("bad or missing object number when deserializing")
        throw Ocp1Error.status(.badFormat)
      }

      guard objectNumber == oNo else {
        logger.warning("object number mismatch between \(self) and \(oNo)")
        throw Ocp1Error.status(.badONo)
      }
    }

    for (_, propertyKeyPath) in allDevicePropertyKeyPaths {
      let property = self[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)
      let propertyName = property.propertyID.description

      guard let value = jsonObject[propertyName] else {
        if flags.contains(.ignoreMissingProperties) {
          continue
        } else {
          logger.warning("JSON object \(jsonObject) is missing \(propertyName)")
          throw Ocp1Error.status(.parameterOutOfRange)
        }
      }

      var effectiveValue = value
      if let filter {
        switch await filter(self, property.propertyID, value) {
        case .ok:
          break
        case .ignore:
          continue
        case let .replace(newValue):
          effectiveValue = newValue
        }
      }

      do {
        try await property.set(object: self, jsonValue: effectiveValue, device: deviceDelegate)
      } catch {
        logger
          .warning(
            "failed to set value \(value) on property \(propertyName) of \(self): \(error)"
          )
        if !flags.contains(.ignoreDecodingErrors) { throw error }
      }
    }
  }

  public var jsonObject: [String: any Sendable] {
    try! serialize(flags: .ignoreEncodingErrors)
  }
}

extension OcaRoot: Equatable {
  public nonisolated static func == (lhs: OcaRoot, rhs: OcaRoot) -> Bool {
    lhs.objectNumber == rhs.objectNumber
  }
}

extension OcaRoot: Hashable {
  public nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(objectNumber)
  }
}

protocol _OcaObjectKeyPathRepresentable: OcaRoot {}

extension OcaRoot {
  fileprivate var _metaTypeObjectIdentifier: ObjectIdentifier {
    ObjectIdentifier(type(of: self))
  }

  var allDevicePropertyKeyPaths: [String: AnyKeyPath] {
    OcaDevicePropertyKeyPathCache.shared.keyPaths(for: self)
  }

  // nonisolated(unsafe) is required because this is called from deinit (which
  // cannot be async). This is safe in practice because it only reads immutable
  // property wrapper metadata (propertyID, methodIDs) set at init time, and the
  // key paths are offset-based so they don't go through actor isolation.
  nonisolated(unsafe) var allDevicePropertyKeyPathsUncached: [String: AnyKeyPath] {
    _allKeyPaths(value: self).reduce(into: [:]) {
      if $1.key.hasPrefix("_") {
        $0[String($1.key.dropFirst())] = $1.value
      }
    }.filter {
      self[keyPath: $0.value] is any OcaDevicePropertyRepresentable
    }
  }
}

@OcaDevice
private final class OcaDevicePropertyKeyPathCache {
  fileprivate static let shared = OcaDevicePropertyKeyPathCache()

  enum AccessorType {
    case getter
    case setter
  }

  private struct CacheEntry {
    let keyPaths: [String: AnyKeyPath]
    let methods: [OcaMethodID: (AccessorType, AnyKeyPath)]

    private init(keyPaths: [String: AnyKeyPath], object: some OcaRoot) {
      self.keyPaths = keyPaths
      methods = keyPaths.reduce(into: [:]) {
        guard let value = object[keyPath: $1.value] as? any OcaDevicePropertyRepresentable else {
          return
        }
        if let getMethodID = value.getMethodID {
          $0[getMethodID] = (.getter, $1.value)
        }
        if let setMethodID = value.setMethodID {
          $0[setMethodID] = (.setter, $1.value)
        }
      }
    }

    @OcaDevice
    fileprivate init(object: some OcaRoot) {
      let keyPaths = object.allDevicePropertyKeyPathsUncached
      self.init(keyPaths: keyPaths, object: object)
    }
  }

  private var _cache = [ObjectIdentifier: CacheEntry]()

  private func addCacheEntry(for object: some OcaRoot) -> CacheEntry {
    let cacheEntry = CacheEntry(object: object)
    _cache[object._metaTypeObjectIdentifier] = cacheEntry
    return cacheEntry
  }

  @OcaDevice
  fileprivate func keyPaths(for object: some OcaRoot) -> [String: AnyKeyPath] {
    if let cacheEntry = _cache[object._metaTypeObjectIdentifier] {
      return cacheEntry.keyPaths
    }

    return addCacheEntry(for: object).keyPaths
  }

  @OcaDevice
  fileprivate func lookupMethod(
    _ methodID: OcaMethodID,
    for object: some OcaRoot
  ) -> (AccessorType, AnyKeyPath)? {
    if let cacheEntry = _cache[object._metaTypeObjectIdentifier] {
      return cacheEntry.methods[methodID]
    }

    return addCacheEntry(for: object).methods[methodID]
  }
}

@OcaDevice
public protocol OcaOwnable: OcaRoot {
  var owner: OcaONo { get set }
}

public extension OcaOwnable {
  func getOwnerObject<T>() async -> OcaBlock<T>? {
    await deviceDelegate?.objects[owner] as? OcaBlock<T>
  }
}

@OcaDevice
protocol OcaLabelRepresentable: OcaRoot {
  var label: OcaString { get set }
}

/// protocol for forwarding an event
@_spi(SwiftOCAPrivate)
public protocol _OcaEventForwarding {
  func forward(event: OcaEvent, eventData: OcaAnyPropertyChangedEventData) async throws
}

/// forward an event to a local object
@_spi(SwiftOCAPrivate)
extension OcaRoot: _OcaEventForwarding {
  @_spi(SwiftOCAPrivate)
  public func forward(event: OcaEvent, eventData: OcaAnyPropertyChangedEventData) async throws {
    guard event.emitterONo == objectNumber, event.eventID == OcaPropertyChangedEventID else {
      throw Ocp1Error.unhandledEvent
    }

    for (_, propertyKeyPath) in allDevicePropertyKeyPaths {
      let property = self[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)
      guard property.propertyID == eventData.propertyID else { continue }
      try await property.set(object: self, eventData: eventData)
    }
  }
}

/// forward an event to a remote object (implementation is in SwiftOCA as it uses private API)
@_spi(SwiftOCAPrivate)
extension SwiftOCA.OcaRoot: _OcaEventForwarding {}

/// copy all device property values from a local object to a remote object
@_spi(SwiftOCAPrivate)
public extension OcaRoot {
  @_spi(SwiftOCAPrivate)
  func copyProperties(to remoteObject: SwiftOCA.OcaRoot) async throws {
    for (_, propertyKeyPath) in allDevicePropertyKeyPaths {
      let property = self[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)
      try await property._forward(to: remoteObject)
    }
  }
}
