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

public class OcaPanBalance: OcaActuator {
    override public class var classID: OcaClassID { OcaClassID("1.1.1.6") }

    @OcaBoundedDeviceProperty(
        propertyID: OcaPropertyID("4.1"),
        getMethodID: OcaMethodID("4.1"),
        setMethodID: OcaMethodID("4.2")
    )
    public var position = OcaBoundedPropertyValue<OcaFloat32>(value: 0, in: -1.0...1.0)

    @OcaBoundedDeviceProperty(
        propertyID: OcaPropertyID("4.2"),
        getMethodID: OcaMethodID("4.3"),
        setMethodID: OcaMethodID("4.4")
    )
    public var midpointGain = OcaBoundedPropertyValue<OcaFloat32>(value: -3.0, in: -3.0 ... -3.0)
}
