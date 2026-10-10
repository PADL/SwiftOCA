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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@OcaClass
open class OcaCounterSetAgent: OcaAgent, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.2.19") }

  /// The counter set, a private property (AES70-2:2024 §6.8) read and written only through
  /// these methods.
  @OcaMethod("3.1", name: "GetCounterSet", resultNames: ["CounterSet"])
  public func getCounterSet() async throws -> OcaCounterSet

  @OcaMethod("3.2", name: "SetCounterSet", parameterNames: ["CounterSet"])
  public func setCounterSet(counterSet: OcaCounterSet) async throws

  @OcaMethod("3.3", name: "GetCounter", parameterNames: ["ID"], resultNames: ["OcaCounter"])
  public func getCounter(id: OcaID16) async throws -> OcaCounter

  public typealias CounterNotifierParameters = OcaCounterNotifierParameters

  @OcaMethod(
    "3.4",
    name: "AttachCounterNotifier",
    parameters: CounterNotifierParameters.self,
    parameterNames: ["ID", "ONo"]
  )
  public func attachCounterNotifier(id: OcaID16, oNo: OcaONo) async throws

  @OcaMethod(
    "3.5",
    name: "DetachCounterNotifier",
    parameters: CounterNotifierParameters.self,
    parameterNames: ["ID", "ONo"]
  )
  public func detachCounterNotifier(id: OcaID16, oNo: OcaONo) async throws

  @OcaMethod("3.6", name: "ResetCounterSet")
  public func resetCounterSet() async throws

  @OcaMethod("3.7", name: "ResetCounter", parameterNames: ["ID"])
  public func resetCounter(id: OcaID16) async throws
}
