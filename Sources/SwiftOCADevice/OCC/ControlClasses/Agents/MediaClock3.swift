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
    getMethodID: OcaMethodID("3.7")
  )
  public var supportedRates: OcaMultiMap<OcaONo, OcaMediaClockRate> = [:]

  open func set(currentRate: OcaMediaClockRate, timeSource: OcaTimeSource) async throws {
    self.currentRate = currentRate
    timeSourceONo = timeSource.objectNumber
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.3"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      let params = SwiftOCA.OcaMediaClock3.GetCurrentRateParameters(
        rate: currentRate,
        timeSourceONo: timeSourceONo
      )
      return try encodeResponse(params)
    case OcaMethodID("3.4"):
      let params: SwiftOCA.OcaMediaClock3.SetCurrentRateParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      guard let deviceDelegate,
            let timeSource: OcaTimeSource = await deviceDelegate
            .resolve(objectNumber: params.timeSourceONo) as? OcaTimeSource
      else {
        throw Ocp1Error.status(.badONo)
      }
      try await set(currentRate: params.rate, timeSource: timeSource)
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
