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

// TODO: clean this up so there aren't so many functions!

extension OcaRoot {
    private func sendCommand(
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

    func sendCommand<T: Encodable>(
        methodID: OcaMethodID,
        parameterCount: OcaUint8,
        parameters: T
    ) async throws {
        let parameterData = try encodeParameters([parameters])

        try await sendCommand(
            methodID: methodID,
            parameterCount: parameterCount,
            parameterData: parameterData
        )
    }

    // public for FlutterSwiftOCA to use
    public func sendCommandRrq(
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

    private func sendCommandRrq(
        methodID: OcaMethodID,
        parameterCount: OcaUint8,
        parameterData: Data,
        responseParameterCount: OcaUint8,
        responseParameterData: inout Data
    ) async throws {
        let response = try await sendCommandRrq(
            methodID: methodID,
            parameterCount: parameterCount,
            parameterData: parameterData
        )

        guard response.statusCode == .ok else {
            throw Ocp1Error.status(response.statusCode)
        }
        guard response.parameters.parameterCount == responseParameterCount else {
            throw Ocp1Error.responseParameterOutOfRange
        }
        responseParameterData = response.parameters.parameterData
    }

    private func encodeParameters<T: Encodable>(_ parameters: [T]) throws -> Data {
        guard parameters.count <= OcaUint8.max else {
            throw Ocp1Error.requestParameterOutOfRange
        }
        var parameterData = Data()
        for parameter in parameters {
            let paramData: Data = try Ocp1Encoder().encode(parameter)
            parameterData.append(paramData)
        }

        return parameterData
    }

    struct NullCodable: Codable {}

    private func decodeResponse<U: Decodable>(_ type: U.Type, from data: Data) throws -> U {
        try Ocp1Decoder().decode(U.self, from: data)
    }

    func sendCommandRrq<T: Encodable, U: Decodable>(
        methodID: OcaMethodID,
        parameterCount: OcaUint8 = 0,
        parameters: [T] = [NullCodable()],
        responseParameterCount: OcaUint8 = 0,
        responseParameters: inout U
    ) async throws {
        let parameterData = try encodeParameters(parameters)
        var responseParameterData = Data()

        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: parameterCount,
            parameterData: parameterData,
            responseParameterCount: responseParameterCount,
            responseParameterData: &responseParameterData
        )
        if responseParameterCount != 0 {
            responseParameters = try decodeResponse(U.self, from: responseParameterData)
        }
    }

    func sendCommandRrq<T: Encodable, U: Decodable>(
        methodID: OcaMethodID,
        parameter: T,
        responseParameterCount: OcaUint8,
        responseParameters: inout U
    ) async throws {
        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: 1,
            parameters: [parameter],
            responseParameterCount: responseParameterCount,
            responseParameters: &responseParameters
        )
    }

    func sendCommandRrq<T: Encodable>(
        methodID: OcaMethodID,
        parameter: T
    ) async throws {
        var placeholder = NullCodable()
        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: 1,
            parameters: [parameter],
            responseParameterCount: 0,
            responseParameters: &placeholder
        )
    }

    func sendCommandRrq<T: Encodable, U: Decodable>(
        methodID: OcaMethodID,
        parameters: T,
        responseParameterCount: OcaUint8,
        responseParameters: inout U
    ) async throws {
        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: _ocp1ParameterCount(value: parameters),
            parameters: [parameters],
            responseParameterCount: responseParameterCount,
            responseParameters: &responseParameters
        )
    }

    func sendCommandRrq<T: Encodable, U: Decodable>(
        methodID: OcaMethodID,
        parameters: T,
        responseParameters: inout U
    ) async throws {
        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: _ocp1ParameterCount(value: parameters),
            parameters: [parameters],
            responseParameterCount: _ocp1ParameterCount(type: U.self),
            responseParameters: &responseParameters
        )
    }

    func sendCommandRrq<T: Encodable>(
        methodID: OcaMethodID,
        parameterCount: OcaUint8,
        parameters: T
    ) async throws {
        var placeholder = NullCodable()
        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: parameterCount,
            parameters: [parameters],
            responseParameterCount: 0,
            responseParameters: &placeholder
        )
    }

    func sendCommandRrq<T: Encodable>(
        methodID: OcaMethodID,
        parameters: T
    ) async throws {
        var placeholder = NullCodable()
        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: _ocp1ParameterCount(value: parameters),
            parameters: [parameters],
            responseParameterCount: 0,
            responseParameters: &placeholder
        )
    }

    func sendCommandRrq(methodID: OcaMethodID) async throws {
        var placeholder = NullCodable()
        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: 0,
            parameters: [placeholder],
            responseParameterCount: 0,
            responseParameters: &placeholder
        )
    }

    // this variant avoids having to allocate inout response type
    func sendCommandRrq<U: Decodable>(
        methodID: OcaMethodID,
        responseParameterCount: OcaUint8? = nil
    ) async throws -> U {
        var responseParameterData = Data()

        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: 0,
            parameterData: Data(),
            responseParameterCount: responseParameterCount ?? _ocp1ParameterCount(type: U.self),
            responseParameterData: &responseParameterData
        )

        return try decodeResponse(U.self, from: responseParameterData)
    }

    func sendCommandRrq<T: Encodable, U: Decodable>(
        methodID: OcaMethodID,
        parameters: T
    ) async throws -> U {
        var responseParameterData = Data()

        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: _ocp1ParameterCount(value: parameters),
            parameters: [parameters],
            responseParameterCount: _ocp1ParameterCount(type: U.self),
            responseParameters: &responseParameterData
        )

        return try decodeResponse(U.self, from: responseParameterData)
    }

    func sendCommandRrq<T: Encodable, U: Decodable>(
        methodID: OcaMethodID,
        parameter: T
    ) async throws -> U {
        var responseParameterData = Data()

        try await sendCommandRrq(
            methodID: methodID,
            parameterCount: 1,
            parameters: [parameter],
            responseParameterCount: _ocp1ParameterCount(type: U.self),
            responseParameters: &responseParameterData
        )

        return try decodeResponse(U.self, from: responseParameterData)
    }
}
