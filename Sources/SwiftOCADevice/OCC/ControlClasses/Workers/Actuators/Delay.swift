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

open class OcaDelay: OcaActuator {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.7") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  /// delay in seconds
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var delayTime = OcaBoundedPropertyValue<OcaTimeInterval>(value: 0, in: 0...1)
}

open class OcaDelayExtended: OcaDelay {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.7.1") }

  /// delay expressed in an arbitrary unit of measure; the inherited ``delayTime``
  /// property reflects the same delay in seconds
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("5.1"),
    getMethodID: OcaMethodID("5.1"),
    setMethodID: OcaMethodID("5.2")
  )
  public var delayValue = OcaBoundedPropertyValue<OcaDelayValue>(
    value: OcaDelayValue(delayValue: 0, delayUnit: .time),
    in: OcaDelayValue(delayValue: 0, delayUnit: .time)...OcaDelayValue(
      delayValue: 1,
      delayUnit: .time
    )
  )

  /// unit conversion is device specific; the default implementation is unimplemented
  open func getDelayValue(convertedTo unitOfMeasure: OcaDelayUnit) async throws
    -> OcaDelayValue
  {
    throw Ocp1Error.status(.notImplemented)
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("5.3"):
      let unitOfMeasure: OcaDelayUnit = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try await encodeResponse(getDelayValue(convertedTo: unitOfMeasure))
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
