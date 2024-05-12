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

open class OcaNetworkManager: OcaManager {
  override open class var classID: OcaClassID { OcaClassID("1.3.6") }

  // networks and streamNetworks are deprecated

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.3")
  )
  public var controlNetworks = [OcaControlNetwork]()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.4"),
    getMethodID: OcaMethodID("3.4")
  )
  public var mediaTransportNetworks = [OcaMediaTransportNetwork]()

  public convenience init(deviceDelegate: OcaDevice? = nil) async throws {
    try await self.init(
      objectNumber: OcaNetworkManagerONo,
      role: "Network Manager",
      deviceDelegate: deviceDelegate,
      addToRootBlock: true
    )
  }
}
