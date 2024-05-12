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

open class OcaFirmwareManager: OcaManager {
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

  public func startUpdateProcess() async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.2"))
  }

  public func beginActiveImageUpdate(component: OcaComponent) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.3"), parameters: component)
  }

  public struct AddImageDataParameters: Ocp1ParametersReflectable {
    public let id: OcaUint32
    public let imageData: OcaBlob

    public init(id: OcaUint32, imageData: OcaBlob) {
      self.id = id
      self.imageData = imageData
    }
  }

  public func addImageData(id: OcaUint32, _ imageData: OcaBlob) async throws {
    let parameters = AddImageDataParameters(id: id, imageData: imageData)
    try await sendCommandRrq(methodID: OcaMethodID("3.4"), parameters: parameters)
  }

  public func verifyImage(_ verifyData: OcaBlob) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.5"), parameters: verifyData)
  }

  public func endActiveImageUpdate() async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.6"))
  }

  public struct BeginPassiveComponentUpdateParameters: Ocp1ParametersReflectable {
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

  public func beginPassiveComponentUpdate(
    component: OcaComponent,
    serverAddress: OcaNetworkAddress,
    updateFileName: OcaString
  ) async throws {
    let parameters = BeginPassiveComponentUpdateParameters(
      component: component,
      serverAddress: serverAddress,
      updateFileName: updateFileName
    )
    try await sendCommandRrq(methodID: OcaMethodID("3.7"), parameters: parameters)
  }

  public func endUpdateProcess() async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.8"))
  }
}
