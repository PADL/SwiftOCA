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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@_spi(SwiftOCAPrivate)
import SwiftOCA

private let OcaMatrixWildcardCoordinate: OcaUint16 = 0xFFFF

open class OcaMatrix<Member: OcaRoot>: OcaWorker {
  override open class var classID: OcaClassID {
    OcaClassID("1.1.5")
  }

  public private(set) var members: OcaArray2D<Member?>

  public private(set) var proxy: Proxy<Member>!

  private var lockStatePriorToSetCurrentXY: LockState?

  public init(
    rows: OcaUint16,
    columns: OcaUint16,
    objectNumber: OcaONo? = nil,
    lockable: OcaBoolean = true,
    role: OcaString = "Matrix",
    deviceDelegate: OcaDevice? = nil,
    addToRootBlock: Bool = true
  ) async throws {
    guard rows < OcaMatrixWildcardCoordinate,
          columns < OcaMatrixWildcardCoordinate
    else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    members = OcaArray2D<Member?>(nX: columns, nY: rows, defaultValue: nil)
    try await super.init(
      objectNumber: objectNumber,
      lockable: lockable,
      role: role,
      deviceDelegate: deviceDelegate,
      addToRootBlock: addToRootBlock
    )
    proxy = try await Proxy<Member>(self)
  }

  public required init(from decoder: Decoder) throws {
    throw Ocp1Error.notImplemented
  }

  public required init(
    objectNumber: OcaONo? = nil,
    lockable: OcaBoolean = true,
    role: OcaString? = nil,
    deviceDelegate: OcaDevice? = nil,
    addToRootBlock: Bool = true
  ) async throws {
    fatalError("not supported")
  }

  public class Proxy<ProxyMember: OcaRoot>: OcaRoot {
    weak var matrix: OcaMatrix<ProxyMember>?

    override public class var classIdentification: OcaClassIdentification {
      Member.classIdentification
    }

    public init(
      _ matrix: OcaMatrix<ProxyMember>
    ) async throws {
      try await super.init(
        lockable: matrix.lockable,
        role: "\(matrix.role) Proxy",
        deviceDelegate: matrix.deviceDelegate,
        addToRootBlock: false
      )
      self.matrix = matrix
    }

    public required init(from decoder: Decoder) throws {
      throw Ocp1Error.notImplemented
    }

    public required init(
      objectNumber: OcaONo? = nil,
      lockable: OcaBoolean = true,
      role: OcaString? = nil,
      deviceDelegate: OcaDevice? = nil,
      addToRootBlock: Bool = true
    ) async throws {
      try await super.init(
        objectNumber: objectNumber,
        lockable: lockable,
        role: role,
        deviceDelegate: deviceDelegate,
        addToRootBlock: addToRootBlock
      )
    }

    @OcaDevice
    fileprivate final class Box {
      var response: Ocp1Response?
      var lastStatus: OcaStatus?

      func handleCommand(
        _ command: Ocp1Command,
        from controller: any OcaController,
        object: ProxyMember
      ) async throws {
        if let response, response.parameters.parameterCount > 0 {
          // we have an existing response for a get request, multiple gets are unsupported
          throw Ocp1Error.invalidProxyMethodResponse
        }

        do {
          response = try await object.handleCommand(command, from: controller)
          record(.ok)
        } catch let Ocp1Error.status(status) {
          record(status)
        } catch {
          record(.processingFailed) // shouldn't happen
        }
      }

      /// The first member's status stands until another disagrees: then success mixed
      /// with failure is partial success, and differing failures a processing failure.
      private func record(_ status: OcaStatus) {
        guard let lastStatus else {
          self.lastStatus = status
          return
        }
        guard lastStatus != status else { return }
        self.lastStatus = lastStatus == .ok || status == .ok ? .partiallySucceeded : .processingFailed
      }

      func getResponse() throws -> Ocp1Response {
        if let lastStatus, lastStatus != .ok {
          throw Ocp1Error.status(lastStatus)
        }

        return response ?? Ocp1Response()
      }
    }

