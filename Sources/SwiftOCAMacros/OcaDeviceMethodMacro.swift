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

import SwiftSyntax
import SwiftSyntaxMacros

/// `@OcaDeviceMethod` on a method of a device class. Expands to a descriptor the
/// class's `deviceMethods` table lists, and, in the form that spells the descriptor
/// itself, to a parameter record when the method takes more than one OCA parameter.
public struct OcaDeviceMethodMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let function = declaration.as(FunctionDeclSyntax.self) else {
      throw MacroExpansionErrorMessage("@OcaDeviceMethod can only be applied to a method")
    }
    guard let attribute = OcaDeviceMethodAttribute(node) else {
      throw MacroExpansionErrorMessage(
        "@OcaDeviceMethod needs the client's descriptor, or its method ID as a string literal"
      )
    }
    let method = try DeviceMethod(function)

    var arguments = [String]()
    var declarations = [DeclSyntax]()
    var body = [String]()
    let closureParameters: String

    if let descriptor = attribute.descriptor {
      // the shared form: the descriptor comes from SwiftOCA, only the dispatch is here
      for label in ["name", "parameters", "parameterNames", "result", "resultNames"]
        where attribute.argument(label) != nil
      {
        throw MacroExpansionErrorMessage("the descriptor gives the method its \(label)")
      }
      arguments.append(descriptor.trimmedDescription)
      if method.isRaw {
        closureParameters = "object, command, controller"
      } else {
        arguments.append("access: \(try method.access(attribute))")
        if method.parameters.count > 1 {
          // the descriptor's Parameters, taken apart by the method's argument names
          body.append("let parameters = \(descriptor.trimmedDescription).parameters(parameters)")
        } else {
          arguments.append("parameters: \(method.parametersType ?? "Void").self")
        }
        arguments.append("result: \(method.resultType ?? "Void").self")
        closureParameters = method.parametersType == nil
          ? "object, _, controller"
          : "object, parameters, controller"
      }
      // a closure of more than one statement returns explicitly
      body.append((method.resultType != nil && !body.isEmpty ? "return " : "") + method.call)
      if !method.isRaw, method.resultType == nil {
        body.append("return nil")
      }
    } else if method.isRaw {
      arguments += attribute.identity
      for label in ["parameters", "parameterNames", "result", "resultNames"] {
        if let value = attribute.argument(label) {
          arguments.append("\(label): \(value.trimmedDescription)")
        }
      }
      closureParameters = "object, command, controller"
      body.append(method.call)
    } else {
      arguments += attribute.identity
      arguments.append("access: \(try method.access(attribute))")
      if let parametersType = method.parametersType {
        if method.parameters.count > 1 {
          declarations.append(method.parameterRecord)
          body.append("let parameters = parameters as! \(parametersType)")
        }
        arguments.append("parameters: \(parametersType).self")
        let names = method.parameters.map { "\"\($0.name)\"" }.joined(separator: ", ")
        arguments.append("argumentNames: [\(names)]")
        if let parameterNames = attribute.argument("parameterNames") {
          arguments.append("parameterNames: \(parameterNames.trimmedDescription)")
        }
      }
      if let resultType = method.resultType {
        arguments.append("result: \(resultType).self")
        if let resultNames = attribute.argument("resultNames") {
          arguments.append("resultNames: \(resultNames.trimmedDescription)")
        }
      }
      closureParameters = method.parametersType == nil
        ? "object, _, controller"
        : "object, parameters, controller"
      body.append((method.resultType != nil && !body.isEmpty ? "return " : "") + method.call)
      if method.resultType == nil {
        body.append("return nil")
      }
    }

    declarations.append(
      """
      static func \(raw: method.descriptorName)(_: \(raw: method.selectorType).Type) -> OcaDeviceMethodDescriptor {
        OcaDeviceMethodDescriptor(
          \(raw: arguments.joined(separator: ",\n    "))
        ) { \(raw: closureParameters) in
          \(raw: body.joined(separator: "\n    "))
        }
      }
      """
    )
    return declarations
  }
}

