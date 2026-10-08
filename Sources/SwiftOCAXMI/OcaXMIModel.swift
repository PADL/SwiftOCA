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


import Foundation
import SwiftOCA

/// The AES70-2 class model as an XMI document describes it, in the terms a class manager
/// answers with: each control class's own properties, methods and events, and each
/// datatype by its stereotype. Read from Enterprise Architect's XMI, whose UML section
/// gives parameters their names and directions and whose extension gives everything else.
public struct OcaXMIModel: Sendable {
  /// Each control class with its own elements only, as GetControlClasses answers.
  public let classes: [OcaClassDescriptor]
  public let datatypes: [OcaDatatypeDescriptor]

  public init(contentsOf url: URL) throws {
    try self.init(data: Data(contentsOf: url))
  }

  public init(data: Data) throws {
    let root = try XMINode.parse(data)
    let parameters = Self.parameters(in: root)
    let deprecated = Self.deprecatedIDs(in: root)
    let elements = root.descendants(named: "xmi:Extension").flatMap { $0.descendants(named: "element") }
    let names = Dictionary(elements.compactMap { e in e["xmi:idref"].flatMap { id in e["name"].map { (id, $0) } } }) { first, _ in first }
    var classes = [OcaClassDescriptor]()
    var datatypes = [String: OcaDatatypeDescriptor]()
    for element in elements {
      guard let name = element["name"] else { continue }
      let isDeprecated = element["xmi:idref"].map(deprecated.contains) ?? false
        || element.child(named: "properties")?["stereotype"] == "deprecated"
      if var controlClass = Self.controlClass(element, named: name, parameters: parameters) {
        controlClass.isDeprecated = isDeprecated
        classes.append(controlClass)
      } else if var datatype = Self.datatype(element, named: name, names: names) {
        datatype.isDeprecated = isDeprecated
        datatypes[name] = datatype
      }
    }
    // a template instance is named where it is used, and has no element of its own
    var used = [String]()
    for c in classes {
      used += c.properties.map(\.typeName)
      used += c.methods.flatMap { $0.parameters.map(\.typeName) }
      used += c.events.map(\.eventDataTypeName)
    }
    for datatype in datatypes.values {
      used += datatype.fields.map(\.typeName) + [datatype.baseTypeName]
    }
    for name in used where datatypes[name] == nil {
      if let instance = Self.templateInstance(name) { datatypes[name] = instance }
    }
    self.classes = classes
    self.datatypes = datatypes.values.sorted { $0.name < $1.name }
  }

  /// The class `classID`, with the elements of the classes it derives from if asked for,
  /// as GetControlClass answers.
  public func controlClass(_ classID: OcaClassID, includeInherited: Bool) -> OcaClassDescriptor? {
    guard var described = classes.first(where: { $0.classID == classID }) else { return nil }
    guard includeInherited else { return described }
    var ancestor = classID.parent
    var ancestors = [OcaClassDescriptor]()
    while let id = ancestor {
      if let found = classes.first(where: { $0.classID == id }) { ancestors.insert(found, at: 0) }
      ancestor = id.parent
    }
    described.properties = ancestors.flatMap(\.properties) + described.properties
    described.methods = ancestors.flatMap(\.methods) + described.methods
    described.events = ancestors.flatMap(\.events) + described.events
    return described
  }

  // MARK: - Control classes

  private typealias Parameter = (name: String, direction: String)

  /// Each operation's parameters by its ID, from the UML section, the return left out.
  private static func parameters(in root: XMINode) -> [String: [(id: String, parameter: Parameter)]] {
    var parameters = [String: [(id: String, parameter: Parameter)]]()
    for operation in root.descendants(named: "ownedOperation") {
      guard let id = operation["xmi:id"] else { continue }
      parameters[id] = operation.children(named: "ownedParameter").compactMap { p in
        guard let pid = p["xmi:id"], let name = p["name"], let direction = p["direction"], direction != "return"
        else { return nil }
        return (pid, (name, direction))
      }
    }
    return parameters
  }

  /// The UML IDs of what the model files under a `Deprecated …` package.
  private static func deprecatedIDs(in root: XMINode) -> Set<String> {
    let packages = root.descendants(named: "packagedElement").filter {
      $0["xmi:type"] == "uml:Package" && $0["name"]?.hasPrefix("Deprecated") == true
    }
    return Set(packages.flatMap { $0.descendants(named: "packagedElement" ) }.compactMap { $0["xmi:id"] })
  }

