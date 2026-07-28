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

open class OcaStateSensor: OcaSensor {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.12") }
  override open class var classVersion: OcaClassVersionNumber { 1 }

  /// the current state, named `State` by AES70 and renamed here to avoid colliding with
  /// the inherited reading state; states are numbered from the minimum to the maximum
  /// value of this property inclusive
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1")
  )
  public var reading = OcaBoundedPropertyValue<OcaUint16>(value: 0, in: 0...0)

  /// the first element corresponds to the minimum value of ``reading``
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.2"),
    setMethodID: OcaMethodID("4.3")
  )
  public var stateNames: OcaList<OcaString> = []
}