    override open func handleCommand(
      _ command: Ocp1Command,
      from controller: any OcaController
    ) async throws -> Ocp1Response {
      if command.methodID.defLevel == 1 {
        if command.methodID.methodIndex == 1 {
          let response = ProxyMember.classIdentification
          return try encodeResponse(response)
        } else {
          return try await super.handleCommand(command, from: controller)
        }
      }
      guard let matrix else {
        throw Ocp1Error.status(.deviceError)
      }

      let box = Box()

      try await matrix.withCurrentObject { object in
        try await box.handleCommand(command, from: controller, object: object)
      }

      try matrix.unlockSelfAndProxy(controller: controller)
      return try box.getResponse()
    }
  }

  private func lockSelfAndProxy(controller: any OcaController) throws {
    guard lockable else { return }

    switch lockState {
    case .unlocked:
      lockStatePriorToSetCurrentXY = .unlocked
      lockState = .lockedNoReadWrite(controller.id)
    case let .lockedNoWrite(lockholder):
      fallthrough
    case let .lockedNoReadWrite(lockholder):
      guard controller.id == lockholder else {
        throw Ocp1Error.status(.locked)
      }
      // a repeated SetCurrentXY must not replace the state the first one saved with
      // its own temporary lock, or the proxy call that restores it leaves us locked
      if lockStatePriorToSetCurrentXY == nil {
        lockStatePriorToSetCurrentXY = lockState
      }
      lockState = .lockedNoReadWrite(controller.id)
    }
    proxy.lockState = lockState
  }

  fileprivate func unlockSelfAndProxy(controller: any OcaController) throws {
    guard lockable else { return }

    guard let lockStatePriorToSetCurrentXY else {
      throw Ocp1Error.status(.invalidRequest)
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
      lockState = lockStatePriorToSetCurrentXY
      proxy.lockState = lockStatePriorToSetCurrentXY
      self.lockStatePriorToSetCurrentXY = nil
    }
  }

  @OcaVectorDeviceProperty(
    xPropertyID: OcaPropertyID("3.1"),
    yPropertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.1")
  )
  public var currentXY = OcaVector2D<OcaMatrixCoordinate>(
    x: OcaMatrixWildcardCoordinate,
    y: OcaMatrixWildcardCoordinate
  )

  private func notifySubscribers(
    members: OcaArray2D<Member?>,
    changeType: OcaPropertyChangeType
  ) async throws {
    let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
    let parameters = OcaPropertyChangedEventData<OcaArray2D<Member?>>(
      propertyID: OcaPropertyID("3.5"),
      propertyValue: members,
      changeType: changeType
    )

    try await deviceDelegate?.notifySubscribers(
      event,
      parameters: parameters
    )
  }

  private func isValid(coordinate: OcaVector2D<OcaMatrixCoordinate>) async -> Bool {
    coordinate.x < members.nX && coordinate.y < members.nY
  }

  open func add(
    member object: Member,
    at coordinate: OcaVector2D<OcaMatrixCoordinate>
  ) async throws {
    precondition(object != self)
    guard await isValid(coordinate: coordinate) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    members[Int(coordinate.x), Int(coordinate.y)] = object
    try? await notifySubscribers(members: members, changeType: .itemAdded)
  }

  open func remove(coordinate: OcaVector2D<OcaMatrixCoordinate>) async throws {
    guard await isValid(coordinate: coordinate) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    guard members[Int(coordinate.x), Int(coordinate.y)] != nil else {
      throw Ocp1Error.status(.parameterError)
    }
    members[Int(coordinate.x), Int(coordinate.y)] = nil
    try? await notifySubscribers(members: members, changeType: .itemDeleted)
  }

