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
    getMethodID: OcaMethodID("3.7")
  )
  public var supportedRates: OcaMultiMapProperty<OcaONo, OcaMediaClockRate>.PropertyValue

  @_spi(SwiftOCAPrivate)
  public struct GetCurrentRateParameters: Ocp1ParametersReflectable {
    public let rate: OcaMediaClockRate
    public let timeSourceONo: OcaONo

    public init(rate: OcaMediaClockRate, timeSourceONo: OcaONo) {
      self.rate = rate
      self.timeSourceONo = timeSourceONo
    }
  }

  @_spi(SwiftOCAPrivate) public typealias SetCurrentRateParameters = GetCurrentRateParameters

  public func getCurrentRate() async throws -> (OcaMediaClockRate, OcaONo) {
    let parameters: GetCurrentRateParameters =
      try await sendCommandRrq(methodID: OcaMethodID("3.3"))
    return (parameters.rate, parameters.timeSourceONo)
  }

  public func set(currentRate: OcaMediaClockRate, timeSourceONo: OcaONo? = nil) async throws {
    let _timeSourceONo: OcaONo
    if let timeSourceONo {
      _timeSourceONo = timeSourceONo
    } else {
      (_, _timeSourceONo) = try await getCurrentRate()
    }
    let parameters = SetCurrentRateParameters(rate: currentRate, timeSourceONo: _timeSourceONo)
    try await sendCommandRrq(methodID: OcaMethodID("3.4"), parameters: parameters)
  }
}
