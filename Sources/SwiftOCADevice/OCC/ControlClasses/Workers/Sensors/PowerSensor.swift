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

@_spi(SwiftOCAPrivate)
import SwiftOCA

@OcaDeviceMethods
open class OcaPowerSensor: OcaSensor {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.11") }
  override open class var classVersion: OcaClassVersionNumber { 1 }

  /// power in watts; there is no property accessor because AES70 returns this together
  /// with ``powerFactor`` from GetReading()
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.1")
  )
  public var power = OcaBoundedPropertyValue<OcaFloat32>(
    value: 0,
    in: 0...OcaFloat32.greatestFiniteMagnitude
  )

  /// ranges from one (a purely resistive circuit) to zero
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.2")
  )
  public var powerFactor: OcaFloat32 = 1

  @OcaDeviceMethod(SwiftOCA.OcaPowerSensor.getReading, access: .read)
  func getReading(from controller: any OcaController) -> SwiftOCA.OcaPowerSensor.GetReadingParameters {
    .init(
      power: power.value,
      powerFactor: powerFactor,
      minPower: power.minValue,
      maxPower: power.maxValue
    )
  }
}
