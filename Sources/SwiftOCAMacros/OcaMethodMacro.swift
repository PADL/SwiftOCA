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

/// `@OcaMethod` on a client method without a body: the body is the one `invoke` of the
/// method's descriptor, `Methods.<name>`, with the arguments as its parameters.
public struct OcaMethodMacro: BodyMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
    in context: some MacroExpansionContext
  ) throws -> [CodeBlockItemSyntax] {
    guard let function = declaration.as(FunctionDeclSyntax.self) else {
      throw MacroExpansionErrorMessage("@OcaMethod can only be applied to a method")
    }
    guard function.body == nil else {
      throw MacroExpansionErrorMessage(
        "@OcaMethod writes the method's body; leave it out, or declare a hand-written method with @OcaMethodDescriptor"
      )
    }
    let effects = function.signature.effectSpecifiers
    guard effects?.asyncSpecifier != nil, effects?.throwsClause != nil else {
      throw MacroExpansionErrorMessage("an @OcaMethod method is 'async throws'")
    }
    guard let attribute = OcaMethodAttribute(node) else {
      throw MacroExpansionErrorMessage("@OcaMethod needs the method ID as a string literal and the model's name")
    }
    let method = try ClientMethod(function)
    var arguments = ["Methods.\(method.name)"]
    switch (method.parameters.count, attribute.parametersType) {
    case (0, nil):
      break
    case (1, nil):
      arguments.append(method.parameters[0].name)
    default:
      // the record the descriptor takes, named or synthesised, built by its field names
      let fields = method.parameters.map { "\($0.name): \($0.name)" }
      arguments.append(".init(\(fields.joined(separator: ", ")))")
    }
    return ["try await invoke(\(raw: arguments.joined(separator: ", ")))"]
  }
}

/// `@OcaMethodDescriptor` on a client method whose body is written by hand: the
/// method's descriptor is declared in `Methods` as for `@OcaMethod`, and nothing else.
public struct OcaMethodDescriptorMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let function = declaration.as(FunctionDeclSyntax.self) else {
      throw MacroExpansionErrorMessage("@OcaMethodDescriptor can only be applied to a method")
    }
    guard function.body != nil else {
      throw MacroExpansionErrorMessage("a method without a body takes @OcaMethod, which writes it")
    }
    guard OcaMethodAttribute(node) != nil else {
      throw MacroExpansionErrorMessage(
        "@OcaMethodDescriptor needs the method ID as a string literal and the model's name"
      )
    }
    return []
  }
}

/// `@OcaMethods` on a client class: its `Methods` namespace, holding the descriptor of
/// each `@OcaMethod` and `@OcaMethodDescriptor` method in the class body under the
/// method's own name, and the parameter record of any that needs one synthesised; and its
/// `propertyKeyPaths` table, giving the storage of each property declared in the class
/// body, by its name, after its parent's.
public struct OcaMethodsMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
      throw MacroExpansionErrorMessage("@OcaMethods can only be applied to a class")
    }
    let access = classDecl.modifiers.lazy
      .map(\.name.text)
      .first { ["open", "public", "package"].contains($0) }
      .map { ($0 == "open" ? "public" : $0) + " " } ?? ""

    var lines = [String]()
    var names = [String]()
    func declarations(in members: MemberBlockItemListSyntax) throws -> [String] {
      try members.flatMap { member -> [String] in
        guard let function = member.decl.as(FunctionDeclSyntax.self),
              let attribute = OcaMethodAttribute.on(function)
        else {
          return []
        }
        let method = try ClientMethod(function)
        names.append(method.name)
        return method.descriptor(attribute, access: access)
      }
    }
    lines += try declarations(in: classDecl.memberBlock.members)
    for member in classDecl.memberBlock.members {
      guard let block = member.decl.as(IfConfigDeclSyntax.self) else { continue }
      var clauses = [(String, [String])]()
      for clause in block.clauses {
        let members = clause.elements?.as(MemberBlockItemListSyntax.self)
        let condition = clause.condition.map { " " + $0.trimmedDescription } ?? ""
        let declared = try members.map(declarations(in:)) ?? []
        clauses.append((clause.poundKeyword.text + condition, declared))
      }
      guard clauses.contains(where: { !$0.1.isEmpty }) else { continue }
      for (directive, declarations) in clauses {
        lines.append(directive)
        lines += declarations
      }
      lines.append("#endif")
    }
    let className = classDecl.name.text
    let properties = MemberTable(classDecl) {
      MemberTable.propertyKeyPaths(in: $0, of: className, wrappers: propertyWrappers)
    }
    guard !names.isEmpty || !properties.entries.isEmpty else {
      throw MacroExpansionErrorMessage("@OcaMethods needs at least one @OcaMethod method or property")
    }
    if let duplicate = Dictionary(grouping: names) { $0 }.first(where: { $0.value.count > 1 }) {
      throw MacroExpansionErrorMessage(
        "two methods are named '\(duplicate.key)'; each OCA method needs its own name"
      )
    }
    let body = lines.flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false) }
      .map { $0.isEmpty ? "" : "  " + $0 }
    var members = [DeclSyntax]()
    if !names.isEmpty {
      let namespace = [
        "/// The descriptors of the class's methods, each under the method's name.",
        "\(access)enum Methods {",
      ] + body + ["}"]
      members.append(DeclSyntax(stringLiteral: namespace.joined(separator: "\n")))
    }
    if !properties.entries.isEmpty {
      let classAccess = classDecl.modifiers.lazy
        .map(\.name.text)
        .first { ["open", "public", "package"].contains($0) }
        .map { $0 + " " } ?? ""
      // OcaRoot has no parent to extend, which a class body does not say
      let isRoot = className == "OcaRoot"
      let statements = properties.statements(appending: { "keyPaths.merge([\($0)]) { _, new in new }" })
      members.append(
        """
        \(raw: isRoot ? "" : "override ")\(raw: classAccess)class var propertyKeyPaths: [String: AnyKeyPath] {
          var keyPaths\(raw: isRoot ? ": [String: AnyKeyPath] = [:]" : " = super.propertyKeyPaths")
          \(raw: statements)
          return keyPaths
        }
        """
      )
    }
    return members
  }

  /// The client property wrappers, by the names a property is declared with.
  static let propertyWrappers: Set<String> = [
    "OcaProperty", "OcaBoundedProperty", "OcaVectorProperty", "OcaBoundedVectorProperty",
    "OcaListProperty", "OcaList2DProperty", "OcaMapProperty", "OcaMultiMapProperty",
  ]
}

