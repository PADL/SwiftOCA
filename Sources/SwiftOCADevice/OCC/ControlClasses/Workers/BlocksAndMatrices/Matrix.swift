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

import Foundation
@_spi(SwiftOCAPrivate)
import SwiftOCA

private let OcaMatrixWildcardCoordinate: OcaUint16 = 0xFFFF

open class OcaMatrix<Member: OcaRoot>: OcaWorker {
  override open class var classID: OcaClassID { OcaClassID("1.1.5") }

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
          if lastStatus != .ok {
            lastStatus = .partiallySucceeded
          } else {
            lastStatus = .ok
          }
        } catch let Ocp1Error.status(status) {
          if lastStatus == .ok {
            lastStatus = .partiallySucceeded
          } else if lastStatus != status {
            lastStatus = .processingFailed
          } else {
            lastStatus = status
          }
        } catch {
          lastStatus = .processingFailed // shouldn't happen
        }
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
      lockStatePriorToSetCurrentXY = lockState
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

  func withCurrentObject(_ body: @Sendable (_ object: Member) async throws -> ()) async rethrows {
    if currentXY.x == OcaMatrixWildcardCoordinate && currentXY
      .y == OcaMatrixWildcardCoordinate
    {
      for object in members.items {
        if let object { try await body(object) }
      }
    } else if currentXY.x == OcaMatrixWildcardCoordinate {
      for x in 0..<members.nX {
        if let object = members[x, Int(currentXY.y)] { try await body(object) }
      }
    } else if currentXY.y == OcaMatrixWildcardCoordinate {
      for y in 0..<members.nY {
        if let object = members[Int(currentXY.x), y] { try await body(object) }
      }
    } else {
      precondition(currentXY.x < members.nX)
      precondition(currentXY.y < members.nY)

      if let object = members[Int(currentXY.x), Int(currentXY.y)] {
        try await body(object)
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

  struct MatrixSize<T: Codable>: Codable {
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
      fallthrough
    case OcaMethodID("3.15"):
      try decodeNullCommand(command)
      try await withCurrentObject { try await $0.lockNoReadWrite(controller: controller) }
    case OcaMethodID("3.16"):
      try decodeNullCommand(command)
      try await withCurrentObject { try await $0.unlock(controller: controller) }
    default:
      return try await super.handleCommand(command, from: controller)
    }
    return Ocp1Response()
  }

  override public var isContainer: Bool {
    true
  }

  override public func serialize(
    flags: OcaRoot.SerializationFlags = [],
    isIncluded: OcaRoot.SerializationFilterFunction? = nil
  ) throws -> [String: Any] {
    var jsonObject = try super.serialize(flags: flags, isIncluded: isIncluded)

    let membersJson = members.map(defaultValue: nil, \.?.objectNumber)
    do {
      jsonObject["3.5"] = try JSONEncoder().reencodeAsValidJSONObject(membersJson)
    } catch {
      guard flags.contains(.ignoreEncodingErrors) else {
        throw error
      }
    }
    return jsonObject
  }

  override public func deserialize(
    jsonObject: [String: Sendable],
    flags: DeserializationFlags = []
  ) async throws {
    guard let deviceDelegate else { throw Ocp1Error.notConnected }

    try await super.deserialize(jsonObject: jsonObject, flags: flags)

    guard let membersJson = jsonObject["3.5"] as? [[OcaONo]],
          let membersJson = OcaArray2D<OcaONo>(arrayOfArrays: membersJson)
    else {
      if flags.contains(.ignoreDecodingErrors) { return }
      else { throw Ocp1Error.status(.badFormat) }
    }

    members = try await membersJson.asyncMap(defaultValue: nil) { objectNumber in
      guard let member = await deviceDelegate.objects[objectNumber] else {
        if flags.contains(.ignoreUnknownObjectNumbers) { return nil }
        else { throw Ocp1Error.objectNotPresent(objectNumber) }
      }

      guard let member = member as? Member else {
        if flags.contains(.ignoreObjectClassMismatches) { return nil }
        else { throw Ocp1Error.objectClassMismatch }
      }

      return member
    }

    try? await notifySubscribers(members: members, changeType: .itemChanged)
  }
}