  open func set(
    member object: Member,
    at coordinate: OcaVector2D<OcaMatrixCoordinate>
  ) async throws {
    precondition(object != self)
    guard await isValid(coordinate: coordinate) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    members[Int(coordinate.x), Int(coordinate.y)] = object
    try? await notifySubscribers(members: members, changeType: .itemChanged)
  }

  /// The members of the current area — the whole matrix, a row, a column or a single
  /// cell, according to the wildcards in `currentXY`. Empty cells are skipped.
  private func currentMembers() -> [Member] {
    let members = members
    if currentXY.x == OcaMatrixWildcardCoordinate, currentXY.y == OcaMatrixWildcardCoordinate {
      return members.items.compactMap { $0 }
    } else if currentXY.x == OcaMatrixWildcardCoordinate {
      return (0..<members.nX).compactMap { members[$0, Int(currentXY.y)] }
    } else if currentXY.y == OcaMatrixWildcardCoordinate {
      return (0..<members.nY).compactMap { members[Int(currentXY.x), $0] }
    } else {
      precondition(currentXY.x < members.nX)
      precondition(currentXY.y < members.nY)
      return [members[Int(currentXY.x), Int(currentXY.y)]].compactMap { $0 }
    }
  }

  func withCurrentObject(_ body: @Sendable (_ object: Member) async throws -> ()) async rethrows {
    for object in currentMembers() {
      try await body(object)
    }
  }

  /// SetCurrentXY's work, shared with SetCurrentXYLock: validate and set the current
  /// area, then lock the matrix and its proxy until the next proxy call.
  private func setCurrentXY(_ command: Ocp1Command, from controller: any OcaController) async throws {
    let coordinates: OcaVector2D<OcaMatrixCoordinate> = try decodeCommand(command)
    try await ensureWritable(by: controller, command: command)
    let members = members
    guard coordinates.x < members.nX || coordinates.x == OcaMatrixWildcardCoordinate,
          coordinates.y < members.nY || coordinates.y == OcaMatrixWildcardCoordinate
    else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    currentXY = coordinates
    try lockSelfAndProxy(controller: controller)
  }

