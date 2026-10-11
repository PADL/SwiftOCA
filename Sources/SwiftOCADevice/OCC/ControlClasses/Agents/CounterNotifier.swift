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

import SwiftOCA

/// Emits CounterUpdate for the counters attached to it. An update is sent each time a
/// counter moves CountDelta from the value last notified, and every Period seconds, while
/// it meets any Threshold; a reset by a Reset method is notified whatever the filters.
@OcaDeviceClass
open class OcaCounterNotifier: OcaAgent, OcaRegistrationObserving {
  override open class var classID: OcaClassID { OcaClassID("1.2.18") }

  override open class var deviceEvents: [OcaDeviceEventDescriptor] {
    super.deviceEvents + [OcaDeviceEventDescriptor(
      eventID: SwiftOCA.OcaCounterNotifier.counterUpdateEventID,
      name: "CounterUpdate",
      eventDataType: OcaCounterUpdateEventData.self
    )]
  }

  /// The shortest nonzero Period accepted, which a device may change: a shorter one would
  /// flood subscribers. Zero means no periodic updates.
  open class var minimumPeriod: OcaTimeInterval { 0.1 }

  /// The nonzero Periods accepted; a longer one is no period at all and would overflow the timer.
  public final class var periodRange: ClosedRange<OcaTimeInterval> { minimumPeriod...1e9 }

