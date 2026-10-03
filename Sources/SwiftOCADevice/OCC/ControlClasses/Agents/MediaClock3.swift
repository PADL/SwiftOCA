//
// Copyright (c) 2023-2025 PADL Software Pty Ltd
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
open class OcaMediaClock3: OcaAgent {
  override open class var classID: OcaClassID { OcaClassID("1.2.15") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    setMethodID: OcaMethodID("3.2")
  )
  public var availability: OcaMediaClockAvailability = .unavailable

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.2")
  )
  public var timeSourceONo: OcaONo = OcaInvalidONo

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.5"),
    setMethodID: OcaMethodID("3.6")
  )
  public var offset: OcaTime = .init()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.4")
  )
  public var currentRate: OcaMediaClockRate = .init()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.5"),
    getMethodID: OcaMethodID("3.7"),
    ocp2GetName: "Rates"
  )
  public var supportedRates: OcaMultiMap<OcaONo, OcaMediaClockRate> = [:]

  open func set(currentRate: OcaMediaClockRate, timeSource: OcaTimeSource) async throws {
    self.currentRate = currentRate
    timeSourceONo = timeSource.objectNumber
  }

  @OcaDeviceMethod("3.3", name: "GetCurrentRate", access: .read)
  func getCurrentRate(from controller: any OcaController)
    -> SwiftOCA.OcaMediaClock3.GetCurrentRateParameters
  {
    .init(rate: currentRate, timeSourceONo: timeSourceONo)
  }

  @OcaDeviceMethod("3.4", name: "SetCurrentRate", access: .write)
  func setCurrentRate(
    _ parameters: SwiftOCA.OcaMediaClock3.SetCurrentRateParameters,
    from controller: any OcaController
  ) async throws {
    guard let deviceDelegate,
          let timeSource = await deviceDelegate
          .resolve(objectNumber: parameters.timeSourceONo) as? OcaTimeSource
    else {
      throw Ocp1Error.status(.badONo)
    }
    try await set(currentRate: parameters.rate, timeSource: timeSource)
  }
}
