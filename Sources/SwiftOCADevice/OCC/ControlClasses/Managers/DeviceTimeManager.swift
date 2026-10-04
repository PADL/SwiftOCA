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

@OcaDeviceMethods
open class OcaDeviceTimeManager: OcaManager {
  override open class var classID: OcaClassID { OcaClassID("1.3.10") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  open var deviceTimeNTP: OcaTimeNTP {
    get async throws {
      throw Ocp1Error.status(.notImplemented)
    }
  }

  @OcaDeviceMethod(SwiftOCA.OcaDeviceTimeManager.getDeviceTimeNTP)
  func getDeviceTimeNTP(from controller: any OcaController) async throws -> OcaTimeNTP {
    try await deviceTimeNTP
  }

  @OcaDeviceMethod(SwiftOCA.OcaDeviceTimeManager.getCurrentDeviceTimeSource)
  func getCurrentDeviceTimeSource(from controller: any OcaController) throws -> OcaONo {
    guard let currentDeviceTimeSource else {
      throw Ocp1Error.status(.invalidRequest)
    }
    return currentDeviceTimeSource.objectNumber
  }

  @OcaDeviceMethod(SwiftOCA.OcaDeviceTimeManager.setCurrentDeviceTimeSource)
  func setCurrentDeviceTimeSource(_ timeSourceONo: OcaONo, from controller: any OcaController) throws {
    guard let timeSource = timeSources.first(where: { $0.objectNumber == timeSourceONo }) else {
      throw Ocp1Error.status(.badONo)
    }
    currentDeviceTimeSource = timeSource
  }

  @OcaDeviceMethod(SwiftOCA.OcaDeviceTimeManager.getDeviceTime)
  func getDeviceTimePTP(from controller: any OcaController) async throws -> OcaTime {
    try await deviceTimePTP
  }

  @OcaDeviceMethod(SwiftOCA.OcaDeviceTimeManager.setDeviceTimeNTP)
  open func set(deviceTimeNTP time: OcaTimeNTP, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.3"),
    ocp2GetName: "TimeSourceONos"
  )
  public var timeSources = [OcaTimeSource]()

  // property handled explicitly in handleCommand()
  public var currentDeviceTimeSource: OcaTimeSource?

  open var deviceTimePTP: OcaTime {
    get async throws {
      throw Ocp1Error.status(.notImplemented)
    }
  }

  @OcaDeviceMethod(SwiftOCA.OcaDeviceTimeManager.setDeviceTime)
  open func set(deviceTimePTP time: OcaTime, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  public convenience init(deviceDelegate: OcaDevice? = nil) async throws {
    try await self.init(
      objectNumber: OcaDeviceTimeManagerONo,
      role: "DeviceTimeManager",
      deviceDelegate: deviceDelegate,
      addToRootBlock: true
    )
  }
}
