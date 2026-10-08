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

/// Writes a class manager's descriptors as an XMI document in the shape of the AES70-2
/// model's: a UML section a UML tool can read, and the parts of Enterprise Architect's
/// extension that `OcaXMIModel` reads back. Importing the document gives the descriptors
/// again, with documentation trimmed and methods in ID order, as a class manager has them.
/// Its IDs come from the elements', so the same model writes the same.
public enum OcaXMIExport {
  /// The tag that says whether a property is read only, which the AES70-2 model leaves
  /// to its setters' names.
  static let readOnlyTag = "isReadOnly"
  /// The tag that gives a datatype's base where the model's own form cannot: an enum not
  /// of the model's two widths, or a typedef or bitset of a type the document leaves out.
  static let baseTypeTag = "baseType"
  /// The tags that give a struct's type parameters, one each, in order.
  static let typeArgumentTag = "typeArgument"
  /// The exporter a document names, which tells the importer to infer nothing.
  static let exporter = "SwiftOCA"

  /// The document for `classes`, each with its own elements only, and `datatypes`.
  public static func document(
    classes: [OcaClassDescriptor],
    datatypes: [OcaDatatypeDescriptor],
    modelName: String = "Device"
  ) -> String {
    var writer = Writer(datatypeNames: Set(datatypes.map(\.name)), classIDs: Set(classes.map(\.classID)))
    let classes = classes.map { c in
      var c = c
      c.methods.sort { ($0.methodID.defLevel, $0.methodID.methodIndex) < ($1.methodID.defLevel, $1.methodID.methodIndex) }
      return c
    }
    writer.write(classes: classes, datatypes: datatypes, modelName: modelName)
    return writer.lines.joined(separator: "\n") + "\n"
  }
}

private struct Writer {
  let datatypeNames: Set<String>
  let classIDs: Set<OcaClassID>
  var lines = [String]()

