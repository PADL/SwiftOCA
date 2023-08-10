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

open class OcaGain: OcaActuator {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.5") }

    @OcaBoundedDeviceProperty(
        propertyID: OcaPropertyID("4.1"),
        getMethodID: OcaMethodID("4.1"),
        setMethodID: OcaMethodID("4.2")
    )
    public var gain = OcaBoundedPropertyValue<OcaDB>(value: -144.0, in: -144.0...20.0)
}
