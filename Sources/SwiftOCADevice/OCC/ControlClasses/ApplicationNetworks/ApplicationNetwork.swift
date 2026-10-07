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
open class OcaApplicationNetwork: OcaRoot, OcaOwnable, OcaLabelRepresentable {
  override open class var classID: OcaClassID {
    OcaClassID("1.4")
  }

  override open class var classVersion: OcaClassVersionNumber {
    1
  }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.1"),
    getMethodID: OcaMethodID("2.1"),
    setMethodID: OcaMethodID("2.2")
  )
  public var label = ""

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.2"),
    getMethodID: OcaMethodID("2.3")
  )
  public var owner = OcaInvalidONo

  @_spi(SwiftOCAPrivate)
  public nonisolated static var labelPropertyID: OcaPropertyID { OcaPropertyID("2.1") }
  @_spi(SwiftOCAPrivate)
  public nonisolated static var ownerPropertyID: OcaPropertyID { OcaPropertyID("2.2") }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.3"),
    getMethodID: OcaMethodID("2.4"),
    setMethodID: OcaMethodID("2.5"),
    ocp2GetName: "Name",
    ocp2SetName: "Name"
  )
  public var serviceID: OcaApplicationNetworkServiceID = .init()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.4"),
    getMethodID: OcaMethodID("2.6"),
    setMethodID: OcaMethodID("2.7"),
    ocp2GetName: "SystemInterfaces",
    ocp2SetName: "Descriptors"
  )
  public var systemInterfaces = [OcaNetworkSystemInterfaceDescriptor]()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.5"),
    getMethodID: OcaMethodID("2.8")
  )
  public var state: OcaApplicationNetworkState = .stopped

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("2.6"),
    getMethodID: OcaMethodID("2.9")
  )
  public var errorCode: OcaUint16 = 0

  @OcaDeviceMethod(SwiftOCA.OcaApplicationNetwork.Methods.control, access: .write)
  open func control(command: OcaApplicationNetworkCommand, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaApplicationNetwork.Methods.getPath)
  func getPath(from controller: any OcaController) async -> OcaGetPathParameters {
    await path
  }
}
