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
  /// Event data (`.event`) or an OCP.1-encoded `Ocp1Notification2ExceptionData`
  /// (`.exception`). Event data is in `dataFormat`.
  let data: Data
  /// The marshaling of `data` for an `.event` notification. Exception data is always
  /// OCP.1-encoded, whatever the framing, so `throwIfException` works for both.
  package let dataFormat: OcaParameterFormat

  public var messageSize: OcaUint32 { notificationSize }

  public init(
    notificationSize: OcaUint32 = 0,
    event: OcaEvent,
    notificationType: Ocp1Notification2Type,
    data: Data
  ) {
    self.init(
      notificationSize: notificationSize,
      event: event,
      notificationType: notificationType,
      data: data,
      dataFormat: .ocp1
    )
  }

  package init(
    notificationSize: OcaUint32 = 0,
    event: OcaEvent,
    notificationType: Ocp1Notification2Type,
    data: Data,
    dataFormat: OcaParameterFormat
  ) {
    self.notificationSize = notificationSize
    self.event = event
    self.notificationType = notificationType
    self.data = data
    self.dataFormat = dataFormat
  }

  enum CodingKeys: CodingKey {
    case notificationSize
    case event
    case notificationType
    case data
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      notificationSize: try container.decode(OcaUint32.self, forKey: .notificationSize),
      event: try container.decode(OcaEvent.self, forKey: .event),
      notificationType: try container.decode(Ocp1Notification2Type.self, forKey: .notificationType),
      data: try container.decode(Data.self, forKey: .data)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(notificationSize, forKey: .notificationSize)
    try container.encode(event, forKey: .event)
    try container.encode(notificationType, forKey: .notificationType)
    try container.encode(data, forKey: .data)
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
    // notificationSize(4) + event(8) + notificationType(1) fixed bytes plus at
    // least one byte of `data`; reject a truncated notification rather than
    // surfacing it as a valid empty-payload event.
    guard input.count >= 14 else {
      throw Ocp1Error.pduTooShort
    }
    notificationSize = try OcaUint32(parsingBigEndian: &input)
    event = try OcaEvent(parsing: &input)
    notificationType = try Ocp1Notification2Type(parsing: &input)
    data = Data(parsingRemainingBytes: &input)
    dataFormat = .ocp1
  }

  func encode(into bytes: inout [UInt8]) {
    withUnsafeBytes(of: notificationSize.bigEndian) { bytes += $0 }
    event.encode(into: &bytes)
    bytes.append(notificationType.rawValue)
    bytes.append(contentsOf: data)
  }
}
