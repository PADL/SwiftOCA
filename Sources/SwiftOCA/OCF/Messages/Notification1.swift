//
// Copyright (c) 2023-2025 PADL Software Pty Ltd
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

  init(bytes: borrowing[UInt8]) throws {
    event = try OcaEvent(bytes: bytes)
    eventParameters = Data(bytes[8...])
  }

  func encode(into bytes: inout [UInt8]) {
    event.encode(into: &bytes)
    bytes += eventParameters
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

  init(bytes: borrowing[UInt8]) throws {
    guard bytes.count > 1 else { throw Ocp1Error.pduTooShort }
    parameterCount = bytes[0]
    context = try LengthTaggedData(bytes: Array(bytes[1...]))
    // FIXME: abstraction violation
    let eventDataOffset = 1 + 2 + context.count
    precondition(bytes.count >= eventDataOffset)
    eventData = try Ocp1EventData(bytes: Array(bytes[eventDataOffset...]))
  }

  func encode(into bytes: inout [UInt8]) {
    bytes += [parameterCount]
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

  package init(bytes: borrowing[UInt8]) throws {
    guard bytes.count > 12 else { throw Ocp1Error.pduTooShort }
    notificationSize = bytes.withUnsafeBytes {
      OcaUint32(bigEndian: $0.loadUnaligned(fromByteOffset: 0, as: OcaUint32.self))
    }
    targetONo = bytes.withUnsafeBytes {
      OcaUint32(bigEndian: $0.loadUnaligned(fromByteOffset: 4, as: OcaUint32.self))
    }
    methodID = try OcaMethodID(bytes: Array(bytes[8..<12]))
    parameters = try Ocp1NtfParams(bytes: Array(bytes[12...]))
  }

  package func encode(into bytes: inout [UInt8]) {
    withUnsafeBytes(of: notificationSize.bigEndian) { bytes += $0 }
    withUnsafeBytes(of: targetONo.bigEndian) { bytes += $0 }
    methodID.encode(into: &bytes)
    parameters.encode(into: &bytes)
  }
}
