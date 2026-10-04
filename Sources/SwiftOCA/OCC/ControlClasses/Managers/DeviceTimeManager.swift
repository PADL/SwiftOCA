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

@OcaMethods
open class OcaDeviceTimeManager: OcaManager, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.3.10") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaMethod("3.1", name: "GetDeviceTimeNTP", resultNames: ["DeviceTime"])
  public func getDeviceTimeNTP() async throws -> OcaTimeNTP

  @OcaMethod("3.2", name: "SetDeviceTimeNTP", parameterNames: ["DeviceTime"])
  public func setDeviceTimeNTP(deviceTime: OcaTimeNTP) async throws

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.3"),
    ocp2GetName: "TimeSourceONos"
  )
  public var timeSources: OcaListProperty<OcaONo>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.4"),
    setMethodID: OcaMethodID("3.5"),
    ocp2GetName: "TimeSourceONo",
    ocp2SetName: "TimeSourceONo"
  )
  public var currentDeviceTimeSource: OcaProperty<OcaONo>.PropertyValue

  // the property's accessors, as the device declares them
  @OcaMethod("3.4", name: "GetCurrentDeviceTimeSource", resultNames: ["TimeSourceONo"])
  public func getCurrentDeviceTimeSource() async throws -> OcaONo

  @OcaMethod("3.5", name: "SetCurrentDeviceTimeSource", parameterNames: ["TimeSourceONo"])
  public func setCurrentDeviceTimeSource(timeSourceONo: OcaONo) async throws

  // the model names 3.6 and 3.7 GetDeviceTime and GetDeviceTimePTP both; the device says the first
  @OcaMethod("3.6", name: "GetDeviceTime", resultNames: ["DeviceTime"])
  public func getDeviceTime() async throws -> OcaTime

  @OcaMethod("3.7", name: "SetDeviceTime", parameterNames: ["DeviceTime"])
  public func setDeviceTime(deviceTime: OcaTime) async throws

  public convenience init() {
    self.init(objectNumber: OcaDeviceTimeManagerONo)
  }
}
