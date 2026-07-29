//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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

import BinaryParsing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct Ocp1KeepAlive1: _Ocp1MessageCodable, Sendable {
  public let heartBeatTime: OcaUint16 // sec

  public var messageSize: OcaUint32 { 2 }

  public init(heartBeatTime: OcaUint16) {
    self.heartBeatTime = heartBeatTime
  }

  init(parsing input: inout ParserSpan) throws {
    try self.init(heartBeatTime: OcaUint16(parsingBigEndian: &input))
  }

  func encode(into bytes: inout [UInt8]) {
    withUnsafeBytes(of: heartBeatTime.bigEndian) { bytes += $0 }
  }
}

public struct Ocp1KeepAlive2: _Ocp1MessageCodable, Sendable {
  public let heartBeatTime: OcaUint32 // msec

  public var messageSize: OcaUint32 { 4 }

  public init(heartBeatTime: OcaUint32) {
    self.heartBeatTime = heartBeatTime
  }

  init(parsing input: inout ParserSpan) throws {
    try self.init(heartBeatTime: OcaUint32(parsingBigEndian: &input))
  }

  func encode(into bytes: inout [UInt8]) {
    withUnsafeBytes(of: heartBeatTime.bigEndian) { bytes += $0 }
  }
}

public typealias Ocp1KeepAlive = Ocp1KeepAlive1

extension Ocp1KeepAlive {
  /// Seconds if the interval is at least one, milliseconds otherwise: two
  /// distinct message types, so the choice can only be made at runtime.
  static func message(interval heartbeatTime: Duration) -> any _Ocp1MessageCodable {
    let seconds = heartbeatTime.seconds
    if seconds >= 1 {
      return Ocp1KeepAlive1(heartBeatTime: OcaUint16(seconds))
    } else {
      let milliseconds = heartbeatTime.milliseconds
      return Ocp1KeepAlive2(heartBeatTime: OcaUint32(max(milliseconds, 1)))
    }
  }
}

package extension Ocp1KeepAlive {
  /// `_Ocp1MessageCodable` is internal, so callers in other modules — which
  /// batch messages heterogeneously anyway — get the wider erasure.
  static func keepAlive(interval heartbeatTime: Duration) -> Ocp1Message {
    message(interval: heartbeatTime)
  }
}
