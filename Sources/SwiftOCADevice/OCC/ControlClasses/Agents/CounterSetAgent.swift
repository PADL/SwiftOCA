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

/// A counter set on its own. Its counters reach their notifiers as those of a network
/// interface or application do, however the set is changed.
@OcaDeviceClass
open class OcaCounterSetAgent: OcaAgent, OcaCounterSetRepresentable {
  override open class var classID: OcaClassID { OcaClassID("1.2.19") }

  @_spi(SwiftOCAPrivate)
  public static var counterSetPropertyID: OcaPropertyID { OcaPropertyID("3.1") }

  /// A private property (AES70-2:2024 §6.8): it raises no PropertyChanged, and a controller
  /// reads and writes it with GetCounterSet and SetCounterSet.
  public var counterSet = OcaCounterSet() {
    didSet { counterSetsDidChange(formerly: [oldValue]) }
  }

  @_spi(SwiftOCAPrivate)
  public let counterSetChanges = OcaCounterSetChanges()

  open var allCounterSets: [OcaCounterSet] { [counterSet] }

  /// The most counters SetCounterSet takes.
  open class var maximumCounterCount: Int { 256 }

  open func didRegister() async {
    counterSetOwnerDidRegister()
  }

  open func didDeregister() async {
    counterSetOwnerDidDeregister()
  }

  @OcaDeviceMethod(SwiftOCA.OcaCounterSetAgent.Methods.getCounterSet)
  open func getCounterSet(from controller: any OcaController) async throws -> OcaCounterSet {
    counterSet
  }

  @OcaDeviceMethod(SwiftOCA.OcaCounterSetAgent.Methods.setCounterSet)
  open func setCounterSet(counterSet: OcaCounterSet, from controller: any OcaController) async throws {
    let ids = Set(counterSet.counter.map(\.id))
    guard counterSet.counter.count <= Self.maximumCounterCount, ids.count == counterSet.counter.count else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    for oNo in Set(counterSet.counter.flatMap(\.notifiers)) {
      try await ensureCounterNotifier(oNo)
    }
    // the set keeps the agent's ID, unique within the device, whatever the controller sends
    var counterSet = counterSet
    counterSet.id = self.counterSet.id
    self.counterSet = counterSet
  }

  @OcaDeviceMethod(SwiftOCA.OcaCounterSetAgent.Methods.getCounter)
  open func getCounter(id: OcaID16, from controller: any OcaController) async throws -> OcaCounter {
    try counterSet.existingCounter(id: id)
  }

  @OcaDeviceMethod(SwiftOCA.OcaCounterSetAgent.Methods.attachCounterNotifier)
  open func attachCounterNotifier(
    id: OcaID16,
    oNo: OcaONo,
    from controller: any OcaController
  ) async throws {
    try await ensureCounterNotifier(oNo)
    try counterSet.attach(notifier: oNo, to: id)
  }

  @OcaDeviceMethod(SwiftOCA.OcaCounterSetAgent.Methods.detachCounterNotifier)
  open func detachCounterNotifier(
    id: OcaID16,
    oNo: OcaONo,
    from controller: any OcaController
  ) async throws {
    try counterSet.detach(notifier: oNo, from: id)
  }

  @OcaDeviceMethod(SwiftOCA.OcaCounterSetAgent.Methods.resetCounterSet)
  open func resetCounterSet(from controller: any OcaController) async throws {
    try reset(&counterSet)
  }

  @OcaDeviceMethod(SwiftOCA.OcaCounterSetAgent.Methods.resetCounter)
  open func resetCounter(id: OcaID16, from controller: any OcaController) async throws {
    try reset(&counterSet, counter: id)
  }
}
