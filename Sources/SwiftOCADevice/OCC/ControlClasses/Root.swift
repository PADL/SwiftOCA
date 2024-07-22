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
open class OcaRoot: CustomStringConvertible, Codable, @unchecked
Sendable, OcaKeyPathMarkerProtocol {
  open nonisolated class var classID: OcaClassID { OcaClassID("1") }
  open nonisolated class var classVersion: OcaClassVersionNumber { 2 }

  public nonisolated let objectNumber: OcaONo
  public nonisolated let lockable: OcaBoolean
  public nonisolated let role: OcaString

  public internal(set) weak var deviceDelegate: OcaDevice?

  enum LockState: Sendable, CustomStringConvertible {
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

  var lockState: LockState {
    get {
      lockStateSubject.value
    }
    set {
      lockStateSubject.value = newValue
    }
  }

  public nonisolated class var classIdentification: OcaClassIdentification {
    OcaClassIdentification(classID: classID, classVersion: classVersion)
  }

  public var objectIdentification: OcaObjectIdentification {
    OcaObjectIdentification(oNo: objectNumber, classIdentification: Self.classIdentification)
  }

  public init(
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
    for (_, propertyKeyPath) in allDevicePropertyKeyPaths {
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
    if encoder._isOcp1Encoder {
      var container = encoder.unkeyedContainer()
      try container.encode(objectNumber)
    } else {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(Self.classID.description, forKey: .classIdentification)
      try container.encode(objectNumber, forKey: .objectNumber)
      try container.encode(lockable, forKey: .lockable)
      try container.encode(role, forKey: .role)
    }
  }

  public required nonisolated init(from decoder: Decoder) throws {
    if decoder._isOcp1Decoder {
      throw Ocp1Error.notImplemented
    } else {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let classID = try OcaClassID(
        container
          .decode(String.self, forKey: .classIdentification)
      )
      guard classID == Self.classID else {
        throw Ocp1Error.objectClassMismatch
      }

      objectNumber = try container.decode(OcaONo.self, forKey: .objectNumber)
      lockable = try container.decode(OcaBoolean.self, forKey: .lockable)
      role = try container.decode(OcaString.self, forKey: .role)
      Task { @OcaDevice in deviceDelegate = OcaDevice.shared }
    }
  }

  public nonisolated var description: String {
    let objectNumberString = String(format: "0x%08x", objectNumber)
    return "\(type(of: self))(objectNumber: \(objectNumberString), role: \(role))"
  }

  private func handlePropertyAccessor(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    for (_, propertyKeyPath) in allDevicePropertyKeyPaths {
      let property = self[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)

      if command.methodID == property.getMethodID {
        try decodeNullCommand(command)
        try await ensureReadable(by: controller, command: command)
        return try await property.getOcp1Response()
      } else if command.methodID == property.setMethodID {
        try await ensureWritable(by: controller, command: command)
        try await property.set(object: self, command: command)
        return Ocp1Response()
      }
    }
    await deviceDelegate?.logger.info("unknown property accessor method \(command)")
    throw Ocp1Error.status(.notImplemented)
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
      try lockNoReadWrite(controller: controller)
    case OcaMethodID("1.4"):
      try decodeNullCommand(command)
      try unlock(controller: controller)
    case OcaMethodID("1.5"):
      try decodeNullCommand(command)
      return try encodeResponse(role)
    case OcaMethodID("1.6"):
      try decodeNullCommand(command)
      try lockNoWrite(controller: controller)
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

  func lockNoWrite(controller: any OcaController) throws {
    if !lockable {
      throw Ocp1Error.status(.notImplemented)
    }

    switch lockState {
    case .unlocked:
      lockState = .lockedNoWrite(controller.id)
    case .lockedNoWrite:
      throw Ocp1Error.status(.locked)
    case let .lockedNoReadWrite(lockholder):
      guard controller.id == lockholder else {
        throw Ocp1Error.status(.locked)
      }
      // downgrade lock
      lockState = .lockedNoWrite(controller.id)
    }
  }

  func lockNoReadWrite(controller: any OcaController) throws {
    if !lockable {
      throw Ocp1Error.status(.notImplemented)
    }

    switch lockState {
    case .unlocked:
      lockState = .lockedNoReadWrite(controller.id)
    case let .lockedNoWrite(lockholder):
      guard controller.id == lockholder else {
        throw Ocp1Error.status(.locked)
      }
      lockState = .lockedNoReadWrite(controller.id)
    case .lockedNoReadWrite:
      throw Ocp1Error.status(.locked)
    }
  }

  func unlock(controller: any OcaController) throws {
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
      lockState = .unlocked
    }
  }

  func setLockState(to lockState: OcaLockState, controller: any OcaController) -> Bool {
    do {
      switch lockState {
      case .noLock:
        try unlock(controller: controller)
      case .lockNoWrite:
        try lockNoWrite(controller: controller)
      case .lockNoReadWrite:
        try lockNoReadWrite(controller: controller)
      }
      return true
    } catch {
      return false
    }
  }

  public var jsonObject: [String: Any] {
    var dict = [String: Any]()

    precondition(objectNumber != OcaInvalidONo)

    guard self is OcaWorker else {
      return [:]
    }

    dict[objectNumberJSONKey] = objectNumber
    dict[classIDJSONKey] = Self.classID.description

    for (_, propertyKeyPath) in allDevicePropertyKeyPaths {
      let property = self[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)
      dict[property.propertyID.description] = try? property.getJsonValue()
    }

    return dict
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

protocol OcaKeyPathMarkerProtocol: AnyObject {}

extension OcaKeyPathMarkerProtocol where Self: OcaRoot {
  var allDevicePropertyKeyPaths: [String: PartialKeyPath<Self>] {
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
