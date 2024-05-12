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

import Foundation

private extension OcaRoot {
    func sendCommand(
        methodID: OcaMethodID,
        parameterCount: OcaUint8,
        parameterData: Data
    ) async throws {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
        let command = Ocp1Command(
            commandSize: 0,
            handle: await connectionDelegate.getNextCommandHandle(),
            targetONo: objectNumber,
            methodID: methodID,
            parameters: Ocp1Parameters(
                parameterCount: parameterCount,
                parameterData: parameterData
            )
        )
        try await connectionDelegate.sendCommand(command)
    }

    func sendCommandRrq(
        methodID: OcaMethodID,
        parameterCount: OcaUint8,
        parameterData: Data,
        responseParameterCount: OcaUint8,
        responseParameterData: inout Data
    ) async throws {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }

        let response = try await withThrowingTimeout(
            of: connectionDelegate.options
                .responseTimeout
        ) {
            try await self.sendCommandRrq(
                methodID: methodID,
                parameterCount: parameterCount,
                parameterData: parameterData
            )
        }

        guard response.statusCode == .ok else {
            throw Ocp1Error.status(response.statusCode)
        }
        guard response.parameters.parameterCount == responseParameterCount else {
            throw Ocp1Error.responseParameterOutOfRange
        }
        responseParameterData = response.parameters.parameterData
    }

    func encodeParameters(
        _ parameters: some Encodable,
        userInfo: [CodingUserInfoKey: Any]? = nil
    ) throws -> Data {
        var encoder = Ocp1Encoder()
        if let userInfo { encoder.userInfo = userInfo }
        return try encoder.encode(parameters)
    }

    func decodeResponse<U: Decodable>(
        _ type: U.Type,
        from data: Data,
        userInfo: [CodingUserInfoKey: Any]? = nil
    ) throws -> U {
        var decoder = Ocp1Decoder()
        if let userInfo { decoder.userInfo = userInfo }
        return try decoder.decode(U.self, from: data)
    }
}

extension OcaRoot {
    /// Send a command, not expecting a response
    func sendCommand<T: Encodable>(
        methodID: OcaMethodID,
        parameterCount: OcaUint8 = _ocp1ParameterCount(type: T.self),
        parameters: T,
        userInfo: [CodingUserInfoKey: Any]? = nil
    ) async throws {
        let parameterData = try encodeParameters(parameters, userInfo: userInfo)

        try await sendCommand(
            methodID: methodID,
            parameterCount: parameterCount,
            parameterData: parameterData
        )
    }
}

extension OcaRoot {
    struct Placeholder: Codable {}

    final func sendCommandRrq<T: Encodable, U: Decodable>(
        methodID: OcaMethodID,
        parameters: T = Placeholder(),
        userInfo: [CodingUserInfoKey: Any]? = nil
    ) async throws -> U {
        let parameterData = try encodeParameters(parameters, userInfo: userInfo)
        var responseParameterData = Data()

        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: _ocp1ParameterCount(type: T.self),
            parameterData: parameterData,
            responseParameterCount: _ocp1ParameterCount(type: U.self),
            responseParameterData: &responseParameterData
        )
        return try decodeResponse(U.self, from: responseParameterData, userInfo: userInfo)
    }

    final func sendCommandRrq<T: Encodable>(
        methodID: OcaMethodID,
        parameters: T,
        userInfo: [CodingUserInfoKey: Any]? = nil
    ) async throws {
        let parameterData = try encodeParameters(parameters, userInfo: userInfo)
        var responseParameterData = Data()

        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: _ocp1ParameterCount(type: T.self),
            parameterData: parameterData,
            responseParameterCount: 0,
            responseParameterData: &responseParameterData
        )
    }

    final func sendCommandRrq(
        methodID: OcaMethodID
    ) async throws {
        var responseParameterData = Data()
        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: 0,
            parameterData: Data(),
            responseParameterCount: 0,
            responseParameterData: &responseParameterData
        )
    }
}

public extension OcaRoot {
    // public for FlutterSwiftOCA to use
    final func sendCommandRrq(
        methodID: OcaMethodID,
        parameterCount: OcaUint8,
        parameterData: Data
    ) async throws -> Ocp1Response {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }

        return try await withThrowingTimeout(of: connectionDelegate.options.responseTimeout) {
            let command = Ocp1Command(
                commandSize: 0,
                handle: await connectionDelegate.getNextCommandHandle(),
                targetONo: self.objectNumber,
                methodID: methodID,
                parameters: Ocp1Parameters(
                    parameterCount: parameterCount,
                    parameterData: parameterData
                )
            )
            return try await connectionDelegate.sendCommandRrq(command)
        }
    }
}
