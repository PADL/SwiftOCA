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

/// The device's class manager (see `SwiftOCA.OcaClassManager`). It describes the classes
/// of the device's objects to a controller from what the device knows of them.
///
/// A typedef is named as such only where a declaration records it: a property's type, or a
/// method's as `@OcaMethod` writes it. Elsewhere, such as a struct's fields, a Swift
/// typealias is not known at run time, and the typedef is named as the type it stands for.
@OcaDeviceClass
public final class OcaClassManager: OcaManager {
  override public class var classID: OcaClassID { SwiftOCA.OcaClassManager.classID }

  public convenience init(deviceDelegate: OcaDevice? = nil) async throws {
    try await self.init(
      objectNumber: OcaClassManagerONo,
      role: "ClassManager",
      deviceDelegate: deviceDelegate,
      addToRootBlock: false
    )
  }

  /// Every class of the device's objects, each once and with only its own elements, in
  /// the order the device first had an object of it.
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public private(set) var controlClasses = OcaList<OcaClassDescriptor>()

  /// Every datatype the classes of the device's objects refer to, each once, by name.
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.2")
  )
  public private(set) var datatypes = OcaList<OcaDatatypeDescriptor>()

  @OcaDeviceMethod(SwiftOCA.OcaClassManager.Methods.getControlClass, access: .read)
  func getControlClass(
    classID: OcaClassID,
    includeInherited: OcaBoolean,
    from controller: any OcaController
  ) async throws -> OcaClassDescriptor {
    guard let lineage = lineages[classID] else { throw Ocp1Error.status(.parameterError) }
    return Self.descriptor(of: lineage.last!, with: includeInherited ? lineage : [lineage.last!])
  }

  @OcaDeviceMethod(SwiftOCA.OcaClassManager.Methods.getDatatype, access: .read)
  func getDatatype(name: OcaString, from controller: any OcaController) async throws -> OcaDatatypeDescriptor {
    guard let datatype = described.described[name] else { throw Ocp1Error.status(.parameterError) }
    return datatype
  }

  /// The registered objects' Swift classes, each with how many objects it has and its
  /// OCA classes, root first.
  private var registered = [ObjectIdentifier: (count: Int, lineage: [OcaDeviceClassDescriptor])]()
  /// Each OCA class of the device's objects with the classes it derives from, root first.
  private var lineages = [OcaClassID: [OcaDeviceClassDescriptor]]()
  private var described = Datatypes()

  /// Called by the device as it registers an object. Only an object of a Swift class the
  /// device has no other object of can bring classes to describe.
  func didRegister(object: OcaRoot) {
    let key = ObjectIdentifier(type(of: object))
    if let entry = registered[key] {
      registered[key]!.count = entry.count + 1
      return
    }
    let lineage = object.deviceClassDescriptors
    registered[key] = (1, lineage)
    add(lineage: lineage)
  }

  /// Called by the device as it deregisters an object. When the last object of a Swift
  /// class goes, the classes and datatypes are described afresh from those that remain.
  func didDeregister(object: OcaRoot) {
    let key = ObjectIdentifier(type(of: object))
    guard let entry = registered[key] else { return }
    guard entry.count == 1 else {
      registered[key]!.count = entry.count - 1
      return
    }
    registered[key] = nil
    lineages = [:]
    described = Datatypes()
    controlClasses = []
    for entry in registered.values {
      add(lineage: entry.lineage)
    }
  }

  private func add(lineage: [OcaDeviceClassDescriptor]) {
    var added = false
    for index in lineage.indices where lineages[lineage[index].classID] == nil {
      let oca = lineage[index]
      lineages[oca.classID] = Array(lineage[...index])
      controlClasses.append(Self.descriptor(of: oca, with: [oca]))
      addDatatypes(of: oca)
      added = true
    }
    if added {
      datatypes = described.described.sorted { $0.key < $1.key }.map(\.value)
    }
  }

  /// Adds the datatypes `oca`'s own elements refer to, and those they refer to in turn.
  private func addDatatypes(of oca: OcaDeviceClassDescriptor) {
    for property in oca.properties {
      described.add(property.valueType, declared: property.typeName)
    }
    for descriptor in oca.methods {
      for element in Self.elements(of: descriptor.method) {
        described.add(element.type, declared: element.declared)
      }
    }
    for event in Self.ownEvents(of: oca) {
      described.add(event.eventDataType, declared: nil)
    }
    if oca.classID == OcaRoot.classID {
      for root in Self.rootProperties {
        described.add(root.type, declared: root.typeName)
      }
    }
  }

  /// OcaRoot's properties, all read only, which OcaRoot answers for itself rather than
  /// through device properties.
  private static let rootProperties: [(id: OcaPropertyID, name: String, type: Any.Type, typeName: String, isStatic: Bool)] = [
    (OcaPropertyID("1.1"), "ClassID", OcaClassID.self, "OcaClassID", true),
    (OcaPropertyID("1.2"), "ClassVersion", OcaClassVersionNumber.self, "OcaClassVersionNumber", true),
    (OcaPropertyID("1.3"), "ObjectNumber", OcaONo.self, "OcaONo", false),
    (OcaPropertyID("1.4"), "Lockable", OcaBoolean.self, "OcaBoolean", false),
    (OcaPropertyID("1.5"), "Role", OcaString.self, "OcaString", false),
    (OcaPropertyID("1.6"), "LockState", OcaLockState.self, "OcaLockState", false),
  ]

  /// `oca` described with the elements of `classes`, which are it and, if asked for,
  /// the classes it derives from.
  private static func descriptor(
    of oca: OcaDeviceClassDescriptor,
    with classes: [OcaDeviceClassDescriptor]
  ) -> OcaClassDescriptor {
    let root = classes.contains { $0.classID == OcaRoot.classID } ? rootProperties.map {
      OcaClassPropertyDescriptor(
        propertyID: $0.id, name: $0.name, typeName: $0.typeName, isReadOnly: true, isStatic: $0.isStatic
      )
    } : []
    return OcaClassDescriptor(
      classID: oca.classID,
      classVersion: oca.classVersion,
      // a generic class, such as OcaBlock<OcaRoot>, by the class's own name
      name: String(String(describing: oca.type).prefix { $0 != "<" }),
      properties: root + classes.flatMap(\.properties).map { property in
        OcaClassPropertyDescriptor(
          propertyID: property.propertyID,
          name: Ocp2Naming.wireName(property.name),
          typeName: Self.typeName(declared: property.typeName, of: property.valueType),
          isReadOnly: !property.isSettable,
          isDeprecated: property.flags.contains(.deprecated)
        )
      },
      methods: methods(of: classes),
      events: classes.flatMap(ownEvents(of:)).map {
        OcaClassEventDescriptor(eventID: $0.eventID, name: $0.name, eventDataTypeName: _ocaTypeName(for: $0.eventDataType))
      },
      isDeprecated: oca.type.classIsDeprecated
    )
  }

  /// The events `oca` itself declares, not those of the classes it derives from.
  private static func ownEvents(of oca: OcaDeviceClassDescriptor) -> [OcaDeviceEventDescriptor] {
    oca.type.deviceEvents.filter { $0.eventID.defLevel == oca.classID.defLevel }
  }

  /// The classes' methods in method ID order, their properties' getters and setters
  /// among them, as the model lists them as operations.
  private static func methods(of classes: [OcaDeviceClassDescriptor]) -> [OcaClassMethodDescriptor] {
    var methods = [OcaMethodID: OcaClassMethodDescriptor]()
    for descriptor in classes.flatMap(\.methods) {
      methods[descriptor.method.methodID] = OcaClassMethodDescriptor(
        methodID: descriptor.method.methodID,
        name: descriptor.method.name,
        parameters: elements(of: descriptor.method).map {
          OcaClassParameterDescriptor(
            name: $0.name, typeName: Self.typeName(declared: $0.declared, of: $0.type), direction: $0.direction
          )
        },
        isDeprecated: descriptor.method.isDeprecated
      )
    }
    for property in classes.flatMap(\.properties) {
      for accessor in accessors(of: property) where methods[accessor.methodID] == nil {
        methods[accessor.methodID] = accessor
      }
    }
    return methods.values.sorted { ($0.methodID.defLevel, $0.methodID.methodIndex) < ($1.methodID.defLevel, $1.methodID.methodIndex) }
  }

  /// A property's getter and setter: the getter returns its value, and a bounded
  /// property's range after it; the setter takes its value. A vector's are its components.
  private static func accessors(of property: OcaDevicePropertyDescriptor) -> [OcaClassMethodDescriptor] {
    let name = Ocp2Naming.wireName(property.name)
    let typeName = Self.typeName(declared: property.typeName, of: property.valueType)
    let values: [OcaClassParameterDescriptor]
    if let components = property.componentNames, let componentType = property.componentType {
      let component = _ocaTypeName(for: componentType)
      values = [components.x, components.y].map {
        OcaClassParameterDescriptor(name: Ocp2Naming.wireName($0), typeName: component, direction: .in)
      }
    } else {
      values = [OcaClassParameterDescriptor(name: property.ocp2SetName, typeName: typeName, direction: .in)]
    }
    var gotten = values.map { OcaClassParameterDescriptor(name: $0.name, typeName: $0.typeName, direction: .out) }
    if property.flags.contains(.bounded), property.componentNames == nil {
      gotten = property.ocp2GetNames.map { OcaClassParameterDescriptor(name: $0, typeName: typeName, direction: .out) }
    } else if property.componentNames == nil, let getName = property.ocp2GetNames.first {
      gotten = [OcaClassParameterDescriptor(name: getName, typeName: typeName, direction: .out)]
    }
    var accessors = [OcaClassMethodDescriptor]()
    if let getMethodID = property.getMethodID {
      accessors.append(OcaClassMethodDescriptor(
        methodID: getMethodID, name: "Get" + name, parameters: gotten,
        isDeprecated: property.flags.contains(.getterDeprecated)
      ))
    }
    if let setMethodID = property.setMethodID {
      accessors.append(OcaClassMethodDescriptor(
        methodID: setMethodID, name: "Set" + name, parameters: values,
        isDeprecated: property.flags.contains(.setterDeprecated)
      ))
    }
    return accessors
  }

  /// What a method takes, then what it returns, each with the type its signature names.
  private static func elements(
    of method: OcaAnyMethodDescriptor
  ) -> [(name: String, type: Any.Type, declared: String?, direction: OcaParameterDirection)] {
    let parameters = method.parameters.map { ($0.name, $0.type as Any.Type, $0.typeName, OcaParameterDirection.in) }
    // a bounded value's signature names one type, which is its value's and both bounds'
    let bounded = method.resultType.map { if case .bounded = OcaDatatypeKind(of: $0) { true } else { false } } ?? false
    let declaredForAll = bounded && method.resultTypeNames?.count == 1 ? method.resultTypeNames?.first : nil
    let results = method.results.map {
      ($0.name, $0.type as Any.Type, $0.typeName ?? declaredForAll, OcaParameterDirection.out)
    }
    return parameters + results
  }

  /// A type by the name it is declared with where that is an AES70 one, such
  /// as `OcaDB`, and by its run-time type's otherwise: a Swift typealias means nothing to a
  /// controller, and a list or map is better named for its elements.
  fileprivate nonisolated static func typeName(declared: String?, of type: Any.Type) -> String {
    let name = _ocaTypeName(for: type)
    guard let declared, declared.hasPrefix("Oca"), !name.hasPrefix("OcaList<"), !name.hasPrefix("OcaMap<")
    else {
      return name
    }
    return declared
  }

  /// The AES70 name of a type: the base types and collections as AES70-2 names them,
  /// anything else by its own name. A typealias such as `OcaDB` is not known at run
  /// time, so it is named for the type it stands for.
  fileprivate nonisolated static func _ocaTypeName(for type: Any.Type) -> String {
    if let describing = type as? any OcaDatatypeDescribing.Type {
      return describing.datatypeDescriptor.name
    }
    if let template = type as? any OcaTemplateDatatype.Type {
      return "\(template.templateName)<\(template.templateArguments.map(_ocaTypeName(for:)).joined(separator: ","))>"
    }
    return switch OcaDatatypeKind(of: type) {
    case let .base(base): base.name
    case .blob: "OcaBlob"
    case .longBlob: "OcaLongBlob"
    case let .optional(wrapped): _ocaTypeName(for: wrapped)
    case let .list(element): "OcaList<\(_ocaTypeName(for: element))>"
    case let .map(key, value): "OcaMap<\(_ocaTypeName(for: key)),\(_ocaTypeName(for: value))>"
    // a bounded property's value is of its type, with the bounds beside it
    case let .bounded(value): _ocaTypeName(for: value)
    case .enumeration, .rawValue, .structure, .other: aes70Spelling(of: String(describing: type))
    }
  }

  /// A Swift type's name with any Swift base type among its generic arguments spelled as
  /// AES70 names it: `OcaInterval<UInt16>` is `OcaInterval<OcaUint16>`.
  private nonisolated static func aes70Spelling(of name: String) -> String {
    guard name.contains("<") else { return name }
    var spelled = ""
    var word = ""
    func flush() {
      spelled += swiftBaseNames[word] ?? word
      word = ""
    }
    for character in name {
      if character.isLetter || character.isNumber {
        word.append(character)
      } else {
        flush()
        // the model writes no space between a template's arguments
        if character != " " { spelled.append(character) }
      }
    }
    flush()
    return spelled
  }

  private nonisolated static let swiftBaseNames = [
    "Bool": "OcaBoolean", "String": "OcaString",
    "Int8": "OcaInt8", "Int16": "OcaInt16", "Int32": "OcaInt32", "Int64": "OcaInt64",
    "UInt8": "OcaUint8", "UInt16": "OcaUint16", "UInt32": "OcaUint32", "UInt64": "OcaUint64",
    "Float": "OcaFloat32", "Double": "OcaFloat64",
  ]
}

