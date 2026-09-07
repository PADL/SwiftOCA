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

/// Method parameters as carried on the wire. For OCP.1, `parameterCount` positional
/// values encoded in `parameterData`; for OCP.2, `parameterData` is the serialised JSON
/// `Parameters` object and `parameterCount` is unused.
public struct Ocp1Parameters: Codable, Sendable {
  public let parameterCount: OcaUint8
  public let parameterData: Data
  public let format: OcaParameterFormat

  public init(parameterCount: OcaUint8, parameterData: Data) {
    self.parameterCount = parameterCount
    self.parameterData = parameterData
    format = .ocp1
  }

  /// OCP.2 parameters: `parameterData` is a serialised JSON object.
  public init(ocp2ParameterData parameterData: Data) {
    parameterCount = 0
    self.parameterData = parameterData
    format = .ocp2
  }

  public init() {
    self.init(parameterCount: 0, parameterData: Data())
  }

  /// `true` when no parameters are carried, in either format.
  public var isEmpty: Bool {
    switch format {
    case .ocp1:
      parameterCount == 0 && parameterData.isEmpty
    case .ocp2:
      parameterData.isEmpty
    }
  }

  enum CodingKeys: CodingKey {
    case parameterCount
    case parameterData
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      parameterCount: try container.decode(OcaUint8.self, forKey: .parameterCount),
      parameterData: try container.decode(Data.self, forKey: .parameterData)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(parameterCount, forKey: .parameterCount)
    try container.encode(parameterData, forKey: .parameterData)
  }
}

public struct Ocp1Command: _Ocp1MessageCodable, Sendable {
  public let commandSize: OcaUint32
  /// assigned by the connection when the command is sent
  public var handle: OcaUint32
  public let targetONo: OcaONo
  public let methodID: OcaMethodID
  public let parameters: Ocp1Parameters

  public var messageSize: OcaUint32 { commandSize }

  public init(
    commandSize: OcaUint32 = 0,
    handle: OcaUint32 = 0,
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