  /// Whether `lockNoReadWrite` would succeed for `member`, checked up front so that
  /// SetCurrentXYLock can fail before locking anything.
  private static func ensureLockable(_ member: Member, by controller: any OcaController) throws {
    guard controller.flags.contains(.supportsLocking) else {
      throw Ocp1Error.status(.permissionDenied)
    }
    guard member.lockable else {
      throw Ocp1Error.status(.notImplemented)
    }
    switch member.lockState {
    case .unlocked:
      break
    case let .lockedNoWrite(lockholder), let .lockedNoReadWrite(lockholder):
      guard controller.id == lockholder else {
        throw Ocp1Error.status(.locked)
      }
    }
  }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.7"),
    getMethodID: OcaMethodID("3.11"),
    setMethodID: OcaMethodID("3.12")
  )
  public var portsPerRow: OcaUint8 = 0

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.8"),
    getMethodID: OcaMethodID("3.13"),
    setMethodID: OcaMethodID("3.14")
  )
  public var portsPerColumn: OcaUint8 = 0

  /// GetSize's six output parameters (a record, so each is counted and named)
  struct MatrixSize<T: Codable>: Ocp1ParametersReflectable {
    var xSize: T
    var ySize: T
    var minXSize: T
    var maxXSize: T
    var minYSize: T
    var maxYSize: T
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.3"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      let size = OcaVector2D<OcaMatrixCoordinate>(
        x: OcaMatrixCoordinate(members.nX),
        y: OcaMatrixCoordinate(members.nY)
      )
      let matrixSize = MatrixSize<OcaMatrixCoordinate>(
        xSize: size.x,
        ySize: size.y,
        minXSize: 0,
        maxXSize: size.x,
        minYSize: 0,
        maxYSize: size.y
      )
      return try encodeResponse(matrixSize)
    case OcaMethodID("3.5"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      let members = members
        .map(defaultValue: OcaInvalidONo) { $0?.objectNumber ?? OcaInvalidONo }
      return try encodeResponse(members)
    case OcaMethodID("3.7"):
      let coordinates: OcaVector2D<OcaMatrixCoordinate> = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      let objectNumber = members[Int(coordinates.x), Int(coordinates.y)]?
        .objectNumber ?? OcaInvalidONo
      return try encodeResponse(objectNumber)
    case OcaMethodID("3.8"):
      let parameters: SwiftOCA.OcaMatrix.SetMemberParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      guard parameters.x < members.nX, parameters.y < members.nY else {
        throw Ocp1Error.status(.parameterOutOfRange)
      }
      if parameters.memberONo == OcaInvalidONo {
        throw Ocp1Error.status(.badONo)
      }
      let object = await deviceDelegate?.objects[parameters.memberONo] as? Member
      guard let object else {
        throw Ocp1Error.status(.badONo)
      }
      try await set(member: object, at: OcaVector2D(x: parameters.x, y: parameters.y))
    case OcaMethodID("3.9"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try encodeResponse(proxy.objectNumber)
    case OcaMethodID("3.2"):
      // SetCurrentXY locks the matrix and its proxy, but not the members (AES70-2)
      try await setCurrentXY(command, from: controller)
    case OcaMethodID("3.15"):
      // SetCurrentXYLock also locks every member of the new current area, failing
      // without locking any of them if one cannot be locked (AES70-2)
      try await setCurrentXY(command, from: controller)
      let members = currentMembers()
      for member in members {
        try Self.ensureLockable(member, by: controller)
      }
      for member in members {
        try await member.lockNoReadWrite(controller: controller)
      }
    case OcaMethodID("3.16"):
      // UnlockCurrent must not fail on a member that is already unlocked (AES70-2)
      try decodeNullCommand(command)
      for member in currentMembers() {
        if case .unlocked = member.lockState { continue }
        try await member.unlock(controller: controller)
      }
    default:
      return try await super.handleCommand(command, from: controller)
    }
    return Ocp1Response()
  }

  override public var isContainer: Bool {
    true
  }

  #if NonEmbeddedBuild
  override public func serialize(
    flags: OcaRoot.SerializationFlags = [],
    filter: OcaRoot.SerializationFilterFunction? = nil
  ) throws -> [String: any Sendable] {
    var jsonObject = try super.serialize(flags: flags, filter: filter)

    let membersJson = members.map(defaultValue: nil, \.?.objectNumber)
    do {
      jsonObject["3.5"] = try reencodeAsValidJSONObject(membersJson)
    } catch {
      guard flags.contains(.ignoreEncodingErrors) else {
        throw error
      }
    }
    return jsonObject
  }

  override public func deserialize(
    jsonObject: [String: Sendable],
    flags: DeserializationFlags = [],
    filter: DeserializationFilterFunction? = nil
  ) async throws {
    guard let deviceDelegate else { throw Ocp1Error.notConnected }

    try await super.deserialize(jsonObject: jsonObject, flags: flags, filter: filter)

    guard let membersJson = jsonObject["3.5"] as? [[OcaONo]],
          let membersJson = OcaArray2D<OcaONo>(arrayOfArrays: membersJson)
    else {
      if flags.contains(.ignoreDecodingErrors) {
        return
      } else {
        throw Ocp1Error.status(.badFormat)
      }
    }

    members = try await membersJson.asyncMap(defaultValue: nil) { @Sendable objectNumber in
      guard let member = await deviceDelegate.objects[objectNumber] else {
        if flags.contains(.ignoreUnknownObjectNumbers) {
          return nil
        } else {
          throw Ocp1Error.objectNotPresent(objectNumber)
        }
      }

      guard let member = member as? Member else {
        if flags.contains(.ignoreObjectClassMismatches) {
          return nil
        } else {
          throw Ocp1Error.objectClassMismatch
        }
      }

      return member
    }

    try? await notifySubscribers(members: members, changeType: .itemChanged)
  }
  #endif
}
