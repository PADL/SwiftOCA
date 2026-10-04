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

open class OcaCounterSetAgent: OcaAgent, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.2.19") }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    setMethodID: OcaMethodID("3.2")
  )
  public var counterSet: OcaProperty<OcaCounterSet>.PropertyValue

  public static let getCounter = OcaMethodDescription<OcaID16, OcaCounter>(
    "3.3",
    name: "GetCounter",
    parameterNames: ["ID"],
    resultNames: ["OcaCounter"]
  )

  public func get(counter id: OcaID16) async throws -> OcaCounter {
    try await invoke(Self.getCounter, id)
  }

  public typealias CounterNotifierParameters = OcaCounterNotifierParameters

  public static let attachCounterNotifier = OcaMethodDescription<CounterNotifierParameters, Void>(
    "3.4",
    name: "AttachCounterNotifier",
    parameterNames: ["ID", "ONo"]
  )

  public func attach(counter id: OcaID16, to oNo: OcaONo) async throws {
    try await invoke(Self.attachCounterNotifier, .init(id: id, oNo: oNo))
  }

  public static let detachCounterNotifier = OcaMethodDescription<CounterNotifierParameters, Void>(
    "3.5",
    name: "DetachCounterNotifier",
    parameterNames: ["ID", "ONo"]
  )

  public func detach(counter id: OcaID16, from oNo: OcaONo) async throws {
    try await invoke(Self.detachCounterNotifier, .init(id: id, oNo: oNo))
  }

  public static let resetCounterSet = OcaMethodDescription<Void, Void>("3.6", name: "ResetCounterSet")

  public func reset() async throws {
    try await invoke(Self.resetCounterSet)
  }

  public static let resetCounter =
    OcaMethodDescription<OcaID16, Void>("3.7", name: "ResetCounter", parameterNames: ["ID"])

  public func reset(counter id: OcaID16) async throws {
    try await invoke(Self.resetCounter, id)
  }
}