/// The datatypes reached from a set of types, each described as the model has it.
private struct Datatypes {
  private(set) var described = [String: OcaDatatypeDescriptor]()

  /// Adds the type, by the name it is declared with if any, and the types it refers to.
  mutating func add(_ type: Any.Type, declared: String?) {
    let name = OcaClassManager.typeName(declared: declared, of: type)
    let own = OcaClassManager._ocaTypeName(for: type)
    if name != own {
      // a typedef, such as OcaDB, of the type the Swift declaration stands for
      guard described[name] == nil else { return }
      described[name] = OcaDatatypeDescriptor(name: name, kind: .typedef, baseTypeName: own)
    }
    add(type)
  }

  private mutating func add(_ type: Any.Type) {
    let name = OcaClassManager._ocaTypeName(for: type)
    guard described[name] == nil else { return }
    defer {
      if type is any OcaDeprecatedDatatype.Type { described[name]?.isDeprecated = true }
    }
    if let describing = type as? any OcaDatatypeDescribing.Type {
      described[name] = describing.datatypeDescriptor
      // the types it refers to are the model's names, with no Swift type to describe
      for referred in describing.referredDatatypes where described[referred.name] == nil {
        described[referred.name] = referred
      }
      for referred in describing.referredTypes {
        add(referred)
      }
      return
    }
    if let template = type as? any OcaTemplateDatatype.Type {
      described[template.templateName] = OcaDatatypeDescriptor(name: template.templateName, kind: .primitive)
      described[name] = OcaDatatypeDescriptor(
        name: name, kind: .template, baseTypeName: template.templateName,
        typeArguments: template.templateArguments.map(OcaClassManager._ocaTypeName(for:))
      )
      for argument in template.templateArguments {
        add(argument)
      }
      return
    }
    switch OcaDatatypeKind(of: type) {
    case .base, .blob, .longBlob:
      described[name] = OcaDatatypeDescriptor(name: name, kind: .primitive)
    case let .optional(wrapped), let .bounded(wrapped):
      add(wrapped)
    case let .list(element):
      described["OcaList"] = OcaDatatypeDescriptor(name: "OcaList", kind: .primitive)
      described[name] = OcaDatatypeDescriptor(
        name: name, kind: .template, baseTypeName: "OcaList",
        typeArguments: [OcaClassManager._ocaTypeName(for: element)]
      )
      add(element)
    case let .map(key, value):
      described["OcaMap"] = OcaDatatypeDescriptor(name: "OcaMap", kind: .primitive)
      described[name] = OcaDatatypeDescriptor(
        name: name, kind: .template, baseTypeName: "OcaMap",
        typeArguments: [OcaClassManager._ocaTypeName(for: key), OcaClassManager._ocaTypeName(for: value)]
      )
      add(key)
      add(value)
    case let .enumeration(cases):
      // the integer it is coded as, which AES70's enum and enumlong tell apart
      let raw = (type as? any RawRepresentable.Type).map { Self.rawType(of: $0) }
      described[name] = OcaDatatypeDescriptor(
        name: name, kind: .enum, baseTypeName: raw.map(OcaClassManager._ocaTypeName(for:)) ?? "",
        items: cases.map { OcaEnumItemDescriptor(name: Ocp2Naming.wireName($0.name), value: $0.value) }
      )
      if let raw { add(raw) }
    case let .rawValue(raw):
      described[name] = OcaDatatypeDescriptor(
        name: name, kind: type is any OptionSet.Type ? .bitset : .typedef,
        baseTypeName: OcaClassManager._ocaTypeName(for: raw)
      )
      add(raw)
    case .structure:
      let fields = Ocp2Encoder.fields(of: type)
      described[name] = OcaDatatypeDescriptor(name: name, kind: .struct, fields: fields.map {
        OcaFieldDescriptor(name: Ocp2Encoder.fieldName($0.name), typeName: OcaClassManager._ocaTypeName(for: $0.type))
      })
      for field in fields {
        add(field.type)
      }
    case .other:
      break
    }
  }

  private static func rawType<R: RawRepresentable>(of _: R.Type) -> Any.Type { R.RawValue.self }
}
