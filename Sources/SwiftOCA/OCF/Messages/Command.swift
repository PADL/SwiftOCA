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
/// values encoded in `parameterData`; for OCP.2, the parsed JSON `Parameters` object,
/// which `parameterData` serialises on demand, and `parameterCount` is unused.
public struct Ocp1Parameters: Codable, Sendable {
  public let parameterCount: OcaUint8
  public let format: OcaParameterFormat
  private let _ocp1Data: Data
  #if NonEmbeddedBuild
  private let _ocp2Object: [String: any Sendable]
  #endif

  public var parameterData: Data {
    switch format {
    case .ocp1:
      return _ocp1Data
    case .ocp2:
      #if NonEmbeddedBuild
      // the object was parsed or encoded as valid JSON, so serialising cannot fail
      return _ocp2Object.isEmpty ? Data() : (try? Ocp2JSON.serialize(_ocp2Object)) ?? Data()
      #else
      return Data()
      #endif
    }
  }

  /// The OCP.2 `Parameters` object, or `nil` on OCP.1.
  public var ocp2Parameters: [String: Any]? {
    #if NonEmbeddedBuild
    guard format == .ocp2 else { return nil }
    return _ocp2Object
    #else
    return nil
    #endif
  }

  public init(parameterCount: OcaUint8, parameterData: Data) {
    self.parameterCount = parameterCount
    _ocp1Data = parameterData
    format = .ocp1
    #if NonEmbeddedBuild
    _ocp2Object = [:]
    #endif
  }

  #if NonEmbeddedBuild
  /// OCP.2 parameters from the parsed `Parameters` object.
  public init(ocp2Parameters object: [String: Any]) {
    parameterCount = 0
    _ocp1Data = Data()
    _ocp2Object = Ocp2JSON.sendableObject(object)
    format = .ocp2
  }

  /// OCP.2 parameters from a serialised JSON object; empty data is no parameters.
  public init(ocp2ParameterData parameterData: Data) throws {
    self.init(ocp2Parameters: parameterData.isEmpty ? [:] : try Ocp2JSON.parseObject(parameterData))
  }
  #endif

  public init() {
    self.init(parameterCount: 0, parameterData: Data())
  }

  /// `true` when no parameters are carried, in either format.
  public var isEmpty: Bool {
    switch format {
    case .ocp1:
      return parameterCount == 0 && _ocp1Data.isEmpty
    case .ocp2:
      #if NonEmbeddedBuild
      return _ocp2Object.isEmpty
      #else
      return true
      #endif
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
