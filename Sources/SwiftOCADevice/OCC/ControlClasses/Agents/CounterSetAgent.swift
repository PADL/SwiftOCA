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

  @OcaDeviceMethod(SwiftOCA.OcaCounterSetAgent.Methods.getCounter)
  open func getCounter(id: OcaID16, from controller: any OcaController) async throws -> OcaCounter {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaCounterSetAgent.Methods.attachCounterNotifier)
  open func attachCounterNotifier(
    id: OcaID16,
    oNo: OcaONo,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaCounterSetAgent.Methods.detachCounterNotifier)
  open func detachCounterNotifier(
    id: OcaID16,
    oNo: OcaONo,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaCounterSetAgent.Methods.resetCounterSet)
  open func resetCounterSet(from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaCounterSetAgent.Methods.resetCounter)
  open func resetCounter(id: OcaID16, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }
}
