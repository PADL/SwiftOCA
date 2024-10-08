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

public enum OcaPolarityState: OcaUint8, Codable, Sendable, CaseIterable {
  case nonInverted = 1
  case inverted = 2
}

open class OcaPolarity: OcaActuator, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.3") }

  @OcaProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var state: OcaProperty<OcaPolarityState>.PropertyValue
}
