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

public struct Ocp1EventData: Codable, Sendable, _Ocp1Codable {
  public let event: OcaEvent
  public let eventParameters: Data

  public init(event: OcaEvent, eventParameters: Data) {
    self.event = event
    self.eventParameters = eventParameters
  }

  init(parsing input: inout ParserSpan) throws {
    event = try OcaEvent(parsing: &input)
    eventParameters = Data(parsingRemainingBytes: &input)
  }

  func encode(into bytes: inout [UInt8]) {
    event.encode(into: &bytes)
    bytes.append(contentsOf: eventParameters)
  }
}

public struct Ocp1NtfParams: Codable, Sendable, _Ocp1Codable {
  public let parameterCount: OcaUint8
  public let context: OcaBlob
  public let eventData: Ocp1EventData

  public init(parameterCount: OcaUint8, context: OcaBlob, eventData: Ocp1EventData) {
    self.parameterCount = parameterCount
    self.context = context
    self.eventData = eventData
  }

  init(parsing input: inout ParserSpan) throws {
    parameterCount = try OcaUint8(parsing: &input)
    context = try LengthTaggedData(parsing: &input)
    eventData = try Ocp1EventData(parsing: &input)
  }

  func encode(into bytes: inout [UInt8]) {
    bytes.append(parameterCount)
    context.encode(into: &bytes)
    eventData.encode(into: &bytes)
  }
}

public struct Ocp1Notification1: _Ocp1MessageCodable, Sendable {
  public let notificationSize: OcaUint32
  public let targetONo: OcaONo
  public let methodID: OcaMethodID
  public let parameters: Ocp1NtfParams

  public var messageSize: OcaUint32 { notificationSize }

  public init(
    notificationSize: OcaUint32 = 0,
    targetONo: OcaONo,
    methodID: OcaMethodID,
    parameters: Ocp1NtfParams
  ) {
    self.notificationSize = notificationSize
    self.targetONo = targetONo
    self.methodID = methodID
    self.parameters = parameters
  }

  // FIXME: package visibility required for OCAEventBenchmark

  package init(bytes: borrowing Data) throws {
    self = try Ocp1Error.mapping { [bytes = copy bytes] in
      try bytes.withParserSpan { try Self(parsing: &$0) }
    }
  }

  package init(parsing input: inout ParserSpan) throws {
    notificationSize = try OcaUint32(parsingBigEndian: &input)
    targetONo = try OcaONo(parsingBigEndian: &input)
    methodID = try OcaMethodID(parsing: &input)
    parameters = try Ocp1NtfParams(parsing: &input)
  }

  package func encode(into bytes: inout [UInt8]) {
    withUnsafeBytes(of: notificationSize.bigEndian) { bytes += $0 }
    withUnsafeBytes(of: targetONo.bigEndian) { bytes += $0 }
    methodID.encode(into: &bytes)
    parameters.encode(into: &bytes)
  }
}
