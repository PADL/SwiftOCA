//
// Copyright (c) 2026 PADL Software Pty Ltd
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

open class OcaPowerSupply: OcaAgent {
  override open class var classID: OcaClassID { OcaClassID("1.2.7") }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var type: OcaPowerSupplyType = .none

  /// implementation-dependent model information
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.2")
  )
  public var modelInfo: OcaString = ""

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.3"),
    setMethodID: OcaMethodID("3.4")
  )
  public var state: OcaPowerSupplyState = .off

  /// whether a rechargeable supply is currently charging
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.4"),
    getMethodID: OcaMethodID("3.5")
  )
  public var charging: OcaBoolean = false

  /// fraction of the supply's load capacity that is currently unused, normally in the
  /// range zero to one; a negative value indicates the data is unavailable
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.5"),
    getMethodID: OcaMethodID("3.6")
  )
  public var loadFractionAvailable: OcaFloat32 = -1

  /// fraction of the supply's energy storage that remains available, normally in the
  /// range zero to one; a negative value indicates the data is unavailable
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.6"),
    getMethodID: OcaMethodID("3.7")
  )
  public var storageFractionAvailable: OcaFloat32 = -1

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.7"),
    getMethodID: OcaMethodID("3.8")
  )
  public var location: OcaPowerSupplyLocation = .unspecified
}