  mutating func write(classes: [OcaClassDescriptor], datatypes: [OcaDatatypeDescriptor], modelName: String) {
    lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
    lines.append(#"<xmi:XMI xmi:version="2.1" xmlns:uml="http://schema.omg.org/spec/UML/2.1" xmlns:xmi="http://schema.omg.org/spec/XMI/2.1">"#)
    lines.append("<xmi:Documentation exporter=\(quoted(OcaXMIExport.exporter)) exporterVersion=\"1\"/>")
    lines.append("<uml:Model xmi:type=\"uml:Model\" name=\(quoted(modelName)) visibility=\"public\">")
    lines.append(#"<packagedElement xmi:type="uml:Package" xmi:id="OCA_PK_Model" name="Control Model" visibility="public">"#)
    // the importer marks what a Deprecated package holds deprecated
    package("Control Classes", id: "OCA_PK_Classes") {
      for c in classes where !c.isDeprecated { $0.umlClass(c) }
    }
    package("Control Datatypes", id: "OCA_PK_Datatypes") {
      for d in datatypes where !d.isDeprecated { $0.umlDatatype(d) }
    }
    package("Deprecated Components", id: "OCA_PK_Deprecated") {
      for c in classes where c.isDeprecated { $0.umlClass(c) }
      for d in datatypes where d.isDeprecated { $0.umlDatatype(d) }
    }
    lines.append("</packagedElement>")
    lines.append("</uml:Model>")
    lines.append(#"<xmi:Extension extender="Enterprise Architect" extenderID="6.5">"#)
    lines.append("<elements>")
    for c in classes { extensionClass(c) }
    for d in datatypes { extensionDatatype(d) }
    lines.append("</elements>")
    lines.append("</xmi:Extension>")
    lines.append("</xmi:XMI>")
  }

  private mutating func package(_ name: String, id: String, _ body: (inout Self) -> Void) {
    lines.append("<packagedElement xmi:type=\"uml:Package\" xmi:id=\(quoted(id)) name=\(quoted(name)) visibility=\"public\">")
    body(&self)
    lines.append("</packagedElement>")
  }

  // MARK: - UML section

  private mutating func umlClass(_ c: OcaClassDescriptor) {
    let id = Self.classID(c.classID)
    lines.append("<packagedElement xmi:type=\"uml:Class\" xmi:id=\(quoted(id)) name=\(quoted(c.name)) visibility=\"public\">")
    if let parent = parent(of: c) {
      lines.append("<generalization xmi:type=\"uml:Generalization\" xmi:id=\(quoted(id + "_G")) general=\(quoted(Self.classID(parent)))/>")
    }
    for (name, value, typeName) in Self.identity(of: c) where !Self.isRoot(c) {
      lines.append("<ownedAttribute xmi:type=\"uml:Property\" xmi:id=\(quoted(id + "_" + name)) name=\(quoted(name)) visibility=\"public\" isStatic=\"true\" isReadOnly=\"true\"\(typeAttribute(typeName))>")
      lines.append("<defaultValue xmi:type=\"uml:LiteralString\" xmi:id=\(quoted(id + "_" + name + "_V")) value=\(quoted(value))/>")
      lines.append("</ownedAttribute>")
    }
    for p in c.properties {
      lines.append("<ownedAttribute xmi:type=\"uml:Property\" xmi:id=\(quoted(Self.propertyID(c, p))) name=\(quoted(p.name)) visibility=\"public\" isStatic=\"\(p.isStatic)\" isReadOnly=\"\(p.isReadOnly)\"\(typeAttribute(p.typeName))/>")
    }
    for m in c.methods {
      umlOperation(id: Self.methodID(c, m), name: m.name, parameters: m.parameters, returns: true)
    }
    for e in c.events {
      umlOperation(id: Self.eventID(c, e), name: e.name, parameters: e.parameters, returns: false)
    }
    lines.append("</packagedElement>")
  }

  private mutating func umlOperation(id: String, name: String, parameters: [OcaClassParameterDescriptor], returns: Bool) {
    lines.append("<ownedOperation xmi:id=\(quoted(id)) name=\(quoted(name)) visibility=\"public\">")
    for (index, p) in parameters.enumerated() {
      lines.append("<ownedParameter xmi:id=\(quoted(id + "_P\(index)")) name=\(quoted(p.name)) direction=\"\(p.direction)\"\(typeAttribute(p.typeName))/>")
    }
    if returns {
      lines.append("<ownedParameter xmi:id=\(quoted(id + "_R")) name=\"return\" direction=\"return\"\(typeAttribute("OcaStatus"))/>")
    }
    lines.append("</ownedOperation>")
  }

  private mutating func umlDatatype(_ d: OcaDatatypeDescriptor) {
    let id = Self.datatypeID(d.name)
    let type = Self.umlType(of: d)
    lines.append("<packagedElement xmi:type=\(quoted(type)) xmi:id=\(quoted(id)) name=\(quoted(d.name)) visibility=\"public\">")
    if let base = base(of: d) {
      lines.append("<generalization xmi:type=\"uml:Generalization\" xmi:id=\(quoted(id + "_G")) general=\(quoted(Self.datatypeID(base)))/>")
    }
    for (index, f) in d.fields.enumerated() {
      lines.append("<ownedAttribute xmi:type=\"uml:Property\" xmi:id=\(quoted(id + "_F\(index)")) name=\(quoted(f.name)) visibility=\"public\"\(typeAttribute(f.typeName))/>")
    }
    for (index, i) in d.items.enumerated() {
      lines.append("<ownedLiteral xmi:type=\"uml:EnumerationLiteral\" xmi:id=\(quoted(id + "_I\(index)")) name=\(quoted(i.name))/>")
    }
    lines.append("</packagedElement>")
  }

  // MARK: - Enterprise Architect's extension

  private mutating func extensionClass(_ c: OcaClassDescriptor) {
    let id = Self.classID(c.classID)
    lines.append("<element xmi:idref=\(quoted(id)) xmi:type=\"uml:Class\" name=\(quoted(c.name)) scope=\"public\">")
    lines.append("<properties documentation=\(quoted(trimmed(c.documentation))) sType=\"Class\" scope=\"public\" stereotype=\"controlClass\"/>")
    lines.append("<attributes>")
    for (name, value, typeName) in Self.identity(of: c) where !Self.isRoot(c) {
      lines.append("<attribute xmi:idref=\(quoted(id + "_" + name)) name=\(quoted(name)) scope=\"Public\">")
      lines.append("<initial body=\(quoted(value))/>")
      lines.append("<properties type=\(quoted(typeName)) static=\"1\"/>")
      lines.append("<style value=\(quoted(Self.style(1, "p", name == "ClassID" ? 1 : 2)))/>")
      lines.append("</attribute>")
    }
    for p in c.properties {
      let pid = Self.propertyID(c, p)
      lines.append("<attribute xmi:idref=\(quoted(pid)) name=\(quoted(p.name)) scope=\"Public\">")
      // OcaRoot's own ClassID and ClassVersion carry the class's values
      if Self.isRoot(c), let value = Self.identity(of: c).first(where: { $0.name == p.name })?.value {
        lines.append("<initial body=\(quoted(value))/>")
      }
      documentation(p.documentation)
      lines.append("<properties type=\(quoted(p.typeName)) static=\"\(p.isStatic ? 1 : 0)\"/>")
      deprecation(p.isDeprecated)
      lines.append("<style value=\(quoted(Self.style(p.propertyID.defLevel, "p", p.propertyID.propertyIndex)))/>")
      lines.append("<tags><tag xmi:id=\(quoted(pid + "_T")) name=\(quoted(OcaXMIExport.readOnlyTag)) value=\"\(p.isReadOnly)\" modelElement=\(quoted(pid))/></tags>")
      lines.append("</attribute>")
    }
    lines.append("</attributes>")
    lines.append("<operations>")
    for m in c.methods {
      extensionOperation(
        id: Self.methodID(c, m), name: m.name, style: Self.style(m.methodID.defLevel, "m", m.methodID.methodIndex),
        parameters: m.parameters, isDeprecated: m.isDeprecated, isEvent: false, documentation: m.documentation
      )
    }
    for e in c.events {
      extensionOperation(
        id: Self.eventID(c, e), name: e.name, style: Self.style(e.eventID.defLevel, "e", e.eventID.eventIndex),
        parameters: e.parameters, isDeprecated: e.isDeprecated, isEvent: true, documentation: e.documentation
      )
    }
    lines.append("</operations>")
    if let parent = parent(of: c) {
      lines.append("<links><Generalization xmi:id=\(quoted(id + "_L")) start=\(quoted(id)) end=\(quoted(Self.classID(parent)))/></links>")
    }
    lines.append("</element>")
  }

  private mutating func extensionOperation(
    id: String,
    name: String,
    style: String,
    parameters: [OcaClassParameterDescriptor],
    isDeprecated: Bool,
    isEvent: Bool,
    documentation text: String
  ) {
    lines.append("<operation xmi:idref=\(quoted(id)) name=\(quoted(name)) scope=\"Public\">")
    if isDeprecated || isEvent {
      lines.append("<stereotype stereotype=\"\(isDeprecated ? "deprecated" : "event")\"/>")
    }
    documentation(text)
    lines.append("<style value=\(quoted(style))/>")
    lines.append("<parameters>")
    for (index, p) in parameters.enumerated() {
      lines.append("<parameter xmi:idref=\(quoted(id + "_P\(index)")) visibility=\"public\">")
      lines.append("<properties type=\(quoted(p.typeName))/>")
      documentation(p.documentation)
      lines.append("</parameter>")
    }
    lines.append("</parameters>")
    lines.append("</operation>")
  }

  private mutating func extensionDatatype(_ d: OcaDatatypeDescriptor) {
    let id = Self.datatypeID(d.name)
    lines.append("<element xmi:idref=\(quoted(id)) xmi:type=\(quoted(Self.umlType(of: d))) name=\(quoted(d.name)) scope=\"public\">")
    lines.append("<properties documentation=\(quoted(trimmed(d.documentation))) sType=\"Class\" scope=\"public\" stereotype=\(quoted(Self.stereotype(of: d)))/>")
    if !d.fields.isEmpty || !d.items.isEmpty {
      lines.append("<attributes>")
      for (index, f) in d.fields.enumerated() {
        lines.append("<attribute xmi:idref=\(quoted(id + "_F\(index)")) name=\(quoted(f.name)) scope=\"Public\">")
        documentation(f.documentation)
        lines.append("<properties type=\(quoted(f.typeName))/>")
        deprecation(f.isDeprecated)
        lines.append("</attribute>")
      }
      for (index, i) in d.items.enumerated() {
        lines.append("<attribute xmi:idref=\(quoted(id + "_I\(index)")) name=\(quoted(i.name)) scope=\"Public\">")
        lines.append("<initial body=\"\(i.value)\"/>")
        documentation(i.documentation)
        deprecation(i.isDeprecated)
        lines.append("</attribute>")
      }
      lines.append("</attributes>")
    }
    if let base = base(of: d) {
      lines.append("<links><Generalization xmi:id=\(quoted(id + "_L")) start=\(quoted(id)) end=\(quoted(Self.datatypeID(base)))/></links>")
    }
    var tags = [(name: String, value: String)]()
    if needsBaseTypeTag(d) { tags.append((OcaXMIExport.baseTypeTag, d.baseTypeName)) }
    if d.kind == .struct { tags += d.typeArguments.map { (OcaXMIExport.typeArgumentTag, $0) } }
    if !tags.isEmpty {
      lines.append("<tags>")
      for (index, tag) in tags.enumerated() {
        lines.append("<tag xmi:id=\(quoted(id + "_T\(index)")) name=\(quoted(tag.name)) value=\(quoted(tag.value)) modelElement=\(quoted(id))/>")
      }
      lines.append("</tags>")
    }
    lines.append("</element>")
  }

  private mutating func documentation(_ text: String) {
    let text = trimmed(text)
    guard !text.isEmpty else { return }
    lines.append("<documentation value=\(quoted(text))/>")
  }

  private mutating func deprecation(_ isDeprecated: Bool) {
    guard isDeprecated else { return }
    lines.append(#"<stereotype stereotype="deprecated"/>"#)
  }

  // MARK: - Names and IDs

  /// The class ID and version every class carries: OcaRoot has them as its own
  /// properties, and the model redeclares them in every other class.
  private static func identity(of c: OcaClassDescriptor) -> [(name: String, value: String, typeName: String)] {
    [("ClassID", c.classID.description, "OcaClassID"), ("ClassVersion", "\(c.classVersion)", "OcaClassVersionNumber")]
  }

  private static func isRoot(_ c: OcaClassDescriptor) -> Bool { c.classID.defLevel == 1 }

  /// The class `c` derives from, where the document has it.
  private func parent(of c: OcaClassDescriptor) -> OcaClassID? {
    c.classID.parent.flatMap { classIDs.contains($0) ? $0 : nil }
  }

  /// The type a typedef or bitset stands for, where the document has it.
  private func base(of d: OcaDatatypeDescriptor) -> String? {
    switch d.kind {
    case .typedef, .bitset: datatypeNames.contains(d.baseTypeName) ? d.baseTypeName : nil
    default: nil
    }
  }

  /// Whether `d`'s base needs a tag to be read back: the model's stereotypes give an
  /// enum's only for its two widths, and a link gives a typedef's only to a type here.
  private func needsBaseTypeTag(_ d: OcaDatatypeDescriptor) -> Bool {
    switch d.kind {
    case .enum: d.baseTypeName != "OcaUint8" && d.baseTypeName != "OcaUint16"
    case .typedef, .bitset: base(of: d) == nil
    default: false
    }
  }

  private func typeAttribute(_ typeName: String) -> String {
    datatypeNames.contains(typeName) ? " type=\(quoted(Self.datatypeID(typeName)))" : ""
  }

  private static func umlType(of d: OcaDatatypeDescriptor) -> String {
    switch d.kind {
    case .primitive: "uml:PrimitiveType"
    case .enum: "uml:Enumeration"
    default: "uml:DataType"
    }
  }

  private static func stereotype(of d: OcaDatatypeDescriptor) -> String {
    switch d.kind {
    case .primitive: "primitive"
    case .typedef: "typedef"
    case .struct: "struct"
    case .bitset: "bitset"
    case .template: "template"
    // the model's two widths: enum is an OcaUint8, enumlong an OcaUint16
    case .enum: d.baseTypeName == "OcaUint8" ? "enum" : "enumlong"
    }
  }

  private static func style(_ level: UInt16, _ letter: Character, _ index: UInt16) -> String {
    func padded(_ n: UInt16) -> String { n < 10 ? "0\(n)" : "\(n)" }
    return padded(level) + String(letter) + padded(index)
  }

  static func classID(_ id: OcaClassID) -> String { "OCA_C_" + escaped(id.description) }

  static func datatypeID(_ name: String) -> String { "OCA_T_" + escaped(name) }

  private static func propertyID(_ c: OcaClassDescriptor, _ p: OcaClassPropertyDescriptor) -> String {
    classID(c.classID) + "_p\(p.propertyID.defLevel)_\(p.propertyID.propertyIndex)"
  }

  private static func methodID(_ c: OcaClassDescriptor, _ m: OcaClassMethodDescriptor) -> String {
    classID(c.classID) + "_m\(m.methodID.defLevel)_\(m.methodID.methodIndex)"
  }

  private static func eventID(_ c: OcaClassDescriptor, _ e: OcaClassEventDescriptor) -> String {
    classID(c.classID) + "_e\(e.eventID.defLevel)_\(e.eventID.eventIndex)"
  }

  /// A name as an XML name: ASCII letters and digits kept, anything else as `_` and its hex.
  private static func escaped(_ name: String) -> String {
    var escaped = ""
    for byte in name.utf8 {
      switch byte {
      case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"):
        escaped.unicodeScalars.append(Unicode.Scalar(byte))
      default:
        let hex = String(byte, radix: 16, uppercase: true)
        escaped += "_" + (hex.count < 2 ? "0" + hex : hex)
      }
    }
    return escaped
  }
}

/// Documentation as the importer reads it back.
private func trimmed(_ text: String) -> String {
  text.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// `value` as a quoted XML attribute value; whitespace that an attribute would otherwise
/// normalise away is written as character references, and characters XML 1.0 cannot hold
/// at all as U+FFFD.
private func quoted(_ value: String) -> String {
  var quoted = "\""
  for scalar in value.unicodeScalars {
    switch scalar {
    case "\u{0}"..."\u{8}", "\u{B}", "\u{C}", "\u{E}"..."\u{1F}", "\u{FFFE}", "\u{FFFF}": quoted += "\u{FFFD}"
    case "&": quoted += "&amp;"
    case "<": quoted += "&lt;"
    case ">": quoted += "&gt;"
    case "\"": quoted += "&quot;"
    case "\n": quoted += "&#xA;"
    case "\r": quoted += "&#xD;"
    case "\t": quoted += "&#x9;"
    default: quoted.unicodeScalars.append(scalar)
    }
  }
  return quoted + "\""
}
#endif
