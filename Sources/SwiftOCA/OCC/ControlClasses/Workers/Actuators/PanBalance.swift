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

public class OcaPanBalance: OcaActuator {
    public override class var classID: OcaClassID { OcaClassID("1.1.1.6") }

    @OcaBoundedProperty(propertyID: OcaPropertyID("4.1"),
                        getMethodID: OcaMethodID("4.1"),
                        setMethodID: OcaMethodID("4.2"))
    public var position: OcaBoundedProperty<OcaFloat32>.State


    @OcaBoundedProperty(propertyID: OcaPropertyID("4.2"),
                        getMethodID: OcaMethodID("4.3"),
                        setMethodID: OcaMethodID("4.4"))
    public var midpointGain: OcaBoundedProperty<OcaDB>.State
}
