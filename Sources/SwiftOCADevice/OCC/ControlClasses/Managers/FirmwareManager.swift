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

@OcaDeviceClass
open class OcaFirmwareManager: OcaManager {
  override open class var classID: OcaClassID { OcaClassID("1.3.3") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var componentVersions = [OcaVersion]()

  public convenience init(deviceDelegate: OcaDevice? = nil) async throws {
    try await self.init(
      objectNumber: OcaFirmwareManagerONo,
      role: "FirmwareManager",
      deviceDelegate: deviceDelegate,
      addToRootBlock: true
    )
  }

  @OcaDeviceMethod(SwiftOCA.OcaFirmwareManager.Methods.startUpdateProcess)
  open func startUpdateProcess(from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaFirmwareManager.Methods.beginActiveImageUpdate)
  open func beginActiveImageUpdate(
    component: OcaComponent,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaFirmwareManager.Methods.addImageData)
  open func addImageData(
    id: OcaUint32,
    imageData: OcaBlob,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaFirmwareManager.Methods.verifyImage, access: .write)
  open func verifyImage(verifyData: OcaBlob, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaFirmwareManager.Methods.endActiveImageUpdate)
  open func endActiveImageUpdate(from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaFirmwareManager.Methods.beginPassiveComponentUpdate)
  open func beginPassiveComponentUpdate(
    component: OcaComponent,
    serverAddress: OcaNetworkAddress,
    updateFileName: OcaString,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaFirmwareManager.Methods.endUpdateProcess)
  open func endUpdateProcess(from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }
}
