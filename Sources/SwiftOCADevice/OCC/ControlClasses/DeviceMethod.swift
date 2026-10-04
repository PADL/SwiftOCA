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

/// Declares a method of a device class to be the OCA method the client declares as
/// `method` (an `OcaMethodDescription`), so its ID, name and OCP.2 names are stated once,
/// in SwiftOCA. Put it on the method that does the work. That method takes the OCA
/// parameters as its own arguments, named as the description's `Parameters` record names
/// its fields, with the controller as one more (`from controller: any OcaController`),
/// and returns the description's `Result`:
///
///     @OcaDeviceMethod(SwiftOCA.OcaWorker.setPortName, access: .write)
///     open func setPortName(_ id: OcaPortID, _ name: OcaString, from controller: any OcaController) throws
///
/// The expansion reads `parameters.id` and `parameters.name` off the record, so an
/// argument whose name or type is not a field of it is a compile error there. A method
/// may instead take the record itself as its one argument, or the one parameter of a
/// description that has one; the compiler then checks that type against the description's.
/// The result is checked either way. `access` is the lock check made before the method
/// runs: `.read` for a getter, `.write` for a mutator, `.none` for one that checks for
/// itself. Left out, it follows the method's name: `get`, `find`, `is` and `has` read;
/// `set`, `add`, `delete`, `remove`, `clear`, `reset`, `apply`, `construct`, `duplicate`,
/// `link`, `unlink`, `attach`, `detach`, `configure`, `start`, `stop`, `begin`, `end`,
/// `abort`, `read`, `write`, `open` and `close` write; any other first word is a compile
/// error until `access` is stated. The call goes through the object, so a subclass's
/// override of an `open` method is what answers.
///
/// The class lists its methods with `@OcaDeviceMethods`, and `OcaRoot.handleCommand`
/// dispatches to them once a subclass's own `handleCommand` has declined the command, so
/// a hand-written arm, or a NotImplemented override, still takes precedence.
@attached(peer, names: prefixed(_ocaDeviceMethod_))
public macro OcaDeviceMethod<Parameters, Result>(
  _ method: OcaMethodDescription<Parameters, Result>,
  access: OcaDeviceMethodAccess? = nil
) = #externalMacro(module: "SwiftOCAMacros", type: "OcaDeviceMethodMacro")

/// The raw form, for a method that takes the `Ocp1Command` itself and returns the
/// `Ocp1Response`: it decodes, checks access and encodes for itself, as a `handleCommand`
/// arm does.
@attached(peer, names: prefixed(_ocaDeviceMethod_))
public macro OcaDeviceMethod<Parameters, Result>(
  _ method: OcaMethodDescription<Parameters, Result>
) = #externalMacro(module: "SwiftOCAMacros", type: "OcaDeviceMethodMacro")

/// The form for a method the client has no descriptor for yet: the OCA method `methodID`,
/// named `name` in the model. The method's own parameters are the OCA parameters, in
/// order, with the controller as one more argument; its result, if any, is the response.
///
///     @OcaDeviceMethod("2.6", name: "GetPortName", access: .read, resultNames: ["Name"])
///     func getPortName(_ portID: OcaPortID, from controller: any OcaController) throws -> OcaString
///
/// Where SwiftOCA already has a parameters struct for the method (`OcaGetPathParameters`,
/// `OcaWorker.SetPortNameParameters`, ...) the method takes it as its one parameter, so the
/// client and the device share the type; only where none exists does the macro declare a
/// record for several parameters, beside the method. `parameterNames` and `resultNames`
/// give the OCP.2 names where the model spells them differently from the Swift names.
@attached(peer, names: prefixed(_ocaDeviceMethod_), prefixed(_ocaDeviceMethodParameters_))
public macro OcaDeviceMethod(
  _ methodID: String,
  name: String,
  access: OcaDeviceMethodAccess? = nil,
  parameterNames: [String]? = nil,
  resultNames: [String]? = nil
) = #externalMacro(module: "SwiftOCAMacros", type: "OcaDeviceMethodMacro")

