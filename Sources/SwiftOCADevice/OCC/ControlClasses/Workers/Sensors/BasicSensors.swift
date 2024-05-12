//
// Copyright (c) 2023 PADL Software Pty Ltd
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

open class OcaGenericBasicSensor<T: Codable & Comparable & Sendable>: OcaSensor {
  @OcaBoundedDeviceProperty
  public var reading: OcaBoundedPropertyValue<T>

  public init(
    _ initialReading: OcaBoundedPropertyValue<T>,
    objectNumber: OcaONo? = nil,
    lockable: OcaBoolean = true,
    role: OcaString = "Sensor",
    deviceDelegate: OcaDevice? = nil,
    addToRootBlock: Bool = true
  ) async throws {
    _reading = OcaBoundedDeviceProperty(
      wrappedValue: initialReading,
      propertyID: OcaPropertyID("5.1"),
      getMethodID: OcaMethodID("5.1")
    )
    try await super.init(
      objectNumber: objectNumber,
      lockable: lockable,
      role: role,
      deviceDelegate: deviceDelegate,
      addToRootBlock: addToRootBlock
    )
  }

  public required init(from decoder: Decoder) throws {
    throw Ocp1Error.notImplemented
  }
}

open class OcaBasicSensor: OcaSensor {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1") }
}

open class OcaBooleanSensor: OcaSensor {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.1") }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("5.1"),
    getMethodID: OcaMethodID("5.1")
  )
  public var reading = false

  public init(
    _ initialReading: Bool,
    objectNumber: OcaONo? = nil,
    lockable: OcaBoolean = true,
    role: OcaString = "Root",
    deviceDelegate: OcaDevice? = nil,
    addToRootBlock: Bool = true
  ) async throws {
    _reading = OcaDeviceProperty(
      wrappedValue: initialReading,
      propertyID: OcaPropertyID("5.1"),
      getMethodID: OcaMethodID("5.1")
    )
    try await super.init(
      objectNumber: objectNumber,
      lockable: lockable,
      role: role,
      deviceDelegate: deviceDelegate,
      addToRootBlock: addToRootBlock
    )
  }

  public required init(from decoder: Decoder) throws {
    throw Ocp1Error.notImplemented
  }
}

open class OcaInt8Sensor: OcaGenericBasicSensor<OcaInt8> {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.2") }
}

open class OcaInt16Sensor: OcaGenericBasicSensor<OcaInt16> {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.3") }
}

open class OcaInt32Sensor: OcaGenericBasicSensor<OcaInt32> {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.4") }
}

open class OcaInt64Sensor: OcaGenericBasicSensor<OcaInt64> {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.5") }
}

open class OcaUint8Sensor: OcaGenericBasicSensor<OcaUint8> {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.6") }
}

open class OcaUint16Sensor: OcaGenericBasicSensor<OcaUint16> {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.7") }
}

open class OcaUint32Sensor: OcaGenericBasicSensor<OcaUint32> {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.8") }
}

open class OcaUint64Sensor: OcaGenericBasicSensor<OcaUint64> {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.9") }
}

open class OcaFloat32Sensor: OcaGenericBasicSensor<OcaFloat32> {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.10") }
}

open class OcaFloat64Sensor: OcaGenericBasicSensor<OcaFloat64> {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.11") }
}

open class OcaStringSensor: OcaGenericBasicSensor<OcaString> {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.12") }
}
