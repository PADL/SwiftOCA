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

open class OcaPowerManager: OcaManager {
  override open class var classID: OcaClassID { OcaClassID("1.3.5") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    setMethodID: OcaMethodID("3.2")
  )
  public var state: OcaProperty<OcaPowerState>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.3")
  )
  public var powerSupplies: OcaListProperty<OcaONo>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.4")
  )
  public var activePowerSupplies: OcaListProperty<OcaONo>.PropertyValue

  // 3.5 exchangePowerSupply(old, new, powerOffOld)
  public struct ExchangePowerSupplyParameters: Ocp1ParametersReflectable {
    public let oldPsu: OcaONo
    public let newPsu: OcaONo
    public let powerOffOld: OcaBoolean

    public init(oldPsu: OcaONo, newPsu: OcaONo, powerOffOld: OcaBoolean) {
      self.oldPsu = oldPsu
      self.newPsu = newPsu
      self.powerOffOld = powerOffOld
    }
  }

  public func exchangePowerSupply(
    oldPsu: OcaONo,
    newPsu: OcaONo,
    powerOffOld: OcaBoolean
  ) async throws {
    let parameters = ExchangePowerSupplyParameters(
      oldPsu: oldPsu,
      newPsu: newPsu,
      powerOffOld: powerOffOld
    )
    try await sendCommandRrq(methodID: OcaMethodID("3.5"), parameters: parameters)
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.4"),
    getMethodID: OcaMethodID("3.6")
  )
  public var autoState: OcaProperty<OcaBoolean>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.5")
  )
  public var targetState: OcaProperty<OcaPowerState>.PropertyValue

  public convenience init() {
    self.init(objectNumber: OcaPowerManagerONo)
  }
}
