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

  /// The properties declared in `members` with one of `wrappers`, each as a dictionary
  /// entry from its name to the key path of its wrapper's storage in `className`.
  static func propertyKeyPaths(
    in members: MemberBlockItemListSyntax,
    of className: String,
    wrappers: Set<String>
  ) -> [String] {
    members.flatMap { member -> [String] in
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
          let name = pattern.identifier.text.filter { $0 != "`" }
          return "\"\(name)\": \\\(className)._\(name)"
        }
      }
    }
  }
}
