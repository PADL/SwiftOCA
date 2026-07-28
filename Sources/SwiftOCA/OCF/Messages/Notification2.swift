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

public enum Ocp1Notification2Type: OcaUint8, Equatable, Codable, Sendable {
  case event = 0
  case exception = 1
}

public enum Ocp1Notification2ExceptionType: OcaUint8, Equatable, Codable, Sendable {
  case unspecified = 0
  case cancelledByDevice = 1
  case objectDeleted = 2
  case deviceError = 3
}

public struct Ocp1Notification2ExceptionData: Equatable, Codable, Sendable, Error {
  let exceptionType: Ocp1Notification2ExceptionType
  let tryAgain: OcaBoolean
  let exceptionData: OcaBlob

  public init(
    exceptionType: Ocp1Notification2ExceptionType,
    tryAgain: OcaBoolean,
    exceptionData: OcaBlob
  ) {
    self.exceptionType = exceptionType
    self.tryAgain = tryAgain
    self.exceptionData = exceptionData
  }
}

public struct Ocp1Notification2: _Ocp1MessageCodable, Sendable {
  let notificationSize: OcaUint32
  let event: OcaEvent
  let notificationType: Ocp1Notification2Type
  let data: Data

  public var messageSize: OcaUint32 { notificationSize }

  public init(
    notificationSize: OcaUint32 = 0,
    event: OcaEvent,
    notificationType: Ocp1Notification2Type,
    data: Data
  ) {
    self.notificationSize = notificationSize
    self.event = event
    self.notificationType = notificationType
    self.data = data
  }

  func throwIfException() throws {
    guard notificationType == .exception else { return }
    let decoder = Ocp1Decoder()
    let exception = try decoder.decode(
      Ocp1Notification2ExceptionData.self,
      from: data
    )
    throw Ocp1Error.exception(exception)
  }

  init(parsing input: inout ParserSpan) throws {
    notificationSize = try OcaUint32(parsingBigEndian: &input)
    event = try OcaEvent(parsing: &input)
    notificationType = try Ocp1Notification2Type(parsing: &input)
    data = Data(parsingRemainingBytes: &input)
  }

  func encode(into bytes: inout [UInt8]) {
    withUnsafeBytes(of: notificationSize.bigEndian) { bytes += $0 }
    event.encode(into: &bytes)
    bytes.append(notificationType.rawValue)
    bytes.append(contentsOf: data)
  }
}
