//
// Copyright (c) 2026 PADL Software Pty Ltd
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

import SwiftOCA

/// Shared handling for SwiftOCADevice's classes that own an `OcaCounterSet` (OcaNetworkInterface,
/// OcaNetworkApplication, OcaCounterSetAgent); others subclass them. AES70-2:2024 §6.8 makes
/// the set a private property, raising no PropertyChanged; the class signals its notifiers in
/// `didSet`.
@OcaDevice
public protocol OcaCounterSetRepresentable: OcaRoot, OcaRegistrationObserving {
  /// The model's ID of the private property holding the counter set, which names the set
  /// when the device gives it no ID of its own.
  @_spi(SwiftOCAPrivate)
  static var counterSetPropertyID: OcaPropertyID { get }
  var counterSet: OcaCounterSet { get set }
  /// Every counter set the object holds: its own, and any others, such as an application's
  /// endpoints'. It may be read as the object registers, before a subclass's init ends, so an
  /// override must not depend on state assigned after super.init.
  var allCounterSets: [OcaCounterSet] { get }
  /// What the object has still to signal its notifiers; `OcaCounterSetChanges()` will do.
  @_spi(SwiftOCAPrivate)
  var counterSetChanges: OcaCounterSetChanges { get }
}

/// The changes to an object's counter sets its notifiers have not yet been signalled, with the
/// notifiers the sets named before them, so that a detached notifier hears of it.
@_spi(SwiftOCAPrivate) @OcaDevice
public final class OcaCounterSetChanges {
  fileprivate(set) var isPending = false
  fileprivate var isRegistered = false
  fileprivate var resets = Set<OcaCounterKey>()
  fileprivate var formerNotifiers = Set<OcaONo>()

  public nonisolated init() {}
}

public extension OcaCounterSetRepresentable {
  @OcaDevice
  func set(counter id: OcaID16, value: OcaUint64) throws {
    guard counterSet.set(counter: id, value: value) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
  }

  @OcaDevice
  func increment(counter id: OcaID16, by delta: OcaUint64 = 1) throws {
    guard counterSet.increment(counter: id, by: delta) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
  }
}

extension OcaCounterSetRepresentable {
  /// Signals the notifiers the object's counter sets name, and named before (`formerly`), that
  /// the sets changed. The changes of one turn are signalled together.
  func counterSetsDidChange(formerly former: some Sequence<OcaCounterSet> = [OcaCounterSet]()) {
    nameCounterSet()
    let changes = counterSetChanges
    for counterSet in former {
      for counter in counterSet.counter { changes.formerNotifiers.formUnion(counter.notifiers) }
    }
    guard !changes.isPending else { return }
    // most sets name no notifier, and need no task; one attaching names itself
    guard !namedNotifiers.isEmpty else {
      changes.resets = []
      return
    }
    changes.isPending = true
    Task { await signalNotifiers() }
  }

  /// The notifiers the counter sets name now, or named before the changes not yet signalled.
  private var namedNotifiers: Set<OcaONo> {
    counterSetChanges.formerNotifiers.union(allCounterSets.lazy.flatMap(\.counter).flatMap(\.notifiers))
  }

  private func signalNotifiers() async {
    // one hop to the device, after which the changes made meanwhile are signalled too
    let objects = await deviceDelegate?.objects ?? [:]
    let changes = counterSetChanges
    let named = namedNotifiers
    // an owner no longer registered holds no counters
    let counterSets = changes.isRegistered ? allCounterSets : []
    let resets = changes.resets
    changes.formerNotifiers = []
    changes.resets = []
    changes.isPending = false
    for case let notifier as OcaCounterNotifier in named.compactMap({ objects[$0] }) {
      notifier.counterSetsDidChange(for: self, counterSets: counterSets, resetting: resets)
    }
  }

  /// Resets the counter `id` of `counterSet`, one of the object's, or all of them, which
  /// notifiers report whatever their filters.
  func reset(_ counterSet: inout OcaCounterSet, counter id: OcaID16? = nil) throws {
    if let id, counterSet.counter(id: id) == nil { throw Ocp1Error.status(.parameterOutOfRange) }
    for counter in counterSet.counter where id == nil || counter.id == id {
      counterSetChanges.resets.insert(OcaCounterKey(counterSetID: counterSet.id, counterID: counter.id))
    }
    counterSet.reset(counter: id)
  }

  /// Refuses an object number other than a counter notifier's on the object's device, the only
  /// ones Attach takes, so that a controller cannot grow a counter's notifiers without bound.
  func ensureCounterNotifier(_ oNo: OcaONo) async throws {
    guard await deviceDelegate?.objects[oNo] is OcaCounterNotifier else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
  }

  /// Gives a counter set left without an ID, however it was set, one unique within the
  /// device, from the property that holds it. Encoding two fixed-width integers cannot fail.
  private func nameCounterSet() {
    guard counterSet.id.isEmpty,
          let id = try? OcaPropertyCounterSetID(ownerONo: objectNumber, propertyID: Self.counterSetPropertyID).blob,
          !id.isEmpty
    else { return }
    counterSet.id = id
  }

  /// For an owner's `didRegister`: names the counter set, and has notifiers it already names read it.
  func counterSetOwnerDidRegister() {
    counterSetChanges.isRegistered = true
    counterSetsDidChange()
  }

  /// For an owner's `didDeregister`: its notifiers find it gone, and forget its counters.
  func counterSetOwnerDidDeregister() {
    counterSetChanges.isRegistered = false
    counterSetsDidChange()
  }
}
