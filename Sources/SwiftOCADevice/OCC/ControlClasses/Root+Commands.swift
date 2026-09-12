//
// Copyright (c) 2023 PADL Software Pty Ltd
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
@_spi(SwiftOCAPrivate)
import SwiftOCA

/// The format a command arrived in, and so the format its response must take. Bound
/// by `OcaDevice.handleCommand` around dispatch so the per-class `handleCommand`
/// overrides need not know which protocol the controller speaks. `responseNames`
/// names an OCP.2 response's parameters (see `Ocp2Encoder.encodeParameters`).
public extension OcaRoot {
  private nonisolated static func _logUnexpectedParameterCount(
    _ command: Ocp1Command,
    expected responseParameterCount: UInt8? = nil
  ) {
    Task {
      await OcaDevice.shared.logger.info(
        "OcaRoot.decodeCommand(\(command)): unexpected parameter count \(command.parameters.parameterCount), expected \(responseParameterCount != nil ? "\(responseParameterCount!)" : "none")"
      )
    }
  }

  nonisolated static func decodeCommand<U: Decodable>(
    _ command: Ocp1Command
  ) throws -> U {
    switch command.parameters.format {
    case .ocp1:
      let responseParameterCount = _ocp1ParameterCount(type: U.self)
      let response = try Ocp1Decoder().decode(U.self, from: command.parameters.parameterData)
      if command.parameters.parameterCount != responseParameterCount {
        _logUnexpectedParameterCount(command, expected: responseParameterCount)
        throw Ocp1Error.status(.parameterOutOfRange)
      }
      return response
    case .ocp2:
      #if NonEmbeddedBuild
      do {
        return try Ocp2Decoder().decodeParameters(U.self, from: command.parameters.ocp2Parameters)
      } catch let error as Ocp1Error {
        throw error
      } catch {
        throw Ocp1Error.status(.parameterError)
      }
      #else
      throw Ocp1Error.unsupportedControlProtocol
      #endif
    }
  }

  final nonisolated func decodeCommand<U: Decodable>(
    _ command: Ocp1Command
  ) throws -> U {
    try Self.decodeCommand(command)
  }

  final nonisolated func decodeNullCommand(
    _ command: Ocp1Command
  ) throws {
    guard command.parameters.isEmpty else {
      Self._logUnexpectedParameterCount(command)
      throw Ocp1Error.status(.parameterOutOfRange)
    }
  }

  @available(*, unavailable, message: "call encodeResponse on the controller handling the command")
  nonisolated static func encodeResponse<T: Encodable>(
    _ parameters: T,
    names: [String]? = nil,
    statusCode: OcaStatus = .ok
  ) throws -> Ocp1Response {
    fatalError("unavailable")
  }
}

public extension OcaController {
  /// Encodes a response in the protocol this controller speaks. On OCP.2 the
  /// parameters are named by `names`, else derived from the value's field names; a
  /// scalar without a name goes out as `Ocp2Naming.unnamedParameter`.
  nonisolated func encodeResponse<T: Encodable>(
    _ parameters: T,
    names: [String]? = nil,
    statusCode: OcaStatus = .ok
  ) throws -> Ocp1Response {
    switch controlProtocol {
    case .ocp1:
      let parameterCount = _ocp1ParameterCount(type: T.self)
      let encoder = Ocp1Encoder()
      let parameters = try Ocp1Parameters(
        parameterCount: parameterCount,
        parameterData: encoder.encode(parameters)
      )
      return Ocp1Response(statusCode: statusCode, parameters: parameters)
    case .ocp2:
      #if NonEmbeddedBuild
      let object = try Ocp2Encoder().encodeParameters(
        parameters,
        parameterNames: names
      )
      return Ocp1Response(statusCode: statusCode, parameters: Ocp1Parameters(ocp2Parameters: object))
      #else
      throw Ocp1Error.unsupportedControlProtocol
      #endif
    }
  }

  /// A single-parameter response whose OCP.2 name is `name`.
  nonisolated func encodeResponse(
    _ parameter: some Encodable,
    name: String,
    statusCode: OcaStatus = .ok
  ) throws -> Ocp1Response {
    try encodeResponse(parameter, names: [name], statusCode: statusCode)
  }
}
