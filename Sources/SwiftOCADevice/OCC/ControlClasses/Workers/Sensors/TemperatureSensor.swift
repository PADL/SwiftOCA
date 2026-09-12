//
// Copyright (c) 2025 PADL Software Pty Ltd
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

open class OcaTemperatureSensor: OcaSensor {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.5") }

  /// bounded below by absolute zero; a subclass narrows the range it can report
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1")
  )
  public var reading = OcaBoundedPropertyValue<OcaTemperature>(value: 0.0, in: -273.15...1000.0)
}
