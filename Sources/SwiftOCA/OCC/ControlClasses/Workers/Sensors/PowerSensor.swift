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

open class OcaPowerSensor: OcaSensor, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.11") }
  override open class var classVersion: OcaClassVersionNumber { 1 }

  /// power in watts; retrieved together with ``powerFactor`` by ``getReading()``
  @OcaProperty(
    propertyID: OcaPropertyID("4.1")
  )
  public var power: OcaProperty<OcaFloat32>.PropertyValue

  /// ranges from one (a purely resistive circuit) to zero
  @OcaProperty(
    propertyID: OcaPropertyID("4.2")
  )
  public var powerFactor: OcaProperty<OcaFloat32>.PropertyValue

  @_spi(SwiftOCAPrivate)
  public struct GetReadingParameters: Ocp1ParametersReflectable {
    public let power: OcaFloat32
    public let powerFactor: OcaFloat32
    public let minPower: OcaFloat32
    public let maxPower: OcaFloat32

    public init(
      power: OcaFloat32,
      powerFactor: OcaFloat32,
      minPower: OcaFloat32,
      maxPower: OcaFloat32
    ) {
      self.power = power
      self.powerFactor = powerFactor
      self.minPower = minPower
      self.maxPower = maxPower
    }
  }

  public func getReading() async throws
    -> (power: OcaBoundedPropertyValue<OcaFloat32>, powerFactor: OcaFloat32)
  {
    let parameters: GetReadingParameters =
      try await sendCommandRrq(methodID: OcaMethodID("4.1"))
    return (
      OcaBoundedPropertyValue(
        value: parameters.power,
        in: parameters.minPower...parameters.maxPower
      ),
      parameters.powerFactor
    )
  }
}