  /// Whether the model marks an attribute or operation deprecated.
  private static func isDeprecated(_ node: XMINode) -> Bool {
    node.child(named: "stereotype")?["stereotype"] == "deprecated"
  }

  /// Leaves out a deprecated element whose ID a live one has, which AES70 renames by
  /// deprecating a copy of; marks any other deprecated element so.
  private static func live<Element, ID: Hashable>(
    _ elements: [(element: Element, isDeprecated: Bool)],
    id: (Element) -> ID,
    marking mark: (inout Element) -> Void
  ) -> [Element] {
    let liveIDs = Set(elements.filter { !$0.isDeprecated }.map { id($0.element) })
    return elements.compactMap { element, isDeprecated in
      guard isDeprecated else { return element }
      guard !liveIDs.contains(id(element)) else { return nil }
      var element = element
      mark(&element)
      return element
    }
  }

  /// An element's ID from its style, `04m02` for method 4.2, with the letter it is of. A
  /// documentation code may follow it, `04m02 d:3`.
  private static func elementID(_ node: XMINode) -> (letter: Character, defLevel: UInt16, index: UInt16)? {
    guard let style = node.child(named: "style")?["value"]?.split(separator: " ").first,
          let letter = style.first(where: \.isLetter),
          let parts = Optional(style.split(separator: letter)), parts.count == 2,
          let level = UInt16(parts[0]), let index = UInt16(parts[1])
    else {
      return nil
    }
    return (letter, level, index)
  }

  private static func controlClass(
    _ element: XMINode,
    named name: String,
    parameters: [String: [(id: String, parameter: Parameter)]]
  ) -> OcaClassDescriptor? {
    let attributes = element.child(named: "attributes")?.children(named: "attribute") ?? []
    func initial(_ attribute: String) -> String? {
      attributes.first { $0["name"] == attribute }?.child(named: "initial")?["body"]
    }
    guard let id = initial("ClassID"), let classID = try? OcaClassID(unsafeString: id) else { return nil }
    let level = classID.defLevel
    let operations = element.child(named: "operations")?.children(named: "operation") ?? []
    let setters = Set(operations.compactMap { $0["name"] }.filter { $0.hasPrefix("Set") })

    let properties = live(attributes.compactMap { attribute -> (OcaClassPropertyDescriptor, Bool)? in
      guard let (letter, defLevel, index) = elementID(attribute), letter == "p", defLevel == level,
            let name = attribute["name"]
      else {
        return nil
      }
      let properties = attribute.child(named: "properties")
      return (OcaClassPropertyDescriptor(
        propertyID: OcaPropertyID(defLevel: defLevel, propertyIndex: index),
        name: name,
        typeName: properties?["type"] ?? "",
        isReadOnly: !setters.contains("Set" + name),
        isStatic: properties?["static"] == "1"
      ), isDeprecated(attribute))
    }, id: \.propertyID) { $0.isDeprecated = true }

    var methods = [(element: OcaClassMethodDescriptor, isDeprecated: Bool)]()
    var events = [(element: OcaClassEventDescriptor, isDeprecated: Bool)]()
    for operation in operations {
      guard let (letter, defLevel, index) = elementID(operation), defLevel == level,
            let name = operation["name"], let id = operation["xmi:idref"]
      else {
        continue
      }
      let types = Dictionary(
        (operation.child(named: "parameters")?.children(named: "parameter") ?? []).compactMap { p in
          p["xmi:idref"].flatMap { pid in p.child(named: "properties")?["type"].map { (pid, $0) } }
        }
      ) { first, _ in first }
      let declared = parameters[id] ?? []
      switch letter {
      case "m":
        methods.append((OcaClassMethodDescriptor(
          methodID: OcaMethodID(defLevel: defLevel, methodIndex: index),
          name: name,
          parameters: Self.parameterDescriptors(declared, types: types)
        ), isDeprecated(operation)))
      case "e":
        events.append((OcaClassEventDescriptor(
          eventID: OcaEventID(defLevel: defLevel, eventIndex: index),
          name: name,
          eventDataTypeName: declared.first.flatMap { types[$0.id] } ?? ""
        ), isDeprecated(operation)))
      default:
        continue
      }
    }
    return OcaClassDescriptor(
      classID: classID,
      classVersion: initial("ClassVersion").flatMap(OcaClassVersionNumber.init) ?? 1,
      name: name,
      properties: properties,
      methods: live(methods, id: \.methodID) { $0.isDeprecated = true }
        .sorted { ($0.methodID.defLevel, $0.methodID.methodIndex) < ($1.methodID.defLevel, $1.methodID.methodIndex) },
      events: live(events, id: \.eventID) { $0.isDeprecated = true }
    )
  }

