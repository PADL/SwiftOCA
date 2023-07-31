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

import Foundation

open class OcaBasicActuator: OcaActuator {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1") }
}

open class OcaGenericBasicActuator<T: Codable & Comparable & Numeric>: OcaBasicActuator {
    @OcaBoundedProperty(
        propertyID: OcaPropertyID("5.1"),
        getMethodID: OcaMethodID("5.1"),
        setMethodID: OcaMethodID("5.2")
    )
    public var setting: OcaBoundedProperty<T>.State
}

open class OcaBooleanActuator: OcaBasicActuator {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1.1") }

    @OcaProperty(
        propertyID: OcaPropertyID("5.1"),
        getMethodID: OcaMethodID("5.1"),
        setMethodID: OcaMethodID("5.2")
    )
    public var setting: OcaProperty<OcaBoolean>.State
}

open class OcaInt8Actuator: OcaGenericBasicActuator<OcaInt8> {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1.2") }
}

open class OcaInt16Actuator: OcaGenericBasicActuator<OcaInt16> {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1.3") }
}

open class OcaInt32Actuator: OcaGenericBasicActuator<OcaInt32> {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1.4") }
}

open class OcaInt64Actuator: OcaGenericBasicActuator<OcaInt64> {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1.5") }
}

open class OcaUint8Actuator: OcaGenericBasicActuator<OcaUint8> {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1.6") }
}

open class OcaUint16Actuator: OcaGenericBasicActuator<OcaUint16> {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1.7") }
}

open class OcaUint32Actuator: OcaGenericBasicActuator<OcaUint32> {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1.8") }
}

open class OcaUint64Actuator: OcaGenericBasicActuator<OcaUint64> {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1.9") }
}

open class OcaFloat32Actuator: OcaGenericBasicActuator<OcaFloat32> {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1.10") }
}

open class OcaFloat64Actuator: OcaGenericBasicActuator<OcaFloat64> {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1.11") }
}

open class OcaStringActuator: OcaBasicActuator {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1.12") }
    @OcaProperty(
        propertyID: OcaPropertyID("5.1"),
        getMethodID: OcaMethodID("5.1"),
        setMethodID: OcaMethodID("5.2")
    )
    var setting: OcaProperty<String>.State
}

/*
 open struct OcaBitstring: Codable {
     // TODO
 }

 open class OcaBitstringActuator: OcaGenericBasicActuator<OcaBitstring> {
 open override class var classID: OcaClassID { OcaClassID("1.1.1.1.13") }
 }

 */
