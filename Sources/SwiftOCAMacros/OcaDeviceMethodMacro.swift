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
/// class's `deviceMethods` table lists, and to a parameter record when the method
/// takes more than one OCA parameter.
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
        "@OcaDeviceMethod needs its method ID as a string literal, such as \"2.7\""
      )
    }
    let method = try DeviceMethod(function)

    var arguments = ["OcaMethodID(\"\(attribute.methodID)\")"]
    arguments.append("name: \(attribute.argument("name")?.trimmedDescription ?? "\"\"")")
    var declarations = [DeclSyntax]()
    let closureParameters: String

    if method.isRaw {
      for label in ["parameters", "parameterNames", "result", "resultNames"] {
        if let value = attribute.argument(label) {
          arguments.append("\(label): \(value.trimmedDescription)")
        }
      }
      closureParameters = "object: Self, command: Ocp1Command, controller: any OcaController"
    } else {
      guard let access = attribute.argument("access") else {
        throw MacroExpansionErrorMessage("@OcaDeviceMethod needs access: .read, .write or .none")
      }
      arguments.append("access: \(access.trimmedDescription)")
      var parameterList = "object: Self"
      if let parametersType = method.parametersType {
        if method.parameters.count > 1 {
          declarations.append(method.parameterRecord)
        }
        arguments.append("parameters: \(parametersType).self")
        let names = attribute.argument("parameterNames")?.trimmedDescription
          ?? "[\(method.parameters.map { "\"\($0.name)\"" }.joined(separator: ", "))]"
        arguments.append("parameterNames: \(names)")
        parameterList += ", parameters: \(parametersType)"
      }
      if let resultNames = attribute.argument("resultNames") {
        arguments.append("resultNames: \(resultNames.trimmedDescription)")
      }
      closureParameters = parameterList + ", controller: any OcaController"
    }

    declarations.append(
      """
      static var \(raw: attribute.descriptorName): OcaDeviceMethodDescription {
        OcaDeviceMethodDescription(
          \(raw: arguments.joined(separator: ",\n    "))
        ) { (\(raw: closureParameters)) -> \(raw: method.closureResultType) in
          \(raw: method.call)
        }
      }
      """
    )
    return declarations
  }
}

/// `@OcaDeviceMethods` on a device class: its `deviceMethods` table, listing the
/// descriptor of every `@OcaDeviceMethod` method in the class body after its parent's.
public struct OcaDeviceMethodsMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
      throw MacroExpansionErrorMessage("@OcaDeviceMethods can only be applied to a class")
    }
    let descriptors = classDecl.memberBlock.members.compactMap { member -> String? in
      guard let function = member.decl.as(FunctionDeclSyntax.self) else { return nil }
      return OcaDeviceMethodAttribute.on(function)?.descriptorName
    }
    guard !descriptors.isEmpty else {
      throw MacroExpansionErrorMessage("@OcaDeviceMethods needs at least one @OcaDeviceMethod method")
    }
    let access = classDecl.modifiers.lazy
      .map(\.name.text)
      .first { ["open", "public", "package"].contains($0) }
      .map { $0 + " " } ?? ""

    return [
      """
      override \(raw: access)class var deviceMethods: [OcaDeviceMethodDescription] {
        super.deviceMethods + [\(raw: descriptors.joined(separator: ", "))]
      }
      """,
    ]
  }
}

/// The `@OcaDeviceMethod` attribute as written, read by both macros.
struct OcaDeviceMethodAttribute {
  let methodID: String
  private let arguments: LabeledExprListSyntax

  init?(_ attribute: AttributeSyntax) {
    guard case let .argumentList(arguments) = attribute.arguments,
          let first = arguments.first, first.label == nil,
          let methodID = first.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
    else {
      return nil
    }
    self.methodID = methodID
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

  /// `"2.7"` becomes `_ocaDeviceMethod_2_7`, by which the table names the descriptor.
  var descriptorName: String {
    "_ocaDeviceMethod_" + methodID.split(separator: ".").joined(separator: "_")
  }

  func argument(_ label: String) -> ExprSyntax? {
    arguments.first { $0.label?.text == label }?.expression
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
    guard let controller = all.firstIndex(where: {
      ["any OcaController", "OcaController", "(any OcaController)"].contains($0.type)
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
      } else if parameters.count == 1 {
        isRaw ? "command" : "parameters"
      } else {
        "parameters.\(parameter.name)"
      }
      return parameter.label.map { "\($0): \(value)" } ?? value
    }
  }

  /// The record decoded for several parameters, else the one parameter's type.
  var parametersType: String? {
    switch parameters.count {
    case 0: nil
    case 1: parameters[0].type
    default: "_" + function.name.text.prefix(1).uppercased() + function.name.text.dropFirst() +
      "Parameters"
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

  var closureResultType: String {
    function.signature.returnClause?.type.trimmedDescription ?? "Void"
  }

  var call: String {
    "\(callPrefix)object.\(function.name.text)(\(arguments.joined(separator: ", ")))"
  }
}
