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

open class OcaDeviceTimeManager: OcaManager, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.3.10") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  public static let getDeviceTimeNTP = OcaMethodDescription<Void, OcaTimeNTP>(
    "3.1",
    name: "GetDeviceTimeNTP",
    resultNames: ["DeviceTime"]
  )

  public var deviceTimeNTP: OcaTimeNTP {
    get async throws { try await invoke(Self.getDeviceTimeNTP) }
  }

  public static let setDeviceTimeNTP = OcaMethodDescription<OcaTimeNTP, Void>(
    "3.2",
    name: "SetDeviceTimeNTP",
    parameterNames: ["DeviceTime"]
  )

  public func set(deviceTimeNTP time: OcaTimeNTP) async throws {
    try await invoke(Self.setDeviceTimeNTP, time)
  }

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
  public static let getCurrentDeviceTimeSource = OcaMethodDescription<Void, OcaONo>(
    "3.4",
    name: "GetCurrentDeviceTimeSource",
    resultNames: ["TimeSourceONo"]
  )
  public static let setCurrentDeviceTimeSource = OcaMethodDescription<OcaONo, Void>(
    "3.5",
    name: "SetCurrentDeviceTimeSource",
    parameterNames: ["TimeSourceONo"]
  )

  // the model names 3.6 and 3.7 GetDeviceTime and GetDeviceTimePTP both; the device says the first
  public static let getDeviceTime =
    OcaMethodDescription<Void, OcaTime>("3.6", name: "GetDeviceTime", resultNames: ["DeviceTime"])

  public var deviceTimePTP: OcaTime {
    get async throws { try await invoke(Self.getDeviceTime) }
  }

  public static let setDeviceTime = OcaMethodDescription<OcaTime, Void>(
    "3.7",
    name: "SetDeviceTime",
    parameterNames: ["DeviceTime"]
  )

  public func set(deviceTimePTP time: OcaTime) async throws {
    try await invoke(Self.setDeviceTime, time)
  }

  public convenience init() {
    self.init(objectNumber: OcaDeviceTimeManagerONo)
  }
}
