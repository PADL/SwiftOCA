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

  @OcaDeviceMethod("3.2", name: "StartUpdateProcess", access: .write)
  func startUpdateProcess(from controller: any OcaController) async throws {
    try await startUpdateProcess(controller: controller)
  }

  @OcaDeviceMethod("3.3", name: "BeginActiveImageUpdate", access: .write)
  func beginActiveImageUpdate(_ component: OcaComponent, from controller: any OcaController) async throws {
    try await beginActiveImageUpdate(component: component, controller: controller)
  }

  @OcaDeviceMethod("3.4", name: "AddImageData", access: .write)
  func addImageData(
    _ parameters: SwiftOCA.OcaFirmwareManager.AddImageDataParameters,
    from controller: any OcaController
  ) async throws {
    try await addImageData(id: parameters.id, parameters.imageData, controller: controller)
  }

  @OcaDeviceMethod("3.5", name: "VerifyImage", access: .write)
  func verifyImage(_ verifyData: OcaBlob, from controller: any OcaController) async throws {
    try await verifyImage(verifyData, controller: controller)
  }

  @OcaDeviceMethod("3.6", name: "EndActiveImageUpdate", access: .write)
  func endActiveImageUpdate(from controller: any OcaController) async throws {
    try await endActiveImageUpdate(controller: controller)
  }

  @OcaDeviceMethod("3.7", name: "BeginPassiveComponentUpdate", access: .write)
  func beginPassiveComponentUpdate(
    _ parameters: SwiftOCA.OcaFirmwareManager.BeginPassiveComponentUpdateParameters,
    from controller: any OcaController
  ) async throws {
    try await beginPassiveComponentUpdate(
      component: parameters.component,
      serverAddress: parameters.serverAddress,
      updateFileName: parameters.updateFileName,
      controller: controller
    )
  }

  @OcaDeviceMethod("3.8", name: "EndUpdateProcess", access: .write)
  func endUpdateProcess(from controller: any OcaController) async throws {
    try await endUpdateProcess(controller: controller)
  }

  open func startUpdateProcess(controller: OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func beginActiveImageUpdate(
    component: OcaComponent,
    controller: OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func addImageData(
    id: OcaUint32,
    _ imageData: OcaBlob,
    controller: OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func verifyImage(_ verifyData: OcaBlob, controller: OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func endActiveImageUpdate(controller: OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func beginPassiveComponentUpdate(
    component: OcaComponent,
    serverAddress: OcaNetworkAddress,
    updateFileName: OcaString,
    controller: OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func endUpdateProcess(controller: OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }
}
