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

private extension OcaRoot {
  var _controlProtocol: OcaControlProtocol {
    connectionDelegate?.controlProtocol ?? .ocp1
  }

  func sendCommand(
    methodID: OcaMethodID,
    parameters: OcaParameters
  ) async throws {
    guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
    let command = Ocp1Command(
      commandSize: 0,
      targetONo: objectNumber,
      methodID: methodID,
      parameters: parameters
    )
    try await connectionDelegate.sendCommand(command)
  }

  func sendCommandRrq(
    methodID: OcaMethodID,
    parameters: OcaParameters,
    responseParameterCount: OcaUint8
  ) async throws -> OcaParameters {
    let response = try await sendCommandRrq(methodID: methodID, parameters: parameters)
    guard response.statusCode == .ok else {
      throw Ocp1Error.status(response.statusCode)
    }
    if response.parameters.format == .ocp1 {
      guard response.parameters.parameterCount == responseParameterCount else {
        throw Ocp1Error.responseParameterOutOfRange
      }
    }
    return response.parameters
  }

  /// Encodes `parameters` for the connection's protocol. `parameterNames` names them
  /// on OCP.2 (see `Ocp2Encoder.encodeParameters`) and is ignored on OCP.1.
  func encodeParameters(
    _ parameters: some Encodable,
    parameterCount: OcaUint8? = nil,
    parameterNames: [String]? = nil,
    userInfo: [CodingUserInfoKey: Any]? = nil
  ) throws -> OcaParameters {
    switch _controlProtocol {
    case .ocp1:
      var encoder = Ocp1Encoder()
      if let userInfo { encoder.userInfo = userInfo }
      return try OcaParameters(
        parameterCount: parameterCount ?? _ocp1ParameterCount(type: type(of: parameters)),
        parameterData: encoder.encode(parameters)
      )
    #if NonEmbeddedBuild
    case .ocp2:
      var encoder = Ocp2Encoder()
      if let userInfo { encoder.userInfo = userInfo }
      return try OcaParameters(
        ocp2Parameters: encoder.encodeParameters(parameters, parameterNames: parameterNames)
      )
    #endif
    }
  }

  func decodeResponse<U: Decodable>(
    _ type: U.Type,
    from parameters: OcaParameters,
    parameterNames: [String]? = nil,
    userInfo: [CodingUserInfoKey: Any]? = nil
  ) throws -> U {
    switch parameters.format {
    case .ocp1:
      var decoder = Ocp1Decoder()
      if let userInfo { decoder.userInfo = userInfo }
      return try decoder.decode(U.self, from: parameters.parameterData)
    case .ocp2:
      #if NonEmbeddedBuild
      var decoder = Ocp2Decoder()
      if let userInfo { decoder.userInfo = userInfo }
      return try decoder.decodeParameters(
        U.self,
        from: parameters.ocp2Parameters,
        parameterNames: parameterNames
      )
      #else
      throw Ocp1Error.unsupportedControlProtocol
      #endif
    }
  }
}

public extension OcaRoot {
  /// Send a command, not expecting a response.
  ///
  /// `parameterNames` names the parameters on an OCP.2 connection: one name per
  /// stored property of a parameter record, or a single name for a scalar. Names not
  /// supplied are derived from the Swift field names (`Ocp2Naming`).
  final func sendCommand<T: Encodable>(
    methodID: OcaMethodID,
    parameterCount: OcaUint8? = nil,
    parameters: T,
    parameterNames: [String]? = nil,
    userInfo: [CodingUserInfoKey: Any]? = nil
  ) async throws {
    let parameters = try encodeParameters(
      parameters,
      parameterCount: parameterCount,
      parameterNames: parameterNames,
      userInfo: userInfo
    )
    try await sendCommand(methodID: methodID, parameters: parameters)
  }
}

public extension OcaRoot {
  struct Placeholder: Codable {
    public init() {}
  }

  /// Send a command and decode its response. `parameterNames` is as for
  /// `sendCommand`. The response is matched by name, so `responseNames` is needed only
  /// where the response record's field names differ from the model's (a bounded
  /// property's `Gain`, `minGain`, `maxGain`).
  final func sendCommandRrq<T: Encodable, U: Decodable>(
    methodID: OcaMethodID,
    parameters: T = Placeholder(),
    parameterNames: [String]? = nil,
    responseNames: [String]? = nil,
    userInfo: [CodingUserInfoKey: Any]? = nil
  ) async throws -> U {
    let parameters = try encodeParameters(
      parameters,
      parameterNames: parameterNames,
      userInfo: userInfo
    )
    let response = try await sendCommandRrq(
      methodID: methodID,
      parameters: parameters,
      responseParameterCount: _ocp1ParameterCount(type: U.self)
    )
    return try decodeResponse(U.self, from: response, parameterNames: responseNames, userInfo: userInfo)
  }

  final func sendCommandRrq<T: Encodable>(
    methodID: OcaMethodID,
    parameters: T,
    parameterNames: [String]? = nil,
    userInfo: [CodingUserInfoKey: Any]? = nil
  ) async throws {
    let parameters = try encodeParameters(
      parameters,
      parameterNames: parameterNames,
      userInfo: userInfo
    )
    _ = try await sendCommandRrq(
      methodID: methodID,
      parameters: parameters,
      responseParameterCount: 0
    )
  }

  final func sendCommandRrq(
    methodID: OcaMethodID
  ) async throws {
    _ = try await sendCommandRrq(
      methodID: methodID,
      parameters: OcaParameters(),
      responseParameterCount: 0
    )
  }
}

public extension OcaRoot {
  /// Send pre-encoded parameters; they must be in the connection's format.
  final func sendCommandRrq(
    methodID: OcaMethodID,
    parameters: OcaParameters
  ) async throws -> Ocp1Response {
    guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
    guard parameters.isEmpty || parameters.format == connectionDelegate.controlProtocol.parameterFormat
    else {
      throw Ocp1Error.unsupportedControlProtocol
    }

    let command = Ocp1Command(
      commandSize: 0,
      targetONo: objectNumber,
      methodID: methodID,
      parameters: parameters
    )
    return try await connectionDelegate.sendCommandRrq(command)
  }

  // public for FlutterSwiftOCA to use; OCP.1-encoded parameters only
  final func sendCommandRrq(
    methodID: OcaMethodID,
    parameterCount: OcaUint8,
    parameterData: Data
  ) async throws -> Ocp1Response {
    try await sendCommandRrq(
      methodID: methodID,
      parameters: OcaParameters(parameterCount: parameterCount, parameterData: parameterData)
    )
  }
}
