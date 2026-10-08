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

#if NonEmbeddedBuild

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
    // a document OcaXMIExport wrote says everything it means, so nothing is inferred
    let exported = root.child(named: "xmi:Documentation")?["exporter"] == OcaXMIExport.exporter
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
      // a class's or datatype's documentation is an attribute of its properties
      let documentation = Self.trimmed(element.child(named: "properties")?["documentation"])
      if var controlClass = Self.controlClass(element, named: name, parameters: parameters) {
        controlClass.isDeprecated = isDeprecated
        controlClass.documentation = documentation
        classes.append(controlClass)
      } else if var datatype = Self.datatype(element, named: name, names: names, exported: exported) {
        datatype.isDeprecated = isDeprecated
        datatype.documentation = documentation
        datatypes[name] = datatype
      }
    }
    // a template instance is named where it is used, and has no element of its own
    var used = [String]()
    for c in classes {
      used += c.properties.map(\.typeName)
      used += c.methods.flatMap { $0.parameters.map(\.typeName) }
      used += c.events.flatMap { $0.parameters.map(\.typeName) }
    }
    for datatype in datatypes.values {
      used += datatype.fields.map(\.typeName) + [datatype.baseTypeName]
    }
    // an instance's own arguments may be instances too: OcaMap<OcaONo,OcaList<OcaMediaClockRate>>
    while let name = used.popLast() {
      guard datatypes[name] == nil, let instance = Self.templateInstance(name) else { continue }
      datatypes[name] = instance
      used += instance.typeArguments
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

  /// An attribute's, operation's or parameter's documentation, from its `documentation`
  /// child: the parser has decoded its entities, and EA's markup, such as `<b>`, is kept.
  private static func documentation(_ node: XMINode) -> String {
    trimmed(node.child(named: "documentation")?["value"])
  }

  private static func trimmed(_ value: String?) -> String {
    value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
    // what a setter sets, case-insensitively: the model writes SetInbandGain for InBandGain
    let setters = Set(operations.compactMap { $0["name"] }.filter { $0.hasPrefix("Set") }.map { $0.dropFirst(3).lowercased() })
    let names = Set(attributes.filter { !isDeprecated($0) }.compactMap { $0["name"]?.lowercased() })
    // SetEnabled sets ControlEnabled: a setter of a suffix of the name that is no live property's
    func isSettable(_ name: String) -> Bool {
      let name = name.lowercased()
      return setters.contains(name) || setters.contains { name.hasSuffix($0) && !names.contains($0) }
    }

    let properties = live(attributes.compactMap { attribute -> (OcaClassPropertyDescriptor, Bool)? in
      guard let (letter, defLevel, index) = elementID(attribute), letter == "p", defLevel == level,
            let name = attribute["name"]
      else {
        return nil
      }
      let properties = attribute.child(named: "properties")
      // an exported model says so; the AES70-2 model is read only where no setter has its name
      let readOnly = attribute.child(named: "tags")?.children(named: "tag")
        .first { $0["name"] == OcaXMIExport.readOnlyTag }?["value"]
      return (OcaClassPropertyDescriptor(
        propertyID: OcaPropertyID(defLevel: defLevel, propertyIndex: index),
        name: name,
        typeName: properties?["type"] ?? "",
        isReadOnly: readOnly.map { $0 == "true" } ?? !isSettable(name),
        isStatic: properties?["static"] == "1",
        documentation: documentation(attribute)
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
      let extensionParameters = Dictionary(
        (operation.child(named: "parameters")?.children(named: "parameter") ?? []).compactMap { p in
          p["xmi:idref"].map { ($0, p) }
        }
      ) { first, _ in first }
      let declared = parameters[id] ?? []
      switch letter {
      case "m":
        methods.append((OcaClassMethodDescriptor(
          methodID: OcaMethodID(defLevel: defLevel, methodIndex: index),
          name: name,
          parameters: Self.parameterDescriptors(declared, extensionParameters),
          documentation: documentation(operation)
        ), isDeprecated(operation)))
      case "e":
        events.append((OcaClassEventDescriptor(
          eventID: OcaEventID(defLevel: defLevel, eventIndex: index),
          name: name,
          parameters: Self.parameterDescriptors(declared, extensionParameters),
          documentation: documentation(operation)
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
        .sorted { $0.methodID < $1.methodID },
      events: live(events, id: \.eventID) { $0.isDeprecated = true }
    )
  }

  /// What a method takes, then what it returns, as the class manager orders them; an
  /// inout parameter is taken and returned.
  private static func parameterDescriptors(
    _ declared: [(id: String, parameter: Parameter)],
    _ extensionParameters: [String: XMINode]
  ) -> [OcaClassParameterDescriptor] {
    func descriptors(_ direction: OcaParameterDirection, _ directions: Set<String>) -> [OcaClassParameterDescriptor] {
      declared.filter { directions.contains($0.parameter.direction) }.map {
        OcaClassParameterDescriptor(
          name: $0.parameter.name,
          typeName: extensionParameters[$0.id].flatMap(type) ?? "",
          direction: direction,
          documentation: extensionParameters[$0.id].map(documentation) ?? ""
        )
      }
    }
    return descriptors(.in, ["in", "inout"]) + descriptors(.out, ["out", "inout"])
  }

  /// The type an operation's parameter is declared with in the extension section.
  private static func type(_ parameter: XMINode) -> String? {
    parameter.child(named: "properties")?["type"]
  }

  // MARK: - Datatypes

  /// A datatype's stereotype. EA writes only the first of several as the property, so a
  /// deprecated one's kind is the next in its cross-references (`@STEREO;Name=enum;`).
  private static func kind(of element: XMINode) -> String {
    let first = element.child(named: "properties")?["stereotype"] ?? ""
    guard first == "deprecated", let xrefs = element.child(named: "xrefs")?["value"] else { return first }
    return xrefs.components(separatedBy: "@STEREO;Name=").dropFirst()
      .compactMap { $0.split(separator: ";").first.map(String.init) }
      .first { $0 != "deprecated" } ?? first
  }

  private static func datatype(
    _ element: XMINode,
    named name: String,
    names: [String: String],
    exported: Bool
  ) -> OcaDatatypeDescriptor? {
    let stereotype = kind(of: element)
    let attributes = element.child(named: "attributes")?.children(named: "attribute") ?? []
    // an exported model tags a base its links or stereotype cannot give
    let taggedBase = tags(of: element, named: OcaXMIExport.baseTypeTag).first
    let base = taggedBase ?? (element.child(named: "links")?.children(named: "Generalization") ?? [])
      .first { $0["start"] == element["xmi:idref"] }
      .flatMap { $0["end"] }.flatMap { names[$0] } ?? ""
    switch stereotype {
    case "primitive":
      return OcaDatatypeDescriptor(name: name, kind: .primitive)
    case "typedef":
      return OcaDatatypeDescriptor(name: name, kind: .typedef, baseTypeName: base)
    case "bitset":
      // AES70's bitsets are OcaBitSet16s, which the model does not always say
      return OcaDatatypeDescriptor(name: name, kind: .bitset, baseTypeName: taggedBase ?? (base.isEmpty ? "OcaUint16" : base))
    case "enum", "enumlong":
      return OcaDatatypeDescriptor(
        name: name, kind: .enum, baseTypeName: taggedBase ?? (stereotype == "enum" ? "OcaUint8" : "OcaUint16"),
        items: live(attributes.compactMap { a in
          a["name"].flatMap { n in
            a.child(named: "initial")?["body"].flatMap { OcaInt64($0) }.map {
              (OcaEnumItemDescriptor(name: n, value: $0, documentation: documentation(a)), isDeprecated(a))
            }
          }
        }, id: \.value) { $0.isDeprecated = true }
      )
    case "template":
      return templateInstance(name)
    case "struct":
      // a deprecated field is kept, not dropped as a twin: it still has its place in the coding
      let fields = attributes.compactMap { a in
        a["name"].map {
          OcaFieldDescriptor(
            name: $0,
            typeName: a.child(named: "properties")?["type"] ?? "",
            isDeprecated: isDeprecated(a),
            documentation: documentation(a)
          )
        }
      }
      // an exported model tags its parameters; in the AES70-2 model, a field typed by a name
      // that is not a datatype's is of one of the struct's parameters
      var parameters = tags(of: element, named: OcaXMIExport.typeArgumentTag)
      if !exported {
        for type in fields.map(\.typeName) where !type.hasPrefix("Oca") && !type.contains("<") && !parameters.contains(type) {
          parameters.append(type)
        }
      }
      return OcaDatatypeDescriptor(name: name, kind: .struct, typeArguments: parameters, fields: fields)
    default:
      return element["xmi:type"] == "uml:PrimitiveType" ? OcaDatatypeDescriptor(name: name, kind: .primitive) : nil
    }
  }

  /// The values of an element's tags named `name`, in order.
  private static func tags(of element: XMINode, named name: String) -> [String] {
    (element.child(named: "tags")?.children(named: "tag") ?? []).filter { $0["name"] == name }.compactMap { $0["value"] }
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
#endif
