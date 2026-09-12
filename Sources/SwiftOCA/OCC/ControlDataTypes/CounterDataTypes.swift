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

public struct OcaCounter: Codable, Sendable, Equatable {
  public var id: OcaID16
  public var value: OcaUint64
  public var initialValue: OcaUint64
  public var role: OcaString
  public var notifiers: OcaList<OcaONo>

  public init(
    id: OcaID16,
    value: OcaUint64,
    initialValue: OcaUint64,
    role: OcaString,
    notifiers: OcaList<OcaONo>
  ) {
    self.id = id
    self.value = value
    self.initialValue = initialValue
    self.role = role
    self.notifiers = notifiers
  }
}

public typealias OcaCounterSetID = OcaBlob

public struct OcaCounterSet: Codable, Sendable, Equatable {
  public var id: OcaCounterSetID
  public var counter: OcaList<OcaCounter>

  public init(id: OcaCounterSetID = OcaBlob(), counter: OcaList<OcaCounter> = []) {
    self.id = id
    self.counter = counter
  }
}

public struct OcaCounterUpdate: Codable, Sendable {
  public let counterSetID: OcaCounterSetID
  public let counterID: OcaID16
  public var value: OcaUint64

  public init(counterSetID: OcaCounterSetID, counterID: OcaID16, value: OcaUint64) {
    self.counterSetID = counterSetID
    self.counterID = counterID
    self.value = value
  }
}

public struct OcaCounterNotifierFilterParameters: Codable, Sendable {
  public let threshold: OcaUint64
  public let `operator`: OcaRelationalOperator
  public let period: OcaTimeInterval
  public let countDelta: OcaUint64

  public init(
    threshold: OcaUint64,
    operator: OcaRelationalOperator,
    period: OcaTimeInterval,
    countDelta: OcaUint64
  ) {
    self.threshold = threshold
    self.operator = `operator`
    self.period = period
    self.countDelta = countDelta
  }
}

public struct OcaCounterNotifierParameters: OcaParametersReflectable {
  public let id: OcaID16
  public let oNo: OcaONo

  public init(id: OcaID16, oNo: OcaONo) {
    self.id = id
    self.oNo = oNo
  }
}

public extension OcaCounterSet {
  func counter(id: OcaID16) -> OcaCounter? {
    counter.first { $0.id == id }
  }

  private func index(of id: OcaID16) -> Int? {
    counter.firstIndex { $0.id == id }
  }

  /// Sets a counter's value, returning false if no counter has that ID.
  @discardableResult
  mutating func set(counter id: OcaID16, value: OcaUint64) -> Bool {
    guard let index = index(of: id) else { return false }
    counter[index].value = value
    return true
  }

  @discardableResult
  mutating func increment(counter id: OcaID16, by delta: OcaUint64 = 1) -> Bool {
    guard let index = index(of: id) else { return false }
    counter[index].value &+= delta
    return true
  }

  mutating func reset(counter id: OcaID16? = nil) {
    for index in counter.indices where id == nil || counter[index].id == id {
      counter[index].value = counter[index].initialValue
    }
  }

  @discardableResult
  mutating func attach(notifier oNo: OcaONo, to id: OcaID16) -> Bool {
    guard let index = index(of: id) else { return false }
    if !counter[index].notifiers.contains(oNo) {
      counter[index].notifiers.append(oNo)
    }
    return true
  }

  @discardableResult
  mutating func detach(notifier oNo: OcaONo, from id: OcaID16) -> Bool {
    guard let index = index(of: id) else { return false }
    counter[index].notifiers.removeAll { $0 == oNo }
    return true
  }
}
