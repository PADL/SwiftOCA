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

import SwiftOCA

public extension OcaRoot {
    static func decodeCommand<U: Decodable>(
        _ command: Ocp1Command,
        responseParameterCount: OcaUint8? = nil
    ) throws -> U {
        let response = try Ocp1Decoder().decode(U.self, from: command.parameters.parameterData)
        let responseParameterCount = responseParameterCount ?? _ocp1ParameterCount(type: U.self)
        if command.parameters.parameterCount != responseParameterCount {
            Task {
                await OcaDevice.shared.logger.trace(
                    "OcaRoot.decodeCommand: unexpected parameter count \(responseParameterCount), expected \(command.parameters.parameterCount)"
                )
            }
        }
        return response
    }

    static func encodeResponse<T: Encodable>(
        _ parameters: T,
        parameterCount: OcaUint8? = nil,
        statusCode: OcaStatus = .ok
    ) throws -> Ocp1Response {
        let encoder = Ocp1Encoder()
        let parameters = Ocp1Parameters(
            parameterCount: parameterCount ?? _ocp1ParameterCount(value: parameters),
            parameterData: try encoder.encode(parameters)
        )

        return Ocp1Response(statusCode: statusCode, parameters: parameters)
    }

    func decodeCommand<U: Decodable>(
        _ command: Ocp1Command,
        responseParameterCount: OcaUint8? = nil
    ) throws -> U {
        try Self.decodeCommand(command, responseParameterCount: responseParameterCount)
    }

    func encodeResponse<T: Encodable>(
        _ parameters: T,
        parameterCount: OcaUint8? = nil,
        statusCode: OcaStatus = .ok
    ) throws -> Ocp1Response {
        try Self.encodeResponse(parameters, parameterCount: parameterCount, statusCode: statusCode)
    }
}