  /// What a method takes, then what it returns, as the class manager orders them; an
  /// inout parameter is taken and returned.
  private static func parameterDescriptors(
    _ declared: [(id: String, parameter: Parameter)],
    types: [String: String]
  ) -> [OcaClassParameterDescriptor] {
    func descriptors(_ direction: OcaParameterDirection, _ directions: Set<String>) -> [OcaClassParameterDescriptor] {
      declared.filter { directions.contains($0.parameter.direction) }.map {
        OcaClassParameterDescriptor(name: $0.parameter.name, typeName: types[$0.id] ?? "", direction: direction)
      }
    }
    return descriptors(.in, ["in", "inout"]) + descriptors(.out, ["out", "inout"])
  }

  // MARK: - Datatypes

  private static func datatype(_ element: XMINode, named name: String, names: [String: String]) -> OcaDatatypeDescriptor? {
    let stereotype = element.child(named: "properties")?["stereotype"] ?? ""
    let attributes = element.child(named: "attributes")?.children(named: "attribute") ?? []
    let base = (element.child(named: "links")?.children(named: "Generalization") ?? [])
      .first { $0["start"] == element["xmi:idref"] }
      .flatMap { $0["end"] }.flatMap { names[$0] } ?? ""
    switch stereotype {
    case "primitive":
      return OcaDatatypeDescriptor(name: name, kind: .primitive)
    case "typedef":
      return OcaDatatypeDescriptor(name: name, kind: .typedef, baseTypeName: base)
    case "bitset":
      // AES70's bitsets are OcaBitSet16s, which the model does not always say
      return OcaDatatypeDescriptor(name: name, kind: .bitset, baseTypeName: base.isEmpty ? "OcaUint16" : base)
    case "enum", "enumlong":
      return OcaDatatypeDescriptor(
        name: name, kind: .enum, baseTypeName: stereotype == "enum" ? "OcaUint8" : "OcaUint16",
        items: live(attributes.compactMap { a in
          a["name"].flatMap { n in
            a.child(named: "initial")?["body"].flatMap { OcaInt64($0) }.map { (OcaEnumItemDescriptor(name: n, value: $0), isDeprecated(a)) }
          }
        }, id: \.value) { $0.isDeprecated = true }
      )
    case "struct":
      let fields = attributes.compactMap { a in
        a["name"].map {
          OcaFieldDescriptor(name: $0, typeName: a.child(named: "properties")?["type"] ?? "", isDeprecated: isDeprecated(a))
        }
      }
      // a field typed by a name that is not a datatype's is of one of the struct's parameters
      let parameters = fields.map(\.typeName).filter { !$0.hasPrefix("Oca") && !$0.contains("<") }
      return OcaDatatypeDescriptor(name: name, kind: .struct, typeArguments: parameters, fields: fields)
    default:
      return element["xmi:type"] == "uml:PrimitiveType" ? OcaDatatypeDescriptor(name: name, kind: .primitive) : nil
    }
  }

  /// A template instance, `OcaList<OcaONo>`, from its name.
  private static func templateInstance(_ name: String) -> OcaDatatypeDescriptor? {
    guard let open = name.firstIndex(of: "<"), name.hasSuffix(">") else { return nil }
    var arguments = [String]()
    var depth = 0
    var current = ""
    for character in name[name.index(after: open)..<name.index(before: name.endIndex)] {
      switch character {
      case "<": depth += 1
      case ">": depth -= 1
      case "," where depth == 0:
        arguments.append(current.trimmingCharacters(in: .whitespaces))
        current = ""
        continue
      default: break
      }
      current.append(character)
    }
    arguments.append(current.trimmingCharacters(in: .whitespaces))
    return OcaDatatypeDescriptor(name: name, kind: .template, baseTypeName: String(name[..<open]), typeArguments: arguments)
  }
}
