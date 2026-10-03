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

@_spi(SwiftOCAPrivate)
import SwiftOCA

/// Declares a method of a device class to be the OCA method `methodID`, named `name`
/// in the model. The method's own parameters are the OCA parameters, in order, with the
/// controller as one more argument (`from controller: any OcaController`); its result,
/// if any, is the response. Several parameters become one OCP.1 parameter record, which
/// the macro declares beside the method. `access` is the lock check made before the
/// method runs: `.read` for a getter, `.write` for a mutator, `.none` for a method that
/// checks for itself. `parameterNames` and `resultNames` give the OCP.2 names where the
/// model spells them differently from the Swift names.
///
///     @OcaDeviceMethod("2.7", name: "SetPortName", access: .write)
///     func setPortName(_ id: OcaPortID, _ name: OcaString, from controller: any OcaController) async throws
///
/// The class lists its methods with `@OcaDeviceMethods`, and `OcaRoot.handleCommand`
/// dispatches to them once a subclass's own `handleCommand` has declined the command, so
/// a hand-written arm, or a NotImplemented override, still takes precedence.
@attached(peer, names: arbitrary)
public macro OcaDeviceMethod(
  _ methodID: String,
  name: String,
  access: OcaDeviceMethodAccess = .write,
  parameterNames: [String]? = nil,
  resultNames: [String]? = nil
) = #externalMacro(module: "SwiftOCAMacros", type: "OcaDeviceMethodMacro")

/// The raw form, for a method that takes the `Ocp1Command` itself and returns the
/// `Ocp1Response`: it decodes, checks access and encodes for itself, as a `handleCommand`
/// arm does. `parameters` and `result` describe it for introspection only.
///
///     @OcaDeviceMethod("3.27", name: "ApplyPatch", parameters: OcaApplyPatchParameters.self)
///     func applyPatch(_ command: Ocp1Command, from controller: any OcaController) async throws -> Ocp1Response
@attached(peer, names: arbitrary)
public macro OcaDeviceMethod(
  _ methodID: String,
  name: String,
  parameters: (any (Decodable & Sendable).Type)? = nil,
  parameterNames: [String]? = nil,
  result: (any (Encodable & Sendable).Type)? = nil,
  resultNames: [String]? = nil
) = #externalMacro(module: "SwiftOCAMacros", type: "OcaDeviceMethodMacro")

/// Gives a device class its `deviceMethods` table: its parent's, then one entry for each
/// `@OcaDeviceMethod` method declared in the class body.
@attached(member, names: named(deviceMethods))
public macro OcaDeviceMethods() = #externalMacro(
  module: "SwiftOCAMacros",
  type: "OcaDeviceMethodsMacro"
)

/// The lock check made before a method runs, with the command, so that a class's
/// `ensureReadable` and `ensureWritable` overrides see which method it is.
public enum OcaDeviceMethodAccess: Sendable {
  case read
  case write
  /// the method checks for itself, as the lock methods do
  case none
}

/// One parameter, or one result, of a device method.
public struct OcaDeviceMethodParameterDescription: Sendable {
  /// The OCP.2 name.
  public let name: String
  public let type: any (Codable & Sendable).Type
}

/// What a device class declares about one of its methods, and how to call it. Built by
/// `@OcaDeviceMethod`; a class can also build its own and list it in `deviceMethods`.
public struct OcaDeviceMethodDescription: Sendable {
  public typealias Handler = @OcaDevice @Sendable (
    OcaRoot,
    Ocp1Command,
    any OcaController
  ) async throws -> Ocp1Response

  public let methodID: OcaMethodID
  /// The model's name of the method.
  public let name: String
  /// The parameters a record's fields, else the one parameter. Empty for a raw method
  /// that does not describe itself.
  public let parameters: [OcaDeviceMethodParameterDescription]
  /// Likewise for the response.
  public let results: [OcaDeviceMethodParameterDescription]
  let handle: Handler

  private init(
    _ methodID: OcaMethodID,
    name: String,
    parameters: [OcaDeviceMethodParameterDescription],
    results: [OcaDeviceMethodParameterDescription],
    handle: @escaping Handler
  ) {
    self.methodID = methodID
    self.name = name
    self.parameters = parameters
    self.results = results
    self.handle = handle
  }

  // MARK: typed methods

  public init<Object: OcaRoot, Parameters: Decodable & Sendable, Result: Encodable & Sendable>(
    _ methodID: OcaMethodID,
    name: String,
    access: OcaDeviceMethodAccess,
    parameters: Parameters.Type,
    parameterNames: [String],
    resultNames: [String]? = nil,
    _ body: @escaping @OcaDevice @Sendable (Object, Parameters, any OcaController) async throws
      -> Result
  ) {
    let names = parameterNames.map(Ocp2Naming.wireName)
    self.init(
      methodID,
      name: name,
      parameters: Self.describe(Parameters.self, names: names, of: name),
      results: Self.describe(Result.self, names: resultNames, of: name)
    ) { object, command, controller in
      let object = try object.cast(to: Object.self)
      let parameters: Parameters = try Object.decodeCommand(command, names: names)
      try await object.ensureAccess(access, by: controller, command: command)
      let result = try await body(object, parameters, controller)
      return try controller.encodeResponse(result, names: resultNames)
    }
  }

