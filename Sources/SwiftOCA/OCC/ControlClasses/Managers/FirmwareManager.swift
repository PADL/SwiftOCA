//
// Copyright (c) 2024 PADL Software Pty Ltd
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

open class OcaFirmwareManager: OcaManager, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.3.3") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var componentVersions: OcaListProperty<OcaVersion>.PropertyValue

  public convenience init() {
    self.init(objectNumber: OcaFirmwareManagerONo)
  }

  public static let startUpdateProcess =
    OcaMethodDescriptor<Void, Void>("3.2", name: "StartUpdateProcess")

  public func startUpdateProcess() async throws {
    try await invoke(Self.startUpdateProcess)
  }

  public static let beginActiveImageUpdate = OcaMethodDescriptor<OcaComponent, Void>(
    "3.3",
    name: "BeginActiveImageUpdate",
    parameterNames: ["Component"]
  )

  public func beginActiveImageUpdate(component: OcaComponent) async throws {
    try await invoke(Self.beginActiveImageUpdate, component)
  }

  public struct AddImageDataParameters: OcaParametersReflectable {
    public let id: OcaUint32
    public let imageData: OcaBlob

    public init(id: OcaUint32, imageData: OcaBlob) {
      self.id = id
      self.imageData = imageData
    }
  }

  public static let addImageData =
    OcaMethodDescriptor<AddImageDataParameters, Void>("3.4", name: "AddImageData")

  /// Without `sync` the command is sent and no response awaited, which `invoke` does not do.
  public func addImageData(
    id: OcaUint32,
    _ imageData: OcaBlob,
    sync: Bool = true
  ) async throws {
    let parameters = AddImageDataParameters(id: id, imageData: imageData)

    if sync {
      try await invoke(Self.addImageData, parameters)
    } else {
      try await sendCommand(
        methodID: Self.addImageData.methodID,
        parameters: parameters,
        parameterNames: Self.addImageData.erased.parameterNames
      )
    }
  }

  public static let verifyImage = OcaMethodDescriptor<OcaBlob, Void>(
    "3.5",
    name: "VerifyImage",
    parameterNames: ["VerifyData"]
  )

  public func verifyImage(_ verifyData: OcaBlob) async throws {
    try await invoke(Self.verifyImage, verifyData)
  }

  public static let endActiveImageUpdate =
    OcaMethodDescriptor<Void, Void>("3.6", name: "EndActiveImageUpdate")

  public func endActiveImageUpdate() async throws {
    try await invoke(Self.endActiveImageUpdate)
  }

  public struct BeginPassiveComponentUpdateParameters: OcaParametersReflectable {
    public let component: OcaComponent
    public let serverAddress: OcaNetworkAddress
    public let updateFileName: OcaString

    public init(
      component: OcaComponent,
      serverAddress: OcaNetworkAddress,
      updateFileName: OcaString
    ) {
      self.component = component
      self.serverAddress = serverAddress
      self.updateFileName = updateFileName
    }
  }

  public static let beginPassiveComponentUpdate =
    OcaMethodDescriptor<BeginPassiveComponentUpdateParameters, Void>(
      "3.7",
      name: "BeginPassiveComponentUpdate"
    )

  public func beginPassiveComponentUpdate(
    component: OcaComponent,
    serverAddress: OcaNetworkAddress,
    updateFileName: OcaString
  ) async throws {
    try await invoke(
      Self.beginPassiveComponentUpdate,
      .init(component: component, serverAddress: serverAddress, updateFileName: updateFileName)
    )
  }

  public static let endUpdateProcess =
    OcaMethodDescriptor<Void, Void>("3.8", name: "EndUpdateProcess")

  public func endUpdateProcess() async throws {
    try await invoke(Self.endUpdateProcess)
  }
}
