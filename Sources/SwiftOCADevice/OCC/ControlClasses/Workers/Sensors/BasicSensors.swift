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

public class OcaGenericBasicSensor<T: Codable>: OcaSensor {
    @OcaDeviceProperty
    public var reading: T

    public init(
        _ initialReading: T,
        objectNumber: OcaONo? = nil,
        lockable: OcaBoolean = false,
        role: OcaString = "Root",
        deviceDelegate: AES70OCP1Device? = nil
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
            deviceDelegate: deviceDelegate
        )
    }
}

public class OcaBasicSensor: OcaSensor {
    override public class var classID: OcaClassID { OcaClassID("1.1.2.1") }
}

public class OcaBooleanSensor: OcaGenericBasicSensor<OcaBoolean> {
    override public class var classID: OcaClassID { OcaClassID("1.1.2.1.1") }
}

public class OcaInt8Sensor: OcaGenericBasicSensor<OcaInt8> {
    override public class var classID: OcaClassID { OcaClassID("1.1.2.1.2") }
}

public class OcaInt16Sensor: OcaGenericBasicSensor<OcaInt16> {
    override public class var classID: OcaClassID { OcaClassID("1.1.2.1.3") }
}

public class OcaInt32Sensor: OcaGenericBasicSensor<OcaInt32> {
    override public class var classID: OcaClassID { OcaClassID("1.1.2.1.4") }
}

public class OcaInt64Sensor: OcaGenericBasicSensor<OcaInt64> {
    override public class var classID: OcaClassID { OcaClassID("1.1.2.1.5") }
}

public class OcaUint8Sensor: OcaGenericBasicSensor<OcaUint8> {
    override public class var classID: OcaClassID { OcaClassID("1.1.2.1.6") }
}

public class OcaUint16Sensor: OcaGenericBasicSensor<OcaUint16> {
    override public class var classID: OcaClassID { OcaClassID("1.1.2.1.7") }
}

public class OcaUint32Sensor: OcaGenericBasicSensor<OcaUint32> {
    override public class var classID: OcaClassID { OcaClassID("1.1.2.1.8") }
}

public class OcaUint64Sensor: OcaGenericBasicSensor<OcaUint64> {
    override public class var classID: OcaClassID { OcaClassID("1.1.2.1.9") }
}

public class OcaFloat32Sensor: OcaGenericBasicSensor<OcaFloat32> {
    override public class var classID: OcaClassID { OcaClassID("1.1.2.1.10") }
}

public class OcaFloat64Sensor: OcaGenericBasicSensor<OcaFloat64> {
    override public class var classID: OcaClassID { OcaClassID("1.1.2.1.11") }
}

public class OcaStringSensor: OcaGenericBasicSensor<OcaString> {
    override public class var classID: OcaClassID { OcaClassID("1.1.2.1.12") }
}
