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

open class OcaDelay: OcaActuator, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.7") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  /// delay in seconds
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var delayTime: OcaBoundedProperty<OcaTimeInterval>.PropertyValue
}

open class OcaDelayExtended: OcaDelay, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.7.1") }

  /// delay expressed in an arbitrary unit of measure; the inherited ``delayTime``
  /// property reflects the same delay in seconds
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("5.1"),
    getMethodID: OcaMethodID("5.1"),
    setMethodID: OcaMethodID("5.2")
  )
  public var delayValue: OcaBoundedProperty<OcaDelayValue>.PropertyValue

  public func getDelayValue(convertedTo unitOfMeasure: OcaDelayUnit) async throws
    -> OcaDelayValue
  {
    try await sendCommandRrq(
      methodID: OcaMethodID("5.3"),
      parameters: unitOfMeasure
    )
  }
}
