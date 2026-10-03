//
// Copyright (c) 2026 PADL Software Pty Ltd
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

/// A method of a control class as the model declares it: its ID, its name, and the
/// types of its parameters and result. Declared once, beside the client method that
/// sends it, and taken by the device class that answers it:
///
///     public static let setPortName =
///       OcaMethodDescription<SetPortNameParameters, Void>("2.7", name: "SetPortName")
///
/// `Parameters` is the one OCA parameter, or a record of several; `Result` likewise
/// for the response; `Void` for none. A record's fields name themselves on OCP.2;
/// `parameterNames` and `resultNames` name a scalar, or override a record's names.
public struct OcaMethodDescription<Parameters, Result>: Sendable {
  /// The description with the types erased, as a table of methods holds it.
  public let erased: OcaAnyMethodDescription

  public var methodID: OcaMethodID { erased.methodID }
  public var name: String { erased.name }

  private init(
    _ methodID: OcaMethodID,
    name: String,
    parameters: (any (Codable & Sendable).Type)?,
    parameterNames: [String]?,
    result: (any (Codable & Sendable).Type)?,
    resultNames: [String]?
  ) {
    erased = OcaAnyMethodDescription(
      methodID: methodID,
      name: name,
      parametersType: parameters,
      resultType: result,
      parameterNames: parameterNames,
      resultNames: resultNames
    )
  }
}

public extension OcaMethodDescription where Parameters: Codable & Sendable,
  Result: Codable & Sendable
{
  init(
    _ methodID: OcaMethodID,
    name: String,
    parameterNames: [String]? = nil,
    resultNames: [String]? = nil
  ) {
    self.init(
      methodID,
      name: name,
      parameters: Parameters.self,
      parameterNames: parameterNames,
      result: Result.self,
      resultNames: resultNames
    )
  }
}

public extension OcaMethodDescription where Parameters: Codable & Sendable, Result == Void {
  init(_ methodID: OcaMethodID, name: String, parameterNames: [String]? = nil) {
    self.init(
      methodID,
      name: name,
      parameters: Parameters.self,
      parameterNames: parameterNames,
      result: nil,
      resultNames: nil
    )
  }
}

public extension OcaMethodDescription where Parameters == Void, Result: Codable & Sendable {
  init(_ methodID: OcaMethodID, name: String, resultNames: [String]? = nil) {
    self.init(
      methodID,
      name: name,
      parameters: nil,
      parameterNames: nil,
      result: Result.self,
      resultNames: resultNames
    )
  }
}

public extension OcaMethodDescription where Parameters == Void, Result == Void {
  init(_ methodID: OcaMethodID, name: String) {
    self.init(
      methodID,
      name: name,
      parameters: nil,
      parameterNames: nil,
      result: nil,
      resultNames: nil
    )
  }
}

/// One parameter, or one result, of a method: its OCP.2 name and its type.
public struct OcaMethodParameterDescription: Sendable {
  public let name: String
  public let type: any (Codable & Sendable).Type
}

/// `OcaMethodDescription` with its types erased.
public struct OcaAnyMethodDescription: Sendable {
  public let methodID: OcaMethodID
  /// The model's name of the method.
  public let name: String
  /// The parameter record, or the one parameter; nil for none.
  public let parametersType: (any (Codable & Sendable).Type)?
  public let resultType: (any (Codable & Sendable).Type)?
  /// The OCP.2 names given explicitly; a record's fields supply the rest.
  public let parameterNames: [String]?
  public let resultNames: [String]?

  public init(
    methodID: OcaMethodID,
    name: String,
    parametersType: (any (Codable & Sendable).Type)?,
    resultType: (any (Codable & Sendable).Type)?,
    parameterNames: [String]?,
    resultNames: [String]?
  ) {
    self.methodID = methodID
    self.name = name
    self.parametersType = parametersType
    self.resultType = resultType
    self.parameterNames = parameterNames
    self.resultNames = resultNames
  }

  /// The parameters as OCP.2 sees them: one per field of a record, else the one value.
  public var parameters: [OcaMethodParameterDescription] {
    parametersType.map { describe($0, names: parameterNames) } ?? []
  }

  /// Likewise for the response.
  public var results: [OcaMethodParameterDescription] {
    resultType.map { describe($0, names: resultNames) } ?? []
  }

  private func describe(_ type: Any.Type, names: [String]?) -> [OcaMethodParameterDescription] {
    let fields: [(name: String, type: Any.Type)] = if type is OcaParametersReflectable.Type {
      Ocp2Naming.fields(of: type)
    } else {
      [(Ocp2Naming.unnamedParameter, type)]
    }
    let names = Ocp2Naming.parameterNames(explicit: names, fieldNames: fields.map(\.name))
    return zip(names, fields).map { name, field in
      guard let type = erasedCast(field.type, to: DescribedType.self) else {
        preconditionFailure(
          "\(self.name)'s \(name) is a \(field.type), which is not Codable & Sendable"
        )
      }
      return OcaMethodParameterDescription(name: name, type: type)
    }
  }
}

private typealias DescribedType = any (Codable & Sendable).Type

/// Kept out of line: the optimiser miscompiles this cast on a specialised metatype
/// (Swift 6.3.3, -O, aarch64).
@inline(never)
private func erasedCast<U>(_ type: Any.Type, to _: U.Type) -> U? {
  type as? U
}
