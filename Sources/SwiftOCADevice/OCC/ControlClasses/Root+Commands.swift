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

@_spi(SwiftOCAPrivate)
import SwiftOCA

public extension OcaRoot {
  nonisolated static func decodeCommand<U: Decodable>(
    _ command: Ocp1Command
  ) throws -> U {
    let responseParameterCount = _ocp1ParameterCount(type: U.self)
    let response = try Ocp1Decoder().decode(U.self, from: command.parameters.parameterData)
    if command.parameters.parameterCount != responseParameterCount {
      Task {
        await OcaDevice.shared.logger.info(
          "OcaRoot.decodeCommand(\(command)): unexpected parameter count \(command.parameters.parameterCount), expected \(responseParameterCount)"
        )
      }
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return response
  }

  final nonisolated func decodeCommand<U: Decodable>(
    _ command: Ocp1Command
  ) throws -> U {
    try Self.decodeCommand(command)
  }

  final nonisolated func decodeNullCommand(
    _ command: Ocp1Command
  ) throws {
    guard command.parameters.parameterCount == 0,
          command.parameters.parameterData.isEmpty
    else {
      Task {
        await OcaDevice.shared.logger.info(
          "OcaRoot.decodeCommand(\(command)): unexpected parameter count \(command.parameters.parameterCount), expected none"
        )
      }
      throw Ocp1Error.status(.parameterOutOfRange)
    }
  }

  nonisolated static func encodeResponse<T: Encodable>(
    _ parameters: T,
    statusCode: OcaStatus = .ok
  ) throws -> Ocp1Response {
    let parameterCount = _ocp1ParameterCount(type: T.self)
    let encoder = Ocp1Encoder()
    let parameters = try Ocp1Parameters(
      parameterCount: parameterCount,
      parameterData: encoder.encode(parameters)
    )

    return Ocp1Response(statusCode: statusCode, parameters: parameters)
  }

  final nonisolated func encodeResponse(
    _ parameters: some Encodable,
    statusCode: OcaStatus = .ok
  ) throws -> Ocp1Response {
    try Self.encodeResponse(parameters, statusCode: statusCode)
  }
}