/// The raw form with the description's parts given here. `parameters` and `result`
/// describe it for introspection only.
///
///     @OcaDeviceMethod("3.27", name: "ApplyPatch", parameters: OcaApplyPatchParameters.self)
///     func applyPatch(_ command: Ocp1Command, from controller: any OcaController) async throws -> Ocp1Response
@attached(peer, names: prefixed(_ocaDeviceMethod_))
public macro OcaDeviceMethod(
  _ methodID: String,
  name: String,
  parameters: (any (Codable & Sendable).Type)? = nil,
  parameterNames: [String]? = nil,
  result: (any (Codable & Sendable).Type)? = nil,
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

/// What a device class declares about one of its methods, and how to call it: the
/// method's description, shared with the client, and the dispatch. Built by
/// `@OcaDeviceMethod`; a class can also build its own and list it in `deviceMethods`.
public struct OcaDeviceMethodDescription: Sendable {
  public typealias Handler = @OcaDevice @Sendable (
    OcaRoot,
    Ocp1Command,
    any OcaController
  ) async throws -> Ocp1Response

  /// The method as the model declares it. Empty of parameters for a raw method that
  /// does not describe itself.
  public let method: OcaAnyMethodDescription
  let handle: Handler

  public var methodID: OcaMethodID { method.methodID }
  public var name: String { method.name }
  public var parameters: [OcaMethodParameterDescription] { method.parameters }
  public var results: [OcaMethodParameterDescription] { method.results }

  /// What `@OcaDeviceMethod` writes for a typed method: cast the object, cast the
  /// decoded parameters (`()` when there are none) and call; the result, or nil for none.
  /// Decoding, the lock check and encoding are done once here, not per method.
  public typealias Body = @OcaDevice @Sendable (
    OcaRoot,
    Any,
    any OcaController
  ) async throws -> (any Encodable)?

  /// Likewise for a raw method, which does the decoding, checking and encoding itself.
  public typealias RawBody = @OcaDevice @Sendable (
    OcaRoot,
    Ocp1Command,
    any OcaController
  ) async throws -> Ocp1Response

  /// The typed form, from the shared description. `parameters` and `result` are the
  /// method's own types, so the compiler checks them against the description's.
  public init<Parameters, Result>(
    _ method: OcaMethodDescription<Parameters, Result>,
    access: OcaDeviceMethodAccess,
    parameters _: Parameters.Type,
    result _: Result.Type,
    _ body: @escaping Body
  ) {
    self.init(method.erased, access: access, body)
  }

  /// The typed form taking the description's parameters as separate arguments: the
  /// expansion's field accesses are the check on them, the result is checked here.
  public init<Parameters, Result>(
    _ method: OcaMethodDescription<Parameters, Result>,
    access: OcaDeviceMethodAccess,
    result _: Result.Type,
    _ body: @escaping Body
  ) {
    self.init(method.erased, access: access, body)
  }

  /// The raw form, from the shared description.
  public init<Parameters, Result>(
    _ method: OcaMethodDescription<Parameters, Result>,
    _ body: @escaping RawBody
  ) {
    self.init(method.erased, body)
  }

  /// The typed form with the description's parts given here, for a method the client
  /// has no descriptor for. `argumentNames` are the Swift names of the method's
  /// parameters, which name a single value on OCP.2 unless `parameterNames` does; a
  /// record's fields name themselves.
  public init(
    _ methodID: OcaMethodID,
    name: String,
    access: OcaDeviceMethodAccess,
    parameters: (any (Codable & Sendable).Type)? = nil,
    argumentNames: [String] = [],
    parameterNames: [String]? = nil,
    result: (any (Codable & Sendable).Type)? = nil,
    resultNames: [String]? = nil,
    _ body: @escaping Body
  ) {
    self.init(
      OcaAnyMethodDescription(
        methodID: methodID,
        name: name,
        parametersType: parameters,
        resultType: result,
        parameterNames: parameters.flatMap { Self.names(of: $0, argumentNames, parameterNames) },
        resultNames: resultNames
      ),
      access: access,
      body
    )
  }

  public init(
    _ methodID: OcaMethodID,
    name: String,
    parameters: (any (Codable & Sendable).Type)? = nil,
    parameterNames: [String]? = nil,
    result: (any (Codable & Sendable).Type)? = nil,
    resultNames: [String]? = nil,
    _ body: @escaping RawBody
  ) {
    self.init(
      OcaAnyMethodDescription(
        methodID: methodID,
        name: name,
        parametersType: parameters,
        resultType: result,
        parameterNames: parameterNames,
        resultNames: resultNames
      ),
      body
    )
  }

  // out of line, so a site is a call and not a copy of the closure's construction
  @inline(never)
  private init(_ method: OcaAnyMethodDescription, _ body: @escaping RawBody) {
    self.method = method
    handle = { object, command, controller in
      try await body(object, command, controller)
    }
  }

  @inline(never)
  private init(
    _ method: OcaAnyMethodDescription,
    access: OcaDeviceMethodAccess,
    _ body: @escaping Body
  ) {
    self.method = method
    handle = { object, command, controller in
      let decoded: Any = if let parameters = method.parametersType {
        try parameters._decodeDeviceCommand(command, names: method.parameterNames)
      } else {
        try object.decodeNullCommand(command)
      }
      try await object.ensureAccess(access, by: controller, command: command)
      guard let result = try await body(object, decoded, controller) else {
        return Ocp1Response()
      }
      return try result._encodeDeviceResponse(for: controller, names: method.resultNames)
    }
  }

  // MARK: typed conveniences, for a descriptor written by hand

  public init<Object: OcaRoot, Parameters: Codable & Sendable, Result: Codable & Sendable>(
    _ methodID: OcaMethodID,
    name: String,
    access: OcaDeviceMethodAccess,
    parameters: Parameters.Type,
    argumentNames: [String],
    parameterNames: [String]? = nil,
    resultNames: [String]? = nil,
    _ body: @escaping @OcaDevice @Sendable (Object, Parameters, any OcaController) async throws
      -> Result
  ) {
    self.init(
      methodID,
      name: name,
      access: access,
      parameters: parameters,
      argumentNames: argumentNames,
      parameterNames: parameterNames,
      result: Result.self,
      resultNames: resultNames
    ) { object, parameters, controller in
      try await body(object as! Object, parameters as! Parameters, controller)
    }
  }

  public init<Object: OcaRoot, Parameters: Codable & Sendable>(
    _ methodID: OcaMethodID,
    name: String,
    access: OcaDeviceMethodAccess,
    parameters: Parameters.Type,
    argumentNames: [String],
    parameterNames: [String]? = nil,
    _ body: @escaping @OcaDevice @Sendable (Object, Parameters, any OcaController) async throws
      -> Void
  ) {
    self.init(
      methodID,
      name: name,
      access: access,
      parameters: parameters,
      argumentNames: argumentNames,
      parameterNames: parameterNames
    ) { object, parameters, controller in
      try await body(object as! Object, parameters as! Parameters, controller)
      return nil
    }
  }

  public init<Object: OcaRoot, Result: Codable & Sendable>(
    _ methodID: OcaMethodID,
    name: String,
    access: OcaDeviceMethodAccess,
    resultNames: [String]? = nil,
    _ body: @escaping @OcaDevice @Sendable (Object, any OcaController) async throws -> Result
  ) {
    self.init(
      methodID,
      name: name,
      access: access,
      result: Result.self,
      resultNames: resultNames
    ) { object, _, controller in
      try await body(object as! Object, controller)
    }
  }

  public init<Object: OcaRoot>(
    _ methodID: OcaMethodID,
    name: String,
    access: OcaDeviceMethodAccess,
    _ body: @escaping @OcaDevice @Sendable (Object, any OcaController) async throws -> Void
  ) {
    self.init(methodID, name: name, access: access) { object, _, controller in
      try await body(object as! Object, controller)
      return nil
    }
  }

  /// The OCP.2 names a record's fields answer to: explicit names, else none, as a record
  /// names its own fields; a single value is named by the method's argument.
  private static func names(
    of type: Any.Type,
    _ argumentNames: [String],
    _ parameterNames: [String]?
  ) -> [String]? {
    if let parameterNames {
      return parameterNames
    }
    return type is OcaParametersReflectable.Type ? nil : argumentNames.map(Ocp2Naming.wireName)
  }
}

/// Opened through the existential, so there is one decoder and one encoder for every
/// method rather than one specialised per parameter and result type.
private extension Decodable {
  @inline(never)
  static func _decodeDeviceCommand(_ command: Ocp1Command, names: [String]?) throws -> Any {
    let parameters: Self = try OcaRoot.decodeCommand(command, names: names)
    return parameters
  }
}

private extension Encodable {
  @inline(never)
  func _encodeDeviceResponse(
    for controller: any OcaController,
    names: [String]?
  ) throws -> Ocp1Response {
    try controller.encodeResponse(self, names: names)
  }
}

private extension OcaRoot {
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
