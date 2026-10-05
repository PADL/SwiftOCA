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

@OcaMethods
open class OcaMediaClock3: OcaAgent, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.2.15") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    setMethodID: OcaMethodID("3.2")
  )
  public var availability: OcaProperty<OcaMediaClockAvailability>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.2")
  )
  public var timeSourceONo: OcaProperty<OcaONo>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.5"),
    setMethodID: OcaMethodID("3.6")
  )
  public var offset: OcaProperty<OcaTime>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.4")
  )
  public var currentRate: OcaProperty<OcaMediaClockRate>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.5"),
    getMethodID: OcaMethodID("3.7"),
    ocp2GetName: "Rates"
  )
  public var supportedRates: OcaMultiMapProperty<OcaONo, OcaMediaClockRate>.PropertyValue

  public struct GetCurrentRateParameters: OcaParametersReflectable {
    public let rate: OcaMediaClockRate
    public let timeSourceONo: OcaONo

    public init(rate: OcaMediaClockRate, timeSourceONo: OcaONo) {
      self.rate = rate
      self.timeSourceONo = timeSourceONo
    }
  }

  public typealias SetCurrentRateParameters = GetCurrentRateParameters

  @OcaMethod("3.3", name: "GetCurrentRate")
  public func getCurrentRate() async throws -> GetCurrentRateParameters

  @OcaMethod("3.4", name: "SetCurrentRate", parameters: SetCurrentRateParameters.self)
  public func setCurrentRate(rate: OcaMediaClockRate, timeSourceONo: OcaONo) async throws
}

public extension OcaMediaClock3 {
  /// Sets the rate and keeps the current time source, which is read first; the
  /// two commands are not atomic.
  func setCurrentRate(rate: OcaMediaClockRate) async throws {
    let timeSourceONo = try await getCurrentRate().timeSourceONo
    try await setCurrentRate(rate: rate, timeSourceONo: timeSourceONo)
  }
}
