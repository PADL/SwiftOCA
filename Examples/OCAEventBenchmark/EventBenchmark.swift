//
// Copyright (c) 2025 PADL Software Pty Ltd
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

import Foundation
import SwiftOCA

let Rounds = 1_000_000

enum Failure: Error {
  case ntf1((Ocp1Notification1, Ocp1Notification1))
  case data((Data, Data))
}

extension Ocp1EventData: Equatable {
  public static func == (_ lhs: Ocp1EventData, _ rhs: Ocp1EventData) -> Bool {
    lhs.event == rhs.event && lhs.eventParameters == rhs.eventParameters
  }
}

extension Ocp1NtfParams: Equatable {
  public static func == (_ lhs: Ocp1NtfParams, _ rhs: Ocp1NtfParams) -> Bool {
    lhs.parameterCount == rhs.parameterCount && lhs.context == rhs.context && lhs.eventData == rhs
      .eventData
  }
}

extension Ocp1Notification1: Equatable {
  public static func == (_ lhs: Ocp1Notification1, _ rhs: Ocp1Notification1) -> Bool {
    lhs.notificationSize == rhs.notificationSize && lhs.targetONo == rhs.targetONo && lhs
      .methodID == rhs.methodID && lhs.parameters == rhs.parameters
  }
}

func encodeNotificationWithCodable(_ notification: Ocp1Notification1) throws -> Data {
  let encoder = Ocp1Encoder()
  return try encoder.encode(notification)
}

func decodeNotificationWithCodable(_ data: Data) throws -> Ocp1Notification1 {
  let decoder = Ocp1Decoder()
  return try decoder.decode(Ocp1Notification1.self, from: data)
}

func encodeNotificationWithBuiltin(_ notification: Ocp1Notification1) throws -> Data {
  var bytes = [UInt8]()
  bytes.reserveCapacity(32)
  notification.encode(into: &bytes)
  return Data(bytes)
}

func decodeNotificationWithBuiltin(_ data: Data) throws -> Ocp1Notification1 {
  try Ocp1Notification1(bytes: Array(data))
}

func benchmark(tag: String, _ block: () throws -> ()) rethrows {
  let start = ContinuousClock.now
  for _ in 0..<Rounds {
    try block()
  }
  let end = ContinuousClock.now
  print("\(Rounds) rounds of \(tag) took \(end - start)")
}

private let EncodedNotification = Data([
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x56, 0x78, 0x00, 0x01, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00,
  0x00, 0x12, 0x34, 0x00, 0x01, 0x00, 0x01, 0x00, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x01,
])

@main
public enum EventBenchmark {
  public static func main() throws {
    let eventParameters = Data([0x00, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x01])
    let eventData = Ocp1EventData(
      event: OcaEvent(emitterONo: 0x1234, eventID: OcaEventID(defLevel: 1, eventIndex: 1)),
      eventParameters: eventParameters
    )
    let params = Ocp1NtfParams(parameterCount: 1, context: OcaBlob(), eventData: eventData)
    let aNotification = Ocp1Notification1(
      notificationSize: 0,
      targetONo: 0x5678,
      methodID: "1.1",
      parameters: params
    )

    try benchmark(tag: "encodeNotificationWithCodable") {
      let d = try encodeNotificationWithCodable(aNotification)
      guard d == EncodedNotification else { throw Failure.data((d, EncodedNotification)) }
    }

    try benchmark(tag: "decodeNotificationWithCodable") {
      let n = try decodeNotificationWithCodable(EncodedNotification)
      guard n == aNotification else { throw Failure.ntf1((n, aNotification)) }
    }

    try benchmark(tag: "encodeNotificationWithBuiltin") {
      let d = try encodeNotificationWithBuiltin(aNotification)
      guard d == EncodedNotification else { throw Failure.data((d, EncodedNotification)) }
    }

    try benchmark(tag: "decodeNotificationWithBuiltin") {
      let n = try decodeNotificationWithBuiltin(EncodedNotification)
      guard n == aNotification else { throw Failure.ntf1((n, aNotification)) }
    }
  }
}