/// The `@OcaMethod` or `@OcaMethodDescriptor` attribute as written.
struct OcaMethodAttribute {
  let methodID: String
  let name: ExprSyntax
  /// The record or value the method takes, where the signature does not say it.
  let parametersType: String?
  /// The result, where the signature does not say it (`@OcaMethodDescriptor` only).
  let resultType: String?
  let parameterNames: ExprSyntax?
  let resultNames: ExprSyntax?

  init?(_ attribute: AttributeSyntax) {
    guard case let .argumentList(arguments) = attribute.arguments,
          let first = arguments.first, first.label == nil,
          let methodID = first.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
          let name = arguments.first(where: { $0.label?.text == "name" })?.expression
    else {
      return nil
    }
    func argument(_ label: String) -> ExprSyntax? {
      arguments.first { $0.label?.text == label }?.expression
    }
    // `Type.self` names the type
    func type(_ label: String) -> String? {
      argument(label).map { expression in
        let text = expression.trimmedDescription
        return text.hasSuffix(".self") ? String(text.dropLast(5)) : text
      }
    }
    self.methodID = methodID
    self.name = name
    parametersType = type("parameters")
    resultType = type("result")
    parameterNames = argument("parameterNames")
    resultNames = argument("resultNames")
  }

  static func on(_ function: FunctionDeclSyntax) -> Self? {
    for case let .attribute(attribute) in function.attributes {
      let name = attribute.attributeName.trimmedDescription.split(separator: ".").last
      if name == "OcaMethod" || name == "OcaMethodDescriptor" {
        return Self(attribute)
      }
    }
    return nil
  }
}

/// A client method's signature, read as an OCA method.
private struct ClientMethod {
  struct Parameter {
    let name: String
    let type: String
  }

  let name: String
  let parameters: [Parameter]
  let resultType: String?

  init(_ function: FunctionDeclSyntax) throws {
    name = function.name.text
    parameters = try function.signature.parameterClause.parameters.map { parameter in
      if parameter.ellipsis != nil || parameter.type.is(AttributedTypeSyntax.self) {
        throw MacroExpansionErrorMessage("an OCA method's parameters are plain values, not variadic or inout")
      }
      return Parameter(
        name: (parameter.secondName ?? parameter.firstName).text,
        type: parameter.type.trimmedDescription
      )
    }
    resultType = function.signature.returnClause?.type.trimmedDescription
  }

  /// The record synthesised for a method of several parameters given no record.
  var recordName: String {
    name.prefix(1).uppercased() + name.dropFirst() + "Parameters"
  }

  func descriptor(_ attribute: OcaMethodAttribute, access: String) -> [String] {
    var declarations = [String]()
    let parametersType: String
    if let type = attribute.parametersType {
      parametersType = type
    } else {
      switch parameters.count {
      case 0:
        parametersType = "Void"
      case 1:
        parametersType = parameters[0].type
      default:
        parametersType = recordName
        let fields = parameters.map { "\(access)let \($0.name): \($0.type)" }
        let arguments = parameters.map { "\($0.name): \($0.type)" }
        let assignments = parameters.map { "self.\($0.name) = \($0.name)" }
        // built in steps, as one expression is too slow for Swift 6.3 to type-check
        var lines = ["\(access)struct \(recordName): OcaParametersReflectable {"]
        lines += fields.map { "  " + $0 }
        lines.append("")
        lines.append("  \(access)init(\(arguments.joined(separator: ", "))) {")
        lines += assignments.map { "    " + $0 }
        lines += ["  }", "}"]
        declarations.append(lines.joined(separator: "\n"))
      }
    }
    let resultType = attribute.resultType ?? self.resultType ?? "Void"
    var arguments = ["\"\(attribute.methodID)\"", "name: \(attribute.name.trimmedDescription)"]
    if let parameterNames = attribute.parameterNames {
      arguments.append("parameterNames: \(parameterNames.trimmedDescription)")
    }
    if let resultNames = attribute.resultNames {
      arguments.append("resultNames: \(resultNames.trimmedDescription)")
    }
    let type = "OcaMethodDescriptor<\(parametersType), \(resultType)>"
    declarations.append(
      "\(access)static let \(name) =\n  \(type)(\(arguments.joined(separator: ", ")))"
    )
    return declarations
  }
}
