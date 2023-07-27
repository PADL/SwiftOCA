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
import SwiftOCA

public class OcaGenericBasicActuator<T: Codable & Comparable & Numeric>: OcaActuator {
    @OcaBoundedDeviceProperty(
        wrappedValue: OcaBoundedPropertyValue<T>(value: 0, in: 0...1),
        propertyID: OcaPropertyID("5.1"),
        getMethodID: OcaMethodID("5.1"),
        setMethodID: OcaMethodID("5.2")
    )
    public var setting: OcaBoundedPropertyValue<T>
}

open class OcaBasicActuator: OcaActuator {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.1") }
}

open class OcaBooleanActuator: OcaActuator {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.1.1") }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("5.1"),
        getMethodID: OcaMethodID("5.1"),
        setMethodID: OcaMethodID("5.2")
    )
    public var setting = false
}

public class OcaInt8Actuator: OcaGenericBasicActuator<OcaInt8> {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.1.2") }
}

public class OcaInt16Actuator: OcaGenericBasicActuator<OcaInt16> {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.1.3") }
}

public class OcaInt32Actuator: OcaGenericBasicActuator<OcaInt32> {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.1.4") }
}

public class OcaInt64Actuator: OcaGenericBasicActuator<OcaInt64> {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.1.5") }
}

public class OcaUint8Actuator: OcaGenericBasicActuator<OcaUint8> {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.1.6") }
}

public class OcaUint16Actuator: OcaGenericBasicActuator<OcaUint16> {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.1.7") }
}

public class OcaUint32Actuator: OcaGenericBasicActuator<OcaUint32> {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.1.8") }
}

public class OcaUint64Actuator: OcaGenericBasicActuator<OcaUint64> {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.1.9") }
}

public class OcaFloat32Actuator: OcaGenericBasicActuator<OcaFloat32> {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.1.10") }
}

public class OcaFloat64Actuator: OcaGenericBasicActuator<OcaFloat64> {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.1.11") }
}

public class OcaStringActuator: OcaActuator {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.1.12") }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("5.1"),
        getMethodID: OcaMethodID("5.1"),
        setMethodID: OcaMethodID("5.2")
    )
    var setting = ""
}