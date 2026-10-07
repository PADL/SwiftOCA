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

/// What a class macro lists from a class body: entries in groups, each `#if` block's under
/// its own conditions, as the body has them.
struct MemberTable {
  var groups = [(directive: String?, entries: [String])]()

  var entries: [String] { groups.flatMap(\.entries) }

  /// The class body's entries, those in `#if` blocks under the same conditions.
  init(_ classDecl: ClassDeclSyntax, _ entries: (MemberBlockItemListSyntax) throws -> [String]) rethrows {
    func append(_ names: [String]) {
      guard !names.isEmpty else { return }
      groups.append((nil, names))
    }
    append(try entries(classDecl.memberBlock.members))
    for member in classDecl.memberBlock.members {
      guard let block = member.decl.as(IfConfigDeclSyntax.self) else { continue }
      let clauses = try block.clauses.map { clause in
        (clause, try clause.elements?.as(MemberBlockItemListSyntax.self).map(entries) ?? [])
      }
      guard clauses.contains(where: { !$0.1.isEmpty }) else { continue }
      for (clause, names) in clauses {
        let condition = clause.condition.map { " " + $0.trimmedDescription } ?? ""
        groups.append(("\(clause.poundKeyword.text)\(condition)", []))
        append(names)
      }
      groups.append(("#endif", []))
    }
  }

  /// A statement for each group of entries, and each directive as it is.
  func statements(appending: (String) -> String) -> String {
    groups.map { group in
      if let directive = group.directive { return directive }
      return appending(group.entries.joined(separator: ", "))
    }.joined(separator: "\n  ")
  }

  /// The properties declared in `members` with one of `wrappers` and a written type, each
  /// as a dictionary entry from its name to that type's AES70 name.
  static func propertyTypeNames(
    in members: MemberBlockItemListSyntax,
    of classDecl: ClassDeclSyntax,
    wrappers: Set<String>
  ) -> [String] {
    // a type written with the class's generic parameters is known only at run time
    let generics = Set(classDecl.genericParameterClause?.parameters.map(\.name.text) ?? [])
    return wrappedProperties(in: members, wrappers: wrappers).compactMap { name, binding in
      guard let type = declaredType(of: binding), !mentions(type, any: generics) else {
        return nil
      }
      return "\"\(name)\": \"\(aes70Name(of: type))\""
    }
  }

  /// The type a binding is declared with, or, with none written, the one its initial
  /// value is made with (`OcaBoundedPropertyValue<OcaDB>(...)`).
  private static func declaredType(of binding: PatternBindingSyntax) -> TypeSyntax? {
    if let annotation = binding.typeAnnotation { return annotation.type }
    guard let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
          call.calledExpression.is(GenericSpecializationExprSyntax.self)
          || call.calledExpression.is(DeclReferenceExprSyntax.self)
    else {
      return nil
    }
    let type = TypeSyntax(stringLiteral: call.calledExpression.trimmedDescription)
    // a lower-case callee is a function, not a type
    return type.trimmedDescription.first?.isUppercase == true ? type : nil
  }

  /// Whether `type` is written with any of `names`, such as a class's generic parameters.
  static func mentions(_ type: TypeSyntax, any names: Set<String>) -> Bool {
    type.tokens(viewMode: .sourceAccurate).contains { names.contains($0.text) }
  }

  /// A type as written, named as AES70 names it: a typealias such as `OcaDB` as it is,
  /// a Swift base type by its AES70 name, and a collection by AES70's template.
  static func aes70Name(of type: TypeSyntax) -> String {
    if let array = type.as(ArrayTypeSyntax.self) {
      return "OcaList<\(aes70Name(of: array.element))>"
    }
    if let dictionary = type.as(DictionaryTypeSyntax.self) {
      return "OcaMap<\(aes70Name(of: dictionary.key)), \(aes70Name(of: dictionary.value))>"
    }
    if let optional = type.as(OptionalTypeSyntax.self) {
      return aes70Name(of: optional.wrappedType)
    }
    if let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
      return aes70Name(of: unwrapped.wrappedType)
    }
    guard let identifier = type.as(IdentifierTypeSyntax.self) else { return type.trimmedDescription }
    let arguments = identifier.genericArgumentClause?.arguments.compactMap {
      $0.argument.as(TypeSyntax.self).map(aes70Name(of:))
    } ?? []
    switch (identifier.name.text, arguments.count) {
    case ("Array", 1): return "OcaList<\(arguments[0])>"
    case ("Dictionary", 2): return "OcaMap<\(arguments[0]), \(arguments[1])>"
    case ("Optional", 1): return arguments[0]
    // a bounded property's value is of its type, with the bounds beside it
    case ("OcaBoundedPropertyValue", 1): return arguments[0]
    default: break
    }
    let name = baseNames[identifier.name.text] ?? identifier.name.text
    return arguments.isEmpty ? name : "\(name)<\(arguments.joined(separator: ", "))>"
  }

  private static let baseNames = [
    "Bool": "OcaBoolean", "String": "OcaString",
    "Int8": "OcaInt8", "Int16": "OcaInt16", "Int32": "OcaInt32", "Int64": "OcaInt64",
    "UInt8": "OcaUint8", "UInt16": "OcaUint16", "UInt32": "OcaUint32", "UInt64": "OcaUint64",
    "Float": "OcaFloat32", "Float32": "OcaFloat32", "Double": "OcaFloat64", "Float64": "OcaFloat64",
  ]

  /// The properties declared in `members` with one of `wrappers`, each as a dictionary
  /// entry from its name to the key path of its wrapper's storage in `className`.
  static func propertyKeyPaths(
    in members: MemberBlockItemListSyntax,
    of className: String,
    wrappers: Set<String>
  ) -> [String] {
    wrappedProperties(in: members, wrappers: wrappers).map { name, _ in
      "\"\(name)\": \\\(className)._\(name)"
    }
  }

  /// Each property declared in `members` with one of `wrappers`, by its name.
  private static func wrappedProperties(
    in members: MemberBlockItemListSyntax,
    wrappers: Set<String>
  ) -> [(name: String, binding: PatternBindingSyntax)] {
    members.flatMap { member -> [(name: String, binding: PatternBindingSyntax)] in
      guard let variable = member.decl.as(VariableDeclSyntax.self),
            variable.attributes.contains(where: { attribute in
              guard case let .attribute(attribute) = attribute else { return false }
              return attribute.attributeName.trimmedDescription.split(separator: ".").last
                .map { wrappers.contains(String($0)) } ?? false
            })
      else {
        return []
      }
      return variable.bindings.compactMap { binding in
        binding.pattern.as(IdentifierPatternSyntax.self).map { pattern in
          // a keyword spelled with backticks names a property without them
          (pattern.identifier.text.filter { $0 != "`" }, binding)
        }
      }
    }
  }
}
