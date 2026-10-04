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

@OcaMethods
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

  @OcaMethod("3.2", name: "StartUpdateProcess")
  public func startUpdateProcess() async throws

  @OcaMethod("3.3", name: "BeginActiveImageUpdate", parameterNames: ["Component"])
  public func beginActiveImageUpdate(component: OcaComponent) async throws

  public struct AddImageDataParameters: OcaParametersReflectable {
    public let id: OcaUint32
    public let imageData: OcaBlob

    public init(id: OcaUint32, imageData: OcaBlob) {
      self.id = id
      self.imageData = imageData
    }
  }

  @OcaMethod("3.4", name: "AddImageData", parameters: AddImageDataParameters.self)
  public func addImageData(id: OcaUint32, imageData: OcaBlob) async throws

  /// With `sync` false the chunk is sent without waiting for the response, so that an
  /// upload can pipeline its chunks.
  public func addImageData(id: OcaUint32, imageData: OcaBlob, sync: Bool) async throws {
    guard !sync else { return try await addImageData(id: id, imageData: imageData) }
    try await sendCommand(
      methodID: Methods.addImageData.methodID,
      parameters: AddImageDataParameters(id: id, imageData: imageData)
    )
  }

  @OcaMethod("3.5", name: "VerifyImage", parameterNames: ["VerifyData"])
  public func verifyImage(verifyData: OcaBlob) async throws

  @OcaMethod("3.6", name: "EndActiveImageUpdate")
  public func endActiveImageUpdate() async throws

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

  @OcaMethod(
    "3.7",
    name: "BeginPassiveComponentUpdate",
    parameters: BeginPassiveComponentUpdateParameters.self
  )
  public func beginPassiveComponentUpdate(
    component: OcaComponent,
    serverAddress: OcaNetworkAddress,
    updateFileName: OcaString
  ) async throws

  @OcaMethod("3.8", name: "EndUpdateProcess")
  public func endUpdateProcess() async throws
}