/// `@OcaDeviceClass` on a device class: its `deviceMethods` table, listing the
/// descriptor of every `@OcaDeviceMethod` method in the class body after its parent's,
/// and its `devicePropertyKeyPaths` table, giving the storage of every device property
/// declared in the class body, by its name, after its parent's.
public struct OcaDeviceClassMacro: MemberMacro {
  /// The device property wrappers, by the names a property is declared with.
  static let propertyWrappers: Set<String> = [
    "OcaDeviceProperty", "OcaBoundedDeviceProperty", "OcaVectorDeviceProperty",
  ]

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
      throw MacroExpansionErrorMessage("@OcaDeviceClass can only be applied to a class")
    }
    let className = classDecl.name.text
    func methods(in members: MemberBlockItemListSyntax) -> [String] {
      members.compactMap { member in
        guard let function = member.decl.as(FunctionDeclSyntax.self),
              OcaDeviceMethodAttribute.on(function) != nil,
              let method = try? DeviceMethod(function)
        else {
          return nil
        }
        return "\(method.descriptorName)(\(method.selectorType).self)"
      }
    }
    let methodTable = MemberTable(classDecl, methods)
    let propertyTable = MemberTable(classDecl) {
      MemberTable.propertyKeyPaths(in: $0, of: className, wrappers: propertyWrappers)
    }
    guard Set(methodTable.entries).count == methodTable.entries.count else {
      throw MacroExpansionErrorMessage("@OcaDeviceMethod methods need distinct names")
    }
    let access = classDecl.modifiers.lazy
      .map(\.name.text)
      .first { ["open", "public", "package"].contains($0) }
      .map { $0 + " " } ?? ""

    guard !methodTable.entries.isEmpty || !propertyTable.entries.isEmpty else {
      throw MacroExpansionErrorMessage(
        "@OcaDeviceClass needs at least one @OcaDeviceMethod method or device property"
      )
    }
    var members = [DeclSyntax]()
    if !methodTable.entries.isEmpty {
      members.append(
        """
        override \(raw: access)class var deviceMethods: [OcaDeviceMethodDescriptor] {
          var methods = super.deviceMethods
          \(raw: methodTable.statements(appending: { "methods += [\($0)]" }))
          return methods
        }
        """
      )
    }
    let typeNames = MemberTable(classDecl) {
      MemberTable.propertyTypeNames(in: $0, of: classDecl, wrappers: propertyWrappers)
    }
    if !typeNames.entries.isEmpty {
      members.append(
        """
        override \(raw: access)class var devicePropertyTypeNames: [String: String] {
          var typeNames = super.devicePropertyTypeNames
          \(raw: typeNames.statements(appending: { "typeNames.merge([\($0)]) { _, new in new }" }))
          return typeNames
        }
        """
      )
    }
    let deprecated = MemberTable(classDecl) {
      MemberTable.deprecatedProperties(in: $0, wrappers: propertyWrappers)
    }
    if !deprecated.entries.isEmpty {
      members.append(
        """
        override \(raw: access)class var devicePropertyDeprecations: [String: OcaPropertyDeprecation] {
          var deprecations = super.devicePropertyDeprecations
          \(raw: deprecated.statements(appending: { "deprecations.merge([\($0)]) { _, new in new }" }))
          return deprecations
        }
        """
      )
    }
    let accessorNames = MemberTable(classDecl) {
      MemberTable.accessorNames(in: $0, wrappers: propertyWrappers)
    }
    if !accessorNames.entries.isEmpty {
      members.append(
        """
        override \(raw: access)class var devicePropertyAccessorNames: [String: OcaPropertyAccessorNames] {
          var names = super.devicePropertyAccessorNames
          \(raw: accessorNames.statements(appending: { "names.merge([\($0)]) { _, new in new }" }))
          return names
        }
        """
      )
    }
    if !propertyTable.entries.isEmpty {
      members.append(
        """
        override \(raw: access)class var devicePropertyKeyPaths: [String: AnyKeyPath] {
          var keyPaths = super.devicePropertyKeyPaths
          \(raw: propertyTable.statements(appending: { "keyPaths.merge([\($0)]) { _, new in new }" }))
          return keyPaths
        }
        """
      )
    }
    return members
  }
}

/// The `@OcaDeviceMethod` attribute as written, read by both macros: the client's
/// descriptor, or the method ID with the descriptor's parts as further arguments.
struct OcaDeviceMethodAttribute {
  let methodID: String?
  let descriptor: ExprSyntax?
  private let arguments: LabeledExprListSyntax

  init?(_ attribute: AttributeSyntax) {
    guard case let .argumentList(arguments) = attribute.arguments,
          let first = arguments.first, first.label == nil
    else {
      return nil
    }
    methodID = first.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
    descriptor = methodID == nil ? first.expression : nil
    self.arguments = arguments
  }

  static func on(_ function: FunctionDeclSyntax) -> Self? {
    for case let .attribute(attribute) in function.attributes
      where attribute.attributeName.trimmedDescription.split(separator: ".").last == "OcaDeviceMethod"
    {
      return Self(attribute)
    }
    return nil
  }

  func argument(_ label: String) -> ExprSyntax? {
    arguments.first { $0.label?.text == label }?.expression
  }

  /// The ID and name arguments of the form that spells them.
  var identity: [String] {
    [
      "OcaMethodID(\"\(methodID!)\")",
      "name: \(argument("name")?.trimmedDescription ?? "\"\"")",
    ]
  }
}

/// A method's signature, read as an OCA method: the controller parameter, the OCA
/// parameters around it, and whether it takes the raw command instead.
private struct DeviceMethod {
  struct Parameter {
    let label: String?
    let name: String
    let type: String
  }

