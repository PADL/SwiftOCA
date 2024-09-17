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

  public var deviceTimeNTP: OcaTimeNTP {
    get async throws {
      try await sendCommandRrq(methodID: OcaMethodID("3.1"))
    }
  }

  public func set(deviceTimeNTP time: OcaTimeNTP) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.2"), parameters: time)
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.3")
  )
  public var timeSources: OcaListProperty<OcaONo>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.4"),
    setMethodID: OcaMethodID("3.5")
  )
  public var currentDeviceTimeSource: OcaProperty<OcaONo>.PropertyValue

  public var deviceTimePTP: OcaTime {
    get async throws {
      try await sendCommandRrq(methodID: OcaMethodID("3.6"))
    }
  }

  public func set(deviceTimePTP time: OcaTime) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.7"), parameters: time)
  }

  public convenience init() {
    self.init(objectNumber: OcaDeviceTimeManagerONo)
  }
}
