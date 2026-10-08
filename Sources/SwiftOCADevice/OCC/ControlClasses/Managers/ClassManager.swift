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

  @OcaDeviceMethod(SwiftOCA.OcaClassManager.Methods.getControlClass, access: .read)
  func getControlClass(
    classID: OcaClassID,
    includeInherited: OcaBoolean,
    from controller: any OcaController
  ) async throws -> OcaClassDescriptor {
    for object in await objects() {
      let lineage = object.deviceClassDescriptors
      guard let index = lineage.firstIndex(where: { $0.classID == classID }) else { continue }
      let classes = includeInherited ? Array(lineage[...index]) : [lineage[index]]
      return Self.descriptor(of: lineage[index], with: classes)
    }
    throw Ocp1Error.status(.parameterError)
  }

  @OcaDeviceMethod(SwiftOCA.OcaClassManager.Methods.getControlClasses, access: .read)
  func getControlClasses(from controller: any OcaController) async throws -> [OcaClassDescriptor] {
    var described = [OcaClassDescriptor]()
    var seen = Set<OcaClassID>()
    for object in await objects() {
      for oca in object.deviceClassDescriptors where seen.insert(oca.classID).inserted {
        described.append(Self.descriptor(of: oca, with: [oca]))
      }
    }
    return described
  }

  @OcaDeviceMethod(SwiftOCA.OcaClassManager.Methods.getDatatype, access: .read)
  func getDatatype(name: OcaString, from controller: any OcaController) async throws -> OcaDatatypeDescriptor {
    guard let datatype = await datatypes()[name] else { throw Ocp1Error.status(.parameterError) }
    return datatype
  }

  @OcaDeviceMethod(SwiftOCA.OcaClassManager.Methods.getDatatypes, access: .read)
  func getDatatypes(from controller: any OcaController) async throws -> [OcaDatatypeDescriptor] {
    await datatypes().sorted { $0.key < $1.key }.map(\.value)
  }

  /// Every object registered with the device. Taken in object number order only so that
  /// repeated calls agree; GetControlClasses promises no order.
  private func objects() async -> [OcaRoot] {
    guard let device = deviceDelegate else { return [] }
    return await device.objects.sorted { $0.key < $1.key }.map(\.value)
  }

  /// The datatypes the device's classes refer to, by name, and those they refer to in turn.
  private func datatypes() async -> [String: OcaDatatypeDescriptor] {
    var datatypes = Datatypes()
    var seen = Set<OcaClassID>()
    for object in await objects() {
      for oca in object.deviceClassDescriptors where seen.insert(oca.classID).inserted {
        for property in oca.properties {
          datatypes.add(property.valueType, declared: property.typeName)
        }
        for descriptor in oca.methods {
          for element in Self.elements(of: descriptor.method) {
            datatypes.add(element.type, declared: element.declared)
          }
        }
      }
    }
    for root in Self.rootProperties {
      datatypes.add(root.type, declared: root.typeName)
    }
    return datatypes.described
  }

  /// OcaRoot's properties that are not device properties, as the model has them.
  private static let rootProperties: [(id: OcaPropertyID, name: String, type: Any.Type, typeName: String, isStatic: Bool)] = [
    (OcaPropertyID("1.1"), "ClassID", OcaClassID.self, "OcaClassID", true),
    (OcaPropertyID("1.2"), "ClassVersion", OcaClassVersionNumber.self, "OcaClassVersionNumber", true),
    (OcaPropertyID("1.3"), "ObjectNumber", OcaONo.self, "OcaONo", false),
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
          isReadOnly: !property.isSettable
        )
      },
      methods: classes.flatMap(\.methods).map { descriptor in
        OcaClassMethodDescriptor(
          methodID: descriptor.method.methodID,
          name: descriptor.method.name,
          parameters: elements(of: descriptor.method).map {
            OcaClassParameterDescriptor(
              name: $0.name, typeName: Self.typeName(declared: $0.declared, of: $0.type), direction: $0.direction
            )
          }
        )
      }
    )
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
    switch OcaDatatypeKind(of: type) {
    case let .base(base): base.name
    case .blob: "OcaBlob"
    case .longBlob: "OcaLongBlob"
    case let .optional(wrapped): _ocaTypeName(for: wrapped)
    case let .list(element): "OcaList<\(_ocaTypeName(for: element))>"
    case let .map(key, value): "OcaMap<\(_ocaTypeName(for: key)), \(_ocaTypeName(for: value))>"
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
    if let describing = type as? any OcaDatatypeDescribing.Type {
      let descriptor = describing.datatypeDescriptor
      described[name] = descriptor
      // the types it refers to are the model's names, with no Swift type to describe
      for referred in [descriptor.baseTypeName] + descriptor.fields.map(\.typeName) where !referred.isEmpty {
        if described[referred] == nil {
          described[referred] = OcaDatatypeDescriptor(name: referred, kind: .primitive)
        }
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
      described[name] = OcaDatatypeDescriptor(
        name: name, kind: .enum,
        items: cases.map { OcaEnumItemDescriptor(name: Ocp2Naming.wireName($0.name), value: $0.value) }
      )
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
}
