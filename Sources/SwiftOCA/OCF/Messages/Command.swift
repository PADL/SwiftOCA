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
public struct OcaParameters: Codable, Sendable {
  /// One payload rather than one per format, so an OCP.1 connection carries no JSON
  /// object to initialise, retain and release on every message it decodes.
  private enum Storage: Sendable {
    case ocp1(Data)
    #if NonEmbeddedBuild
    case ocp2([String: any Sendable])
    #endif
  }

  public let parameterCount: OcaUint8
  private let storage: Storage

  public var format: OcaParameterFormat {
    switch storage {
    case .ocp1:
      return .ocp1
    #if NonEmbeddedBuild
    case .ocp2:
      return .ocp2
    #endif
    }
  }

  public var parameterData: Data {
    switch storage {
    case let .ocp1(data):
      return data
    #if NonEmbeddedBuild
    case let .ocp2(object):
      // the object was parsed or encoded as valid JSON, so serialising cannot fail
      return object.isEmpty ? Data() : (try? Ocp2JSON.serialize(object)) ?? Data()
    #endif
    }
  }

  /// The OCP.2 `Parameters` object, or `nil` on OCP.1. The containers are `Sendable`,
  /// whether they were parsed from the wire or encoded here, so a received object can be
  /// carried across a task boundary as it is.
  public var ocp2Parameters: [String: any Sendable]? {
    #if NonEmbeddedBuild
    guard case let .ocp2(object) = storage else { return nil }
    return object
    #else
    return nil
    #endif
  }

  public init(parameterCount: OcaUint8, parameterData: Data) {
    self.parameterCount = parameterCount
    storage = .ocp1(parameterData)
  }

  #if NonEmbeddedBuild
  /// OCP.2 parameters from the parsed `Parameters` object.
  public init(ocp2Parameters object: [String: Any]) {
    parameterCount = 0
    storage = .ocp2(Ocp2JSON.sendableObject(object))
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
    switch storage {
    case let .ocp1(data):
      return parameterCount == 0 && data.isEmpty
    #if NonEmbeddedBuild
    case let .ocp2(object):
      return object.isEmpty
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
  public let parameters: OcaParameters

  public var messageSize: OcaUint32 { commandSize }

  public init(
    commandSize: OcaUint32 = 0,
    handle: OcaUint32 = 0,
    targetONo: OcaONo,
    methodID: OcaMethodID,
    parameters: OcaParameters = .init()
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
    parameters = try OcaParameters(
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