  /// `period` brought into `periodRange`; zero, or nothing a timer could keep, is no period.
  private static func period(inRange period: OcaTimeInterval) -> OcaTimeInterval {
    guard period.isFinite, period > 0 else { return 0 }
    return min(max(period, periodRange.lowerBound), periodRange.upperBound)
  }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.2"),
    setMethodID: OcaMethodID("3.3"),
    ocp2GetName: "Parameters",
    ocp2SetName: "Parameters"
  )
  /// All zero until set, which leaves only resets to notify.
  public var filterParameters =
    OcaCounterNotifierFilterParameters(threshold: 0, operator: .none, period: 0, countDelta: 0)

  struct Observed {
    var value: OcaUint64
    /// the value last notified, or the value when the notifier first saw the counter
    var lastNotifiedValue: OcaUint64
  }

  // internal for the tests, which read them through a @testable seam
  /// The attached counters, by the object number of the owner holding them.
  private(set) var observed = [OcaONo: [OcaCounterKey: Observed]]()
  private var lastUpdate = [OcaCounterUpdate]()
  /// A counter's updates waiting to be sent: a reset, then the newest value since it, at most.
  struct Pending {
    var reset: OcaUint64?
    var value: OcaUint64?
  }

  /// The counters with updates waiting, in the order they were first queued.
  private(set) var pending = [OcaCounterKey: Pending]()
  private var pendingOrder = [OcaCounterKey]()
  private(set) var sending: Task<(), Never>?
  private(set) var periodTimer: Task<(), Never>?
  private var periodTracker: Task<(), Never>?
  private var isRegistered = false

  @OcaDeviceMethod(SwiftOCA.OcaCounterNotifier.Methods.getLastUpdate)
  open func getLastUpdate(from controller: any OcaController) async throws -> OcaList<OcaCounterUpdate> {
    lastUpdate
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case _filterParameters.setMethodID:
      // after the access checks, refuse a Period the timer cannot keep
      try await ensureWritable(by: controller, command: command)
      let parameters: OcaCounterNotifierFilterParameters = try Self.decodeCommand(command)
      if parameters.period != 0, !Self.periodRange.contains(parameters.period) {
        throw Ocp1Error.status(.parameterOutOfRange)
      }
      try await _filterParameters.set(object: self, command: command)
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }

  /// Once registered, schedules periodic updates and reads the counter sets that already name it.
  public func didRegister() async {
    isRegistered = true
    schedulePeriodicUpdates()
    let objects = await deviceDelegate?.objects ?? [:]
    guard isRegistered else { return } // deregistered while fetching them
    for case let owner as any OcaCounterSetRepresentable in objects.values {
      read(owner.allCounterSets, for: owner, resets: [])
    }
  }

  /// Deregistered, the notifier holds no counters and sends nothing until registered again.
  public func didDeregister() {
    isRegistered = false
    cancelPeriodicUpdates()
    observed = [:]
    pending = [:]
    pendingOrder = []
  }

  deinit {
    periodTracker?.cancel()
    periodTimer?.cancel()
  }

  /// Reads `counterSets`, all those `owner` holds now, `resets` by a Reset method; its owner
  /// signals it when they change.
  func counterSetsDidChange(
    for owner: any OcaCounterSetRepresentable,
    counterSets: [OcaCounterSet],
    resetting resets: Set<OcaCounterKey>
  ) {
    // a reset signalled while the notifier is still registering is not notified
    guard isRegistered else { return }
    read(counterSets, for: owner, resets: resets)
  }

  /// Brings what the notifier knows of `owner`'s counters up to `counterSets`, all the sets
  /// the owner holds now, and sends the updates that calls for.
  private func read(_ counterSets: [OcaCounterSet], for owner: OcaRoot, resets: Set<OcaCounterKey>) {
    var current = [OcaCounterKey: Observed]()
    for (key, value) in attachedCounters(in: counterSets) {
      let isReset = resets.contains(key)
      guard var counter = observed[owner.objectNumber]?[key] else {
        current[key] = Observed(value: value, lastNotifiedValue: value)
        if isReset { enqueue(key, value, isReset: true) }
        continue
      }
      if isReset || counter.value != value {
        counter.value = value
        if isReset || reachedCountDelta(counter) {
          counter.lastNotifiedValue = value
          enqueue(key, value, isReset: isReset)
        }
      }
      current[key] = counter
    }
    observed[owner.objectNumber] = current.isEmpty ? nil : current
    startSending()
  }

  private func attachedCounters(in counterSets: [OcaCounterSet]) -> [(key: OcaCounterKey, value: OcaUint64)] {
    counterSets.flatMap { counterSet in
      counterSet.counter.filter { $0.notifiers.contains(objectNumber) }.map {
        (OcaCounterKey(counterSetID: counterSet.id, counterID: $0.id), $0.value)
      }
    }
  }

  // AES70-2: a CountDelta of zero means no every-n updates.
  private func reachedCountDelta(_ counter: Observed) -> Bool {
    guard filterParameters.countDelta > 0, filterParameters.meetsThreshold(counter.value) else { return false }
    return max(counter.value, counter.lastNotifiedValue) - min(counter.value, counter.lastNotifiedValue)
      >= filterParameters.countDelta
  }

  /// Restarts the periodic updates whenever Period changes, however FilterParameters is
  /// set, until the notifier is deregistered or goes. A Period set past the command path's
  /// check, as a dataset restores one, is brought into range, which comes round as a change.
  private func schedulePeriodicUpdates() {
    cancelPeriodicUpdates()
    let filterParameters = $filterParameters
    periodTracker = Task { [weak self] in
      var period: OcaTimeInterval?
      do {
        for try await _ in filterParameters {
          guard !Task.isCancelled, let self else { return }
          let parameters = self.filterParameters // the current value, not the one buffered
          let inRange = Self.period(inRange: parameters.period)
          guard parameters.period == inRange else {
            self.filterParameters = OcaCounterNotifierFilterParameters(
              threshold: parameters.threshold,
              operator: parameters.operator,
              period: inRange,
              countDelta: parameters.countDelta
            )
            continue
          }
          guard parameters.period != period else { continue }
          period = parameters.period
          periodTimer?.cancel()
          periodTimer = periodicUpdates(every: parameters.period)
        }
      } catch {}
    }
  }

  private func cancelPeriodicUpdates() {
    periodTracker?.cancel()
    periodTracker = nil
    periodTimer?.cancel()
    periodTimer = nil
  }

  // Period asks for updates on a clock whatever the counters do, so it needs a timer.
  private func periodicUpdates(every period: OcaTimeInterval) -> Task<(), Never>? {
    guard Self.periodRange.contains(period) else { return nil }
    return Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(Double(period)))
        guard !Task.isCancelled, let self else { return }
        self.sendPeriodicUpdate()
      }
    }
  }

  /// Sends every counter that meets the Threshold, by owner and counter, so ticks are alike.
  func sendPeriodicUpdate() {
    for (owner, counters) in observed.sorted(by: { $0.key < $1.key }) {
      for (key, counter) in counters.sorted(by: { $0.key < $1.key })
        where filterParameters.meetsThreshold(counter.value)
      {
        observed[owner]?[key]?.lastNotifiedValue = counter.value
        enqueue(key, counter.value, isReset: false)
      }
    }
    startSending()
  }

  // Updates go out one event at a time, in order. Those raised while one is sent wait, a reset
  // and the newest value per counter, so a slow controller delays them without a growing queue.
  private func enqueue(_ key: OcaCounterKey, _ value: OcaUint64, isReset: Bool) {
    if pending[key] == nil { pendingOrder.append(key) }
    if isReset {
      pending[key] = Pending(reset: value) // supersedes whatever waited, a reset before it included
    } else {
      pending[key, default: Pending()].value = value
    }
  }

  private func startSending() {
    guard sending == nil, !pendingOrder.isEmpty else { return }
    sending = Task { [weak self] in await self?.sendPendingUpdates() }
  }

  private func sendPendingUpdates() async {
    let event = OcaEvent(emitterONo: objectNumber, eventID: SwiftOCA.OcaCounterNotifier.counterUpdateEventID)
    while !pendingOrder.isEmpty {
      // an event names each counter once; a value after a reset goes in the next
      var updates = [OcaCounterUpdate]()
      var waiting = [OcaCounterKey]()
      for key in pendingOrder {
        guard var counter = pending[key] else { continue }
        let value = counter.reset ?? counter.value
        if counter.reset != nil { counter.reset = nil } else { counter.value = nil }
        if let value {
          updates.append(OcaCounterUpdate(counterSetID: key.counterSetID, counterID: key.counterID, value: value))
        }
        if counter.value != nil {
          pending[key] = counter
          waiting.append(key)
        } else {
          pending[key] = nil
        }
      }
      pendingOrder = waiting
      do {
        try await deviceDelegate?.notifySubscribers(event, eventData: OcaCounterUpdateEventData(updates: updates))
        lastUpdate = updates
      } catch {}
    }
    sending = nil
  }
}

/// A counter, by the counter set that holds it.
struct OcaCounterKey: Hashable, Sendable, Comparable {
  let counterSetID: OcaCounterSetID
  let counterID: OcaID16

  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.counterSetID == rhs.counterSetID
      ? lhs.counterID < rhs.counterID
      : lhs.counterSetID.lexicographicallyPrecedes(rhs.counterSetID)
  }
}
