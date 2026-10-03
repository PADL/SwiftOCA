//
// Copyright (c) 2024 PADL Software Pty Ltd
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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@_spi(SwiftOCAPrivate)
import SwiftOCA

@OcaDeviceMethods
open class OcaCounterSetAgent: OcaAgent {
  override open class var classID: OcaClassID { OcaClassID("1.2.19") }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    setMethodID: OcaMethodID("3.2")
  )
  public var counterSet: OcaCounterSet?

  open func get(counter id: OcaID16) async throws -> OcaCounter {
    throw Ocp1Error.status(.notImplemented)
  }

  open func attach(counter id: OcaID16, to oNo: OcaONo) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func detach(counter id: OcaID16, from oNo: OcaONo) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func reset() async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func reset(counter id: OcaID16) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod("3.3", name: "GetCounter", access: .read, parameterNames: ["ID"], resultNames: ["OcaCounter"])
  func getCounter(_ id: OcaID16, from controller: any OcaController) async throws -> OcaCounter {
    try await get(counter: id)
  }

  @OcaDeviceMethod("3.4", name: "AttachCounterNotifier", access: .write)
  func attachCounterNotifier(
    _ parameters: SwiftOCA.OcaCounterSetAgent.CounterNotifierParameters,
    from controller: any OcaController
  ) async throws {
    try await attach(counter: parameters.id, to: parameters.oNo)
  }

  @OcaDeviceMethod("3.5", name: "DetachCounterNotifier", access: .write)
  func detachCounterNotifier(
    _ parameters: SwiftOCA.OcaCounterSetAgent.CounterNotifierParameters,
    from controller: any OcaController
  ) async throws {
    try await detach(counter: parameters.id, from: parameters.oNo)
  }

  @OcaDeviceMethod("3.6", name: "ResetCounterSet", access: .write)
  func resetCounterSet(from controller: any OcaController) async throws {
    try await reset()
  }

  @OcaDeviceMethod("3.7", name: "ResetCounter", access: .write, parameterNames: ["ID"])
  func resetCounter(_ id: OcaID16, from controller: any OcaController) async throws {
    try await reset(counter: id)
  }
}
