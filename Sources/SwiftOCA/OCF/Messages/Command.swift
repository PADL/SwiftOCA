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

public struct Ocp1Parameters: Codable, Sendable {
  public let parameterCount: OcaUint8
  public let parameterData: Data

  public init(parameterCount: OcaUint8, parameterData: Data) {
    self.parameterCount = parameterCount
    self.parameterData = parameterData
  }

  public init() {
    self.init(parameterCount: 0, parameterData: Data())
  }
}

public struct Ocp1Command: _Ocp1MessageCodable, Sendable {
  public let commandSize: OcaUint32
  public let handle: OcaUint32
  public let targetONo: OcaONo
  public let methodID: OcaMethodID
  public let parameters: Ocp1Parameters

  public var messageSize: OcaUint32 { commandSize }

  public init(
    commandSize: OcaUint32 = 0,
    handle: OcaUint32,
    targetONo: OcaONo,
    methodID: OcaMethodID,
    parameters: Ocp1Parameters = .init()
  ) {
    self.commandSize = commandSize
    self.handle = handle
    self.targetONo = targetONo
    self.methodID = methodID
    self.parameters = parameters
  }

  init(parsing input: inout ParserSpan) throws {
    commandSize = try OcaUint32(parsingBigEndian: &input)
    handle = try OcaUint32(parsingBigEndian: &input)
    targetONo = try OcaONo(parsingBigEndian: &input)
    methodID = try OcaMethodID(parsing: &input)
    parameters = try Ocp1Parameters(
      parameterCount: OcaUint8(parsing: &input),
      parameterData: Data(parsingRemainingBytes: &input)
    )
  }

  func encode(into bytes: inout [UInt8]) {
    withUnsafeBytes(of: commandSize.bigEndian) { bytes += $0 }
    withUnsafeBytes(of: handle.bigEndian) { bytes += $0 }
    withUnsafeBytes(of: targetONo.bigEndian) { bytes += $0 }
    methodID.encode(into: &bytes)
    bytes.append(parameters.parameterCount)
    bytes.append(contentsOf: parameters.parameterData)
  }
}
