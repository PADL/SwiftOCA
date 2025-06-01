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

open class OcaMediaRecorderPlayer: OcaDatasetWorker, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.7.1") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.7")
  )
  public var state: OcaProperty<OcaMediaRecorderPlayerState>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.8"),
    setMethodID: OcaMethodID("4.9")
  )
  public var trackCount: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.10"),
    setMethodID: OcaMethodID("4.11")
  )
  public var trackFunctions: OcaProperty<[OcaMediaTrackFunction]>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.12"),
    setMethodID: OcaMethodID("4.13")
  )
  public var playOption: OcaProperty<OcaMediaPlayOption>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.5")
  )
  public var windowStart: OcaProperty<OcaMediaVolumePosition>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.6")
  )
  public var windowEnd: OcaProperty<OcaMediaVolumePosition>.PropertyValue

  // 4.1 Open
  // 4.2 Close
  // 4.3 Record
  // 4.4 Play
  // 4.5 Stop
  // 4.6 Reset
  // 4.14 GetPosition
  // 4.15 SetPosition
  // 4.16 GetWindowRange
  // 4.17 SetWindowRange
}
