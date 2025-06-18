//
// Copyright (c) 2025 PADL Software Pty Ltd
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

@_spi(SwiftOCAPrivate)
import SwiftOCA

open class OcaDataset: OcaRoot, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.5") }
  override open class var classVersion: OcaClassVersionNumber { 1 }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.1"),
    getMethodID: OcaMethodID("2.7")
  )
  public var owner: OcaONo = OcaInvalidONo

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.2"),
    getMethodID: OcaMethodID("2.8"),
    setMethodID: OcaMethodID("2.9")
  )
  public var name: OcaString = ""

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.3"),
    getMethodID: OcaMethodID("2.10"),
    setMethodID: OcaMethodID("2.11")
  )
  public var type = OcaMimeType()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.4"),
    getMethodID: OcaMethodID("2.12"),
    setMethodID: OcaMethodID("2.13")
  )
  public var readOnly: OcaBoolean = false

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.5"),
    getMethodID: OcaMethodID("2.14")
  )
  public var lastModificationTime = OcaTime()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.6")
  )
  public var maxSize: OcaUint64 = 0

  public init(
    owner: OcaONo,
    name: OcaString,
    type: OcaMimeType,
    readOnly: OcaBoolean = true,
    lastModificationTime: OcaTime = .now,
    maxSize: OcaUint64 = .max,
    objectNumber: OcaONo,
    lockable: OcaBoolean = true,
    role: OcaString? = nil,
    deviceDelegate: OcaDevice? = nil,
    addToRootBlock: Bool = false
  ) async throws {
    try await super.init(
      objectNumber: objectNumber,
      lockable: lockable,
      role: role ?? "Dataset \(name)",
      deviceDelegate: deviceDelegate,
      addToRootBlock: addToRootBlock
    )

    self.owner = owner
    self.name = name
    self.type = type
    self.readOnly = readOnly
    self.lastModificationTime = lastModificationTime
    self.maxSize = maxSize
  }

  public required nonisolated init(from decoder: Decoder) throws {
    fatalError("init(from:) has not been implemented")
  }

  private var _nextIOSessionHandle: OcaIOSessionHandle = 1

  private struct IOSession {
    let handle: OcaIOSessionHandle
    let controllerID: OcaController.ID
    let userData: Any

    init(controller: OcaController, handle: OcaIOSessionHandle, userData: Any) {
      controllerID = controller.id
      self.handle = handle
      self.userData = userData
    }
  }

  private var _ioSessions = [OcaIOSessionHandle: IOSession]()

  public func allocateIOSessionHandle(
    with userData: AnyObject,
    controller: OcaController
  ) -> OcaIOSessionHandle {
    _nextIOSessionHandle += 1
    let session = IOSession(
      controller: controller,
      handle: _nextIOSessionHandle,
      userData: userData
    )
    _ioSessions[_nextIOSessionHandle] = session
    return _nextIOSessionHandle
  }

  public func releaseIOSessionHandle(
    _ handle: OcaIOSessionHandle,
    controller: OcaController
  ) throws {
    guard let index = _ioSessions.index(forKey: handle) else {
      throw Ocp1Error.invalidHandle
    }
    guard _ioSessions[index].value.controllerID == controller.id else {
      throw Ocp1Error.status(.permissionDenied)
    }
    _ioSessions.remove(at: index)
  }

  func expireIOSessionHandles(controller: OcaController) {
    _ioSessions.filter { $1.controllerID == controller.id }.forEach { _ioSessions[$0.key] = nil }
  }

  public func resolveIOSessionHandle<T>(
    _ handle: OcaIOSessionHandle,
    controller: OcaController
  ) throws -> T {
    guard let session = _ioSessions[handle] else {
      throw Ocp1Error.invalidHandle
    }

    guard let userData = session.userData as? T else {
      throw Ocp1Error.datasetMimeTypeMismatch
    }

    return userData
  }

  open func openRead(
    lockState: OcaLockState,
    controller: OcaController
  ) async throws -> (OcaUint64, OcaIOSessionHandle) {
    throw Ocp1Error.notImplemented
  }

  open func openWrite(
    lockState: OcaLockState,
    controller: OcaController
  ) async throws -> (OcaUint64, OcaIOSessionHandle) {
    throw Ocp1Error.notImplemented
  }

  open func close(handle: OcaIOSessionHandle, controller: OcaController) async throws {
    throw Ocp1Error.notImplemented
  }

  open func read(
    handle: OcaIOSessionHandle,
    position: OcaUint64,
    partSize: OcaUint64,
    controller: OcaController
  ) async throws -> (OcaBoolean, OcaLongBlob) {
    throw Ocp1Error.notImplemented
  }

  open func write(
    handle: OcaIOSessionHandle,
    position: OcaUint64,
    part: OcaLongBlob,
    controller: OcaController
  ) async throws {
    throw Ocp1Error.notImplemented
  }

  open func clear(handle: OcaIOSessionHandle, controller: OcaController) async throws {
    throw Ocp1Error.notImplemented
  }

  open func getDataSetSizes() async throws -> (OcaUint64, OcaUint64) {
    throw Ocp1Error.notImplemented
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("2.1"):
      let lockState: OcaLockState = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      let (datasetSize, handle) = try await openRead(lockState: lockState, controller: controller)
      let response = SwiftOCA.OcaDataset.OpenReadParameters(
        datasetSize: datasetSize,
        handle: handle
      )
      return try encodeResponse(response)
    case OcaMethodID("2.2"):
      let lockState: OcaLockState = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      let (maxPartSize, handle) = try await openWrite(lockState: lockState, controller: controller)
      let response = SwiftOCA.OcaDataset.OpenWriteParameters(
        maxPartSize: maxPartSize,
        handle: handle
      )
      return try encodeResponse(response)
    case OcaMethodID("2.3"):
      let handle: OcaIOSessionHandle = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await close(handle: handle, controller: controller)
    case OcaMethodID("2.4"):
      let params: SwiftOCA.OcaDataset.ReadParameters = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      let (endOfData, part) = try await read(
        handle: params.handle,
        position: params.position,
        partSize: params.partSize,
        controller: controller
      )
      return try encodeResponse(SwiftOCA.OcaDataset.ReadResultParameters(
        endOfData: endOfData,
        part: part
      ))
    case OcaMethodID("2.5"):
      let params: SwiftOCA.OcaDataset.WriteParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await write(
        handle: params.handle,
        position: params.position,
        part: params.part,
        controller: controller
      )
    case OcaMethodID("2.6"):
      let handle: OcaIOSessionHandle = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await clear(handle: handle, controller: controller)
    default:
      return try await super.handleCommand(command, from: controller)
    }

    return Ocp1Response()
  }
}

extension OcaDataset {
  func applyParameters(to object: OcaBlock<some OcaRoot>, controller: OcaController) async throws {
    guard type == OcaParamDatasetMimeType else {
      throw Ocp1Error.datasetMimeTypeMismatch
    }

    let (size, handle) = try await openRead(lockState: .noLock, controller: controller)
    let (complete, blob) = try await read(
      handle: handle,
      position: 0,
      partSize: size,
      controller: controller
    )
    guard complete else {
      throw Ocp1Error.arrayOrDataTooBig // we assume we can read it in one call
    }

    guard owner == object.objectNumber else {
      throw Ocp1Error.datasetTargetMismatch
    }
    try await object.apply(parameterData: blob)
    try await close(handle: handle, controller: controller)
  }

  func storeParameters(object: OcaBlock<some OcaRoot>, controller: OcaController) async throws {
    guard type == OcaParamDatasetMimeType else {
      throw Ocp1Error.datasetMimeTypeMismatch
    }

    let blob: OcaLongBlob = try await object.serializeDatasetParameters()
    let (_, handle) = try await openWrite(lockState: .noLock, controller: controller)
    try await write(handle: handle, position: 0, part: blob, controller: controller)
    try await close(handle: handle, controller: controller)
  }
}
