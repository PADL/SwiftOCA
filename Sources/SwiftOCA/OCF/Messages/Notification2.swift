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
  /// OCP.1 event data (`.event`) or an OCP.1-encoded `Ocp1Notification2ExceptionData`
  /// (`.exception`). Exception data is always OCP.1-encoded, whatever the framing,
  /// so `throwIfException` works for both.
  private let _data: Data
  #if NonEmbeddedBuild
  /// OCP.2 event data, held as parsed and serialised only if `data` is asked for.
  private let _ocp2Value: (any Sendable)?
  #endif
  /// The marshaling of the event data for an `.event` notification.
  package let dataFormat: OcaParameterFormat

  public var messageSize: OcaUint32 { notificationSize }

  /// The event data as wire bytes.
  var data: Data {
    switch dataFormat {
    case .ocp1:
      return _data
    case .ocp2:
      // parsed or encoded as valid JSON, so serialising cannot fail
      return (try? eventData.data) ?? Data()
    }
  }

  /// The event data as it was received or encoded.
  package var eventData: OcaEncodedEventData {
    #if NonEmbeddedBuild
    switch dataFormat {
    case .ocp1: .ocp1(_data)
    case .ocp2: .ocp2(_ocp2Value)
    }
    #else
    .ocp1(_data)
    #endif
  }

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
      eventData: .ocp1(data)
    )
  }

  package init(
    notificationSize: OcaUint32 = 0,
    event: OcaEvent,
    notificationType: Ocp1Notification2Type,
    eventData: OcaEncodedEventData
  ) {
    self.notificationSize = notificationSize
    self.event = event
    self.notificationType = notificationType
    switch eventData {
    case let .ocp1(data):
      _data = data
      dataFormat = .ocp1
      #if NonEmbeddedBuild
      _ocp2Value = nil
      #endif
    #if NonEmbeddedBuild
    case let .ocp2(value):
      _data = Data()
      _ocp2Value = value
      dataFormat = .ocp2
    #endif
    }
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
    _data = Data(parsingRemainingBytes: &input)
    dataFormat = .ocp1
    #if NonEmbeddedBuild
    _ocp2Value = nil
    #endif
  }

  func encode(into bytes: inout [UInt8]) {
    withUnsafeBytes(of: notificationSize.bigEndian) { bytes += $0 }
    event.encode(into: &bytes)
    bytes.append(notificationType.rawValue)
    bytes.append(contentsOf: data)
  }
}