  public init<Object: OcaRoot, Parameters: Decodable & Sendable>(
    _ methodID: OcaMethodID,
    name: String,
    access: OcaDeviceMethodAccess,
    parameters: Parameters.Type,
    parameterNames: [String],
    _ body: @escaping @OcaDevice @Sendable (Object, Parameters, any OcaController) async throws
      -> Void
  ) {
    let names = parameterNames.map(Ocp2Naming.wireName)
    self.init(
      methodID,
      name: name,
      parameters: Self.describe(Parameters.self, names: names, of: name),
      results: []
    ) { object, command, controller in
      let object = try object.cast(to: Object.self)
      let parameters: Parameters = try Object.decodeCommand(command, names: names)
      try await object.ensureAccess(access, by: controller, command: command)
      try await body(object, parameters, controller)
      return Ocp1Response()
    }
  }

  public init<Object: OcaRoot, Result: Encodable & Sendable>(
    _ methodID: OcaMethodID,
    name: String,
    access: OcaDeviceMethodAccess,
    resultNames: [String]? = nil,
    _ body: @escaping @OcaDevice @Sendable (Object, any OcaController) async throws -> Result
  ) {
    self.init(
      methodID,
      name: name,
      parameters: [],
      results: Self.describe(Result.self, names: resultNames, of: name)
    ) { object, command, controller in
      let object = try object.cast(to: Object.self)
      try object.decodeNullCommand(command)
      try await object.ensureAccess(access, by: controller, command: command)
      let result = try await body(object, controller)
      return try controller.encodeResponse(result, names: resultNames)
    }
  }

  public init<Object: OcaRoot>(
    _ methodID: OcaMethodID,
    name: String,
    access: OcaDeviceMethodAccess,
    _ body: @escaping @OcaDevice @Sendable (Object, any OcaController) async throws -> Void
  ) {
    self.init(methodID, name: name, parameters: [], results: []) { object, command, controller in
      let object = try object.cast(to: Object.self)
      try object.decodeNullCommand(command)
      try await object.ensureAccess(access, by: controller, command: command)
      try await body(object, controller)
      return Ocp1Response()
    }
  }

  // MARK: raw methods

  public init<Object: OcaRoot>(
    _ methodID: OcaMethodID,
    name: String,
    parameters: (any (Decodable & Sendable).Type)? = nil,
    parameterNames: [String]? = nil,
    result: (any (Encodable & Sendable).Type)? = nil,
    resultNames: [String]? = nil,
    _ body: @escaping @OcaDevice @Sendable (Object, Ocp1Command, any OcaController) async throws
      -> Ocp1Response
  ) {
    self.init(
      methodID,
      name: name,
      parameters: parameters.map { Self.describe($0, names: parameterNames, of: name) } ?? [],
      results: result.map { Self.describe($0, names: resultNames, of: name) } ?? []
    ) { object, command, controller in
      try await body(try object.cast(to: Object.self), command, controller)
    }
  }

  /// A parameter record describes one parameter per field, named by `names` then by its
  /// fields; any other type is the one parameter, named by `names` or left unnamed.
  private static func describe(
    _ type: Any.Type,
    names: [String]?,
    of method: String
  ) -> [OcaDeviceMethodParameterDescription] {
    let fields: [(name: String, type: Any.Type)] = if type is OcaParametersReflectable.Type {
      Ocp2Naming.fields(of: type)
    } else {
      [(Ocp2Naming.unnamedParameter, type)]
    }
    let names = Ocp2Naming.parameterNames(explicit: names, fieldNames: fields.map(\.name))
    return zip(names, fields).map { name, field in
      guard let type = erasedCast(field.type, to: DescribedType.self) else {
        preconditionFailure("\(method)'s \(name) is a \(field.type), which is not Codable & Sendable")
      }
      return OcaDeviceMethodParameterDescription(name: name, type: type)
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

private extension OcaRoot {
  nonisolated func cast<Object: OcaRoot>(to _: Object.Type) throws -> Object {
    guard let object = self as? Object else {
      throw Ocp1Error.status(.processingFailed)
    }
    return object
  }

  func ensureAccess(
    _ access: OcaDeviceMethodAccess,
    by controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    switch access {
    case .read:
      try await ensureReadable(by: controller, command: command)
    case .write:
      try await ensureWritable(by: controller, command: command)
    case .none:
      break
    }
  }
}

/// Each class's table by method ID, built once per class. A subclass's entry for an ID
/// replaces its parent's, as the subclass's come later in `deviceMethods`.
@OcaDevice
private var deviceMethodTables = [ObjectIdentifier: [OcaMethodID: OcaDeviceMethodDescription]]()

extension OcaRoot {
  class func deviceMethod(for methodID: OcaMethodID) -> OcaDeviceMethodDescription? {
    let key = ObjectIdentifier(self)
    if let table = deviceMethodTables[key] {
      return table[methodID]
    }
    let table = Dictionary(deviceMethods.map { ($0.methodID, $0) }) { _, last in last }
    deviceMethodTables[key] = table
    return table[methodID]
  }
}
