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

// the class manager uses Foundation, which embedded builds lack
#if NonEmbeddedBuild
/// The device's class manager (see `SwiftOCA.OcaClassManager`). It describes the classes
/// of the device's objects to a controller from what the device knows of them.
///
/// A typedef is named as such only where a declaration records it: a property's type, or a
/// method's as `@OcaMethod` writes it. Elsewhere, such as a struct's fields, a Swift
/// typealias is not known at run time, and the typedef is named as the type it stands for.
@OcaDeviceClass
public final class OcaClassManager: OcaManager {
  override public class var classID: OcaClassID { SwiftOCA.OcaClassManager.classID }

  /// Registers with the device, which tells it of objects from then on, and describes
  /// those the device already has. A device has one only if it makes one.
  public convenience init(deviceDelegate: OcaDevice? = nil) async throws {
    try await self.init(
      objectNumber: OcaClassManagerONo,
      role: "ClassManager",
      deviceDelegate: deviceDelegate,
      addToRootBlock: false
    )
    guard let deviceDelegate else { return }
    for object in Array(await deviceDelegate.objects.values) {
      record(object)
    }
    describeAfresh()
  }

  /// Every class of the device's objects, each once and with only its own elements, in
  /// class ID order.
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

  /// The path of the device's class model as an XMI document, resolved against the
  /// address a controller connected to; empty when the model is not served.
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.5")
  )
  public var modelURL = OcaString()

  @OcaDeviceMethod(SwiftOCA.OcaClassManager.Methods.getControlClass, access: .read)
  func getControlClass(
    classID: OcaClassID,
    includeInherited: OcaBoolean,
    from controller: any OcaController
  ) async throws -> OcaClassDescriptor {
    guard let lineage = lineages[classID]?.lineage else { throw Ocp1Error.status(.parameterError) }
    return Self.descriptor(for: lineage.last!, with: includeInherited ? lineage : [lineage.last!])
  }

  @OcaDeviceMethod(SwiftOCA.OcaClassManager.Methods.getDatatype, access: .read)
  func getDatatype(name: OcaString, from controller: any OcaController) async throws -> OcaDatatypeDescriptor {
    guard let datatype = described.described[name] else { throw Ocp1Error.status(.parameterError) }
    return datatype
  }

  /// The registered objects' Swift classes, each with its objects, its name and its OCA
  /// classes, root first.
  private var registered = [ObjectIdentifier: (objects: Set<ObjectIdentifier>, name: String, lineage: [OcaDeviceClassDescriptor])]()
  /// Each OCA class of the device's objects with the classes it derives from, root first,
  /// described by the Swift class of smallest name among those that have it.
  private var lineages = [OcaClassID: (describer: String, lineage: [OcaDeviceClassDescriptor])]()
  private var described = Datatypes()

  /// Notes an object, returning its Swift class's name and lineage if it is the first of it.
  @discardableResult
  private func record(_ object: OcaRoot) -> (name: String, lineage: [OcaDeviceClassDescriptor])? {
    let key = ObjectIdentifier(type(of: object))
    if registered[key] != nil {
      registered[key]!.objects.insert(ObjectIdentifier(object))
      return nil
    }
    let name = String(reflecting: type(of: object))
    let lineage = object.deviceClassDescriptors
    registered[key] = ([ObjectIdentifier(object)], name, lineage)
    return (name, lineage)
  }

  /// Called by the device as it registers an object. Only an object of a Swift class the
  /// device has no other object of can bring classes to describe.
  func didRegister(object: OcaRoot) {
    guard let (name, lineage) = record(object) else { return }
    // Swift classes keeping their parent's class ID can describe it differently: the one of
    // smaller name describes it anew. An ancestor keeps its first describer's elements.
    if let leaf = lineage.last, lineages[leaf.classID].map({ name < $0.describer }) ?? false {
      describeAfresh()
    } else {
      describe([(name, lineage)], afresh: false)
    }
  }

  /// Called by the device as it deregisters an object. When the last object of a Swift
  /// class that describes a class goes, the classes are described afresh from the rest.
  func didDeregister(object: OcaRoot) {
    let key = ObjectIdentifier(type(of: object))
    guard var entry = registered[key] else { return }
    entry.objects.remove(ObjectIdentifier(object))
    guard entry.objects.isEmpty else {
      registered[key] = entry
      return
    }
    registered[key] = nil
    if lineages.values.contains(where: { $0.describer == entry.name }) {
      describeAfresh()
    }
  }

  private func describeAfresh() {
    describe(registered.values.map { ($0.name, $0.lineage) }.sorted { $0.0 < $1.0 }, afresh: true)
  }

  /// Adds the classes of `lineages` not yet described, or describes only them if `afresh`,
  /// setting each list once, so that a subscriber sees one change.
  private func describe(_ lineages: [(name: String, lineage: [OcaDeviceClassDescriptor])], afresh: Bool) {
    if afresh {
      self.lineages = [:]
      described = Datatypes()
    }
    var classes = afresh ? [] : controlClasses
    for (name, lineage) in lineages {
      for index in lineage.indices where self.lineages[lineage[index].classID] == nil {
        let oca = lineage[index]
        self.lineages[oca.classID] = (name, Array(lineage[...index]))
        classes.append(Self.descriptor(for: oca, with: [oca]))
        addDatatypes(for: oca)
      }
    }
    // the properties skip a value equal to the one they hold
    controlClasses = classes.sorted { $0.classID.fields.lexicographicallyPrecedes($1.classID.fields) }
    datatypes = described.described.sorted { $0.key < $1.key }.map(\.value)
  }

  /// Adds the datatypes `oca`'s own elements refer to, and those they refer to in turn.
  private func addDatatypes(for oca: OcaDeviceClassDescriptor) {
    for property in oca.properties {
      if let componentType = property.componentType {
        described.add(componentType, declared: Self.componentTypeName(declared: property.typeName))
      } else {
        described.add(property.valueType, declared: property.typeName)
      }
    }
    for descriptor in oca.methods {
      for element in Self.elements(for: descriptor.method) {
        described.add(element.type, declared: element.declared)
      }
    }
    for event in Self.ownEvents(for: oca) {
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
  /// the classes it derives from. Documentation is left empty: the device does not carry
  /// the model's text, and Swift's doc comments are not it.
  private static func descriptor(
    for oca: OcaDeviceClassDescriptor,
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
      properties: root + classes.flatMap(\.properties).flatMap { property in
        // a vector property is two of the model's, X and Y, read and written together
        let components: [(OcaPropertyID, String, Any.Type, String?)] =
          if let yPropertyID = property.yPropertyID, let componentType = property.componentType {
            [(property.propertyID, "X", componentType, Self.componentTypeName(declared: property.typeName)),
             (yPropertyID, "Y", componentType, Self.componentTypeName(declared: property.typeName))]
          } else {
            [(property.propertyID, Ocp2Naming.wireName(property.name), property.valueType, property.typeName)]
          }
        return components.map { id, name, type, declared in
          OcaClassPropertyDescriptor(
            propertyID: id,
            name: name,
            typeName: Self.typeName(declared: declared, for: type),
            isReadOnly: !property.isSettable,
            isDeprecated: property.deprecation.contains(.property)
          )
        }
      },
      methods: methods(for: classes),
      events: classes.flatMap(ownEvents(for:)).map {
        OcaClassEventDescriptor(eventID: $0.eventID, name: $0.name, parameters: [OcaClassParameterDescriptor(
          name: "EventData", typeName: _ocaTypeName(for: $0.eventDataType), direction: .in
        )])
      },
      isDeprecated: oca.type is any OcaDeprecated.Type
    )
  }

  /// The events `oca` itself declares, not those of the classes it derives from.
  private static func ownEvents(for oca: OcaDeviceClassDescriptor) -> [OcaDeviceEventDescriptor] {
    oca.type.deviceEvents.filter { $0.eventID.defLevel == oca.classID.defLevel }
  }

  /// The classes' methods in method ID order, their properties' getters and setters
  /// among them, as the model lists them as operations.
  private static func methods(for classes: [OcaDeviceClassDescriptor]) -> [OcaClassMethodDescriptor] {
    let declared = classes.flatMap(\.methods).map { descriptor in
      (descriptor.method.methodID, OcaClassMethodDescriptor(
        methodID: descriptor.method.methodID,
        name: descriptor.method.name,
        parameters: elements(for: descriptor.method).map {
          OcaClassParameterDescriptor(
            name: $0.name, typeName: Self.typeName(declared: $0.declared, for: $0.type), direction: $0.direction
          )
        },
        isDeprecated: descriptor.method.isDeprecated
      ))
    }
    // a declared method stands in for a property's accessor of the same ID
    let methods = Dictionary(declared) { _, last in last }
      .merging(classes.flatMap(\.properties).flatMap(accessors(for:)).map { ($0.methodID, $0) }) { kept, _ in kept }
    return methods.values.sorted { $0.methodID < $1.methodID }
  }

  /// A property's getter and setter: the getter returns its value, and a bounded
  /// property's range after it; the setter takes its value. A vector's are its components.
  private static func accessors(for property: OcaDevicePropertyDescriptor) -> [OcaClassMethodDescriptor] {
    let name = Ocp2Naming.wireName(property.name)
    let values: [OcaClassParameterDescriptor]
    var gotten: [OcaClassParameterDescriptor]
    if let componentType = property.componentType {
      let component = Self.typeName(declared: Self.componentTypeName(declared: property.typeName), for: componentType)
      values = ["X", "Y"].map { OcaClassParameterDescriptor(name: $0, typeName: component, direction: .in) }
      gotten = values.map { OcaClassParameterDescriptor(name: $0.name, typeName: $0.typeName, direction: .out) }
    } else {
      let typeName = Self.typeName(declared: property.typeName, for: property.valueType)
      values = [OcaClassParameterDescriptor(name: property.ocp2SetName, typeName: typeName, direction: .in)]
      // a bounded property's getter returns its range after its value
      gotten = property.ocp2GetNames.map { OcaClassParameterDescriptor(name: $0, typeName: typeName, direction: .out) }
    }
    var accessors = [OcaClassMethodDescriptor]()
    if let getMethodID = property.getMethodID {
      accessors.append(OcaClassMethodDescriptor(
        methodID: getMethodID, name: property.accessorNames.get ?? "Get" + name, parameters: gotten,
        isDeprecated: property.deprecation.contains(.getter)
      ))
    }
    if let setMethodID = property.setMethodID {
      accessors.append(OcaClassMethodDescriptor(
        methodID: setMethodID, name: property.accessorNames.set ?? "Set" + name, parameters: values,
        isDeprecated: property.deprecation.contains(.setter)
      ))
    }
    return accessors
  }

  /// What a method takes, then what it returns, each with the type its signature names.
  private static func elements(
    for method: OcaAnyMethodDescriptor
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
  /// controller, and a list or map is better named for its elements. A template is named
  /// for itself (OcaList2D, not OcaArray2D), or as declared where that is an instance of it.
  fileprivate nonisolated static func typeName(declared: String?, for type: Any.Type) -> String {
    let name = _ocaTypeName(for: type)
    guard let declared, declared.hasPrefix("Oca") else { return name }
    if let template = type as? any OcaTemplateDatatype.Type {
      return declared.hasPrefix(template.templateName + "<") ? declared : name
    }
    guard !name.hasPrefix("OcaList<"), !name.hasPrefix("OcaMap<") else { return name }
    return declared
  }

  /// The argument a vector property's components are declared with, from its type's name.
  fileprivate nonisolated static func componentTypeName(declared: String?) -> String? {
    declared.flatMap(templateArguments(of:))?.first
  }

  /// The arguments of a template instance's name, `OcaMap<OcaONo,OcaList<OcaString>>`
  /// giving `OcaONo` and `OcaList<OcaString>`; nil for a name that is not one.
  fileprivate nonisolated static func templateArguments(of name: String) -> [String]? {
    guard let open = name.firstIndex(of: "<"), name.hasSuffix(">") else { return nil }
    var arguments = [String]()
    var argument = ""
    var depth = 0
    for character in name[name.index(after: open)..<name.index(before: name.endIndex)] {
      switch character {
      case "<": depth += 1
      case ">": depth -= 1
      case "," where depth == 0:
        arguments.append(argument)
        argument = ""
        continue
      case " ": continue
      default: break
      }
      argument.append(character)
    }
    arguments.append(argument)
    return arguments
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
    case .enumeration, .rawValue, .structure, .other: String(describing: type)
    }
  }
}