  let function: FunctionDeclSyntax
  let parameters: [Parameter]
  let isRaw: Bool
  private let arguments: [String]
  private let callPrefix: String

  init(_ function: FunctionDeclSyntax) throws {
    self.function = function
    let all = function.signature.parameterClause.parameters.map { parameter in
      Parameter(
        label: parameter.firstName.text == "_" ? nil : parameter.firstName.text,
        name: (parameter.secondName ?? parameter.firstName).text,
        type: parameter.type.trimmedDescription
      )
    }
    // an optional controller is a hook that is also called from within the device
    guard let controller = all.firstIndex(where: {
      ["any OcaController", "OcaController", "(any OcaController)", "OcaController?", "(any OcaController)?"]
        .contains($0.type)
    }) else {
      throw MacroExpansionErrorMessage(
        "an @OcaDeviceMethod method takes the controller, as `from controller: any OcaController`"
      )
    }
    let parameters = all.enumerated().filter { $0.offset != controller }.map(\.element)
    let isRaw = parameters.count == 1 && parameters[0].type == "Ocp1Command"
    if isRaw, function.signature.returnClause?.type.trimmedDescription != "Ocp1Response" {
      throw MacroExpansionErrorMessage("a method taking the Ocp1Command returns the Ocp1Response")
    }
    self.parameters = parameters
    self.isRaw = isRaw

    let effects = function.signature.effectSpecifiers
    callPrefix = (effects?.throwsClause != nil ? "try " : "") +
      (effects?.asyncSpecifier != nil ? "await " : "")
    arguments = all.enumerated().map { offset, parameter in
      let value = if offset == controller {
        "controller"
      } else if isRaw {
        "command"
      } else if parameters.count == 1 {
        "parameters as! \(parameter.type)"
      } else {
        "parameters.\(parameter.name)"
      }
      return parameter.label.map { "\($0): \(value)" } ?? value
    }
  }

  /// The descriptor the table lists, named after the method as the peer name rule
  /// requires, and overloaded on `selectorType` so that a class can answer two methods
  /// with overloads of one Swift name (`setEndpoint(_:userLabel:)`, `setEndpoint(_:channelMap:)`).
  var descriptorName: String { "_ocaDeviceMethod_" + function.name.text }

  /// The method's OCA parameters as a labelled tuple type: `Void` for none, the one type
  /// for one, else `(label: Type, ...)`.
  var selectorType: String {
    switch parameters.count {
    case 0: "Void"
    case 1: parameters[0].type
    default: "(" + parameters.map { ($0.label.map { "\($0): " } ?? "") + $0.type }
      .joined(separator: ", ") + ")"
    }
  }

  /// The record decoded for several parameters, else the one parameter's type.
  var parametersType: String? {
    switch parameters.count {
    case 0: nil
    case 1: parameters[0].type
    default: "_ocaDeviceMethodParameters_" + function.name.text
    }
  }

  var parameterRecord: DeclSyntax {
    let fields = parameters.map { "let \($0.name): \($0.type)" }
    return """
    struct \(raw: parametersType!): OcaParametersReflectable, Sendable {
      \(raw: fields.joined(separator: "\n  "))
    }
    """
  }

  var resultType: String? {
    function.signature.returnClause?.type.trimmedDescription
  }

  private static let readPrefixes = ["get", "find", "is", "has"]
  private static let writePrefixes = [
    "set", "add", "delete", "remove", "clear", "reset", "apply", "construct", "duplicate",
    "link", "unlink", "attach", "detach", "configure", "start", "stop", "begin", "end", "abort",
    "read", "write", "open", "close",
  ]

  /// The lock check: as written, else (or written `.inferred`) from the method's name,
  /// whose first word says whether it reads or writes; a name that says neither must
  /// state it. Only `.read`, `.write` and `.unchecked` reach the descriptor.
  func access(_ attribute: OcaDeviceMethodAttribute) throws -> String {
    if let access = attribute.argument("access"),
       !["inferred", ".inferred", "OcaDeviceMethodAccess.inferred"].contains(access.trimmedDescription)
    {
      return access.trimmedDescription
    }
    let name = function.name.text
    func starts(with prefix: String) -> Bool {
      guard name.hasPrefix(prefix) else { return false }
      let rest = name.dropFirst(prefix.count)
      return rest.isEmpty || rest.first!.isUppercase
    }
    if Self.readPrefixes.contains(where: starts(with:)) { return ".read" }
    if Self.writePrefixes.contains(where: starts(with:)) { return ".write" }
    throw MacroExpansionErrorMessage(
      "@OcaDeviceMethod cannot tell whether '\(name)' reads or writes; state access: .read, .write or .unchecked"
    )
  }

  var call: String {
    "\(callPrefix)(object as! Self).\(function.name.text)(\(arguments.joined(separator: ", ")))"
  }
}
