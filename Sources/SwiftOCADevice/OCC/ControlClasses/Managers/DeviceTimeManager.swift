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

import SwiftOCA

open class OcaDeviceTimeManager: OcaManager {
  override open class var classID: OcaClassID { OcaClassID("1.3.10") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  open var deviceTimeNTP: OcaTimeNTP {
    get async throws {
      throw Ocp1Error.status(.notImplemented)
    }
  }

  open func set(deviceTimeNTP time: OcaTimeNTP) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.3")
  )
  public var timeSources = [OcaTimeSource]()

  // property handled explicitly in handleCommand()
  public var currentDeviceTimeSource: OcaTimeSource?

  open var deviceTimePTP: OcaTime {
    get async throws {
      throw Ocp1Error.status(.notImplemented)
    }
  }

  open func set(deviceTimePTP time: OcaTime) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  override public func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.1"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try await encodeResponse(deviceTimeNTP)
    case OcaMethodID("3.2"):
      let deviceTimeNTP: OcaTimeNTP = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await set(deviceTimeNTP: deviceTimeNTP)
      return Ocp1Response()
    case OcaMethodID("3.4"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      guard let currentDeviceTimeSource else {
        throw Ocp1Error.status(.invalidRequest)
      }
      return try encodeResponse(currentDeviceTimeSource)
    case OcaMethodID("3.5"):
      let newDeviceTimeSourceONo: OcaONo = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      guard let newDeviceTimeSource = timeSources
        .first(where: { $0.objectNumber == newDeviceTimeSourceONo })
      else {
        throw Ocp1Error.status(.badONo)
      }
      currentDeviceTimeSource = newDeviceTimeSource
      return Ocp1Response()
    case OcaMethodID("3.6"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try await encodeResponse(deviceTimePTP)
    case OcaMethodID("3.7"):
      let deviceTimePTP: OcaTime = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await set(deviceTimePTP: deviceTimePTP)
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }

  public convenience init(deviceDelegate: OcaDevice? = nil) async throws {
    try await self.init(
      objectNumber: OcaDeviceTimeManagerONo,
      role: "Device Time Manager",
      deviceDelegate: deviceDelegate,
      addToRootBlock: true
    )
  }
}
