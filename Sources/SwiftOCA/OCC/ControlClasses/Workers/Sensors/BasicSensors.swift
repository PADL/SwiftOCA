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

open class OcaBasicSensor: OcaSensor, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1") }
}

open class OcaGenericBasicSensor<T: Codable & Comparable & Sendable>: OcaBasicSensor,
  @unchecked Sendable
{
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("5.1"),
    getMethodID: OcaMethodID("5.1")
  )
  public var reading: OcaBoundedProperty<T>.PropertyValue
}

open class OcaBooleanSensor: OcaBasicSensor, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.1") }

  @OcaProperty(
    propertyID: OcaPropertyID("5.1"),
    getMethodID: OcaMethodID("5.1")
  )
  public var reading: OcaProperty<Bool>.PropertyValue
}

open class OcaInt8Sensor: OcaGenericBasicSensor<OcaInt8>, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.2") }
}

open class OcaInt16Sensor: OcaGenericBasicSensor<OcaInt16>, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.3") }
}

open class OcaInt32Sensor: OcaGenericBasicSensor<OcaInt32>, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.4") }
}

open class OcaInt64Sensor: OcaGenericBasicSensor<OcaInt64>, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.5") }
}

open class OcaUint8Sensor: OcaGenericBasicSensor<OcaUint8>, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.6") }
}

open class OcaUint16Sensor: OcaGenericBasicSensor<OcaUint16>, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.7") }
}

open class OcaUint32Sensor: OcaGenericBasicSensor<OcaUint32>, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.8") }
}

open class OcaUint64Sensor: OcaGenericBasicSensor<OcaUint64>, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.9") }
}

open class OcaFloat32Sensor: OcaGenericBasicSensor<OcaFloat32>, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.10") }
}

open class OcaFloat64Sensor: OcaGenericBasicSensor<OcaFloat64>, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.11") }
}

open class OcaStringSensor: OcaGenericBasicSensor<OcaString>, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.1.12") }
}
