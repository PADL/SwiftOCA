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

/// Shared handling for classes that own an `OcaCounterSet` device property
/// (OcaNetworkInterface, OcaNetworkApplication and their subclasses). Mutations go
/// through the property wrapper, which notifies subscribers.
@OcaDevice
public protocol OcaCounterSetRepresentable: OcaRoot {
  var counterSet: OcaCounterSet { get set }
}

public extension OcaCounterSetRepresentable {
  @OcaDevice
  func counter(id: OcaID16) throws -> OcaCounter {
    guard let counter = counterSet.counter(id: id) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return counter
  }

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

  @OcaDevice
  func attach(counterNotifier oNo: OcaONo, to id: OcaID16) throws {
    guard counterSet.attach(notifier: oNo, to: id) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
  }

  @OcaDevice
  func detach(counterNotifier oNo: OcaONo, from id: OcaID16) throws {
    guard counterSet.detach(notifier: oNo, from: id) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
  }

  /// Resets one counter, or all counters when `id` is zero.
  @OcaDevice
  func resetCounters(id: OcaID16 = 0) {
    counterSet.reset(counter: id == 0 ? nil : id)
  }
}