/// The datatypes reached from a set of types, each described as the model has it.
private struct Datatypes {
  private(set) var described = [String: OcaDatatypeDescriptor]()

  /// Adds the type, by the name it is declared with if any, and the types it refers to.
  mutating func add(_ type: Any.Type, declared: String?) {
    let name = OcaClassManager.typeName(declared: declared, for: type)
    let own = OcaClassManager._ocaTypeName(for: type)
    guard name != own else { return add(type) }
    guard described[name] == nil else { return }
    if let template = type as? any OcaTemplateDatatype.Type,
       let arguments = OcaClassManager.templateArguments(of: name)
    {
      // an instance declared with typedef arguments, OcaVector2D<OcaMatrixCoordinate>:
      // each such argument is a typedef of the run-time one
      add(template: template, named: name, arguments: arguments)
      for (argument, runtime) in zip(arguments, template.templateArguments) {
        add(runtime, declared: argument)
      }
      return
    }
    // a typedef, such as OcaDB, of the type the Swift declaration stands for
    described[name] = OcaDatatypeDescriptor(name: name, kind: .typedef, baseTypeName: own)
    add(type)
  }

  /// A template and an instance of it with these arguments' names.
  private mutating func add(template: any OcaTemplateDatatype.Type, named name: String, arguments: [String]) {
    if described[template.templateName] == nil {
      described[template.templateName] = template.templateDescriptor
    }
    described[name] = OcaDatatypeDescriptor(
      name: name, kind: .template, baseTypeName: template.templateName, typeArguments: arguments
    )
    for referred in template.templateReferredTypes {
      add(referred)
    }
  }

  private mutating func add(_ type: Any.Type) {
    let name = OcaClassManager._ocaTypeName(for: type)
    guard described[name] == nil else { return }
    defer {
      if type is any OcaDeprecated.Type { described[name]?.isDeprecated = true }
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
      add(template: template, named: name, arguments: template.templateArguments.map(OcaClassManager._ocaTypeName(for:)))
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
      let raw = (type as? any RawRepresentable.Type).map { Self.rawType(for: $0) }
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
      let fields = Ocp2Naming.fields(of: type)
      described[name] = OcaDatatypeDescriptor(name: name, kind: .struct, fields: fields.map {
        OcaFieldDescriptor(name: Ocp2Naming.wireName($0.name), typeName: OcaClassManager._ocaTypeName(for: $0.type))
      })
      for field in fields {
        add(field.type)
      }
    case .other:
      break
    }
  }

  private static func rawType<R: RawRepresentable>(for _: R.Type) -> Any.Type { R.RawValue.self }
}
#endif
