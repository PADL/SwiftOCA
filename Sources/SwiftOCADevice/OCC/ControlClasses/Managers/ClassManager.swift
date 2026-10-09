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

  /// Every object registered with the device. Taken in object number order only so that
  /// repeated calls agree; GetControlClasses promises no order.
  private func objects() async -> [OcaRoot] {
    guard let device = deviceDelegate else { return [] }
    return await device.objects.sorted { $0.key < $1.key }.map(\.value)
  }

  /// `oca` described with the elements of `classes`, which are it and, if asked for,
  /// the classes it derives from.
  private static func descriptor(
    of oca: OcaDeviceClassDescriptor,
    with classes: [OcaDeviceClassDescriptor]
  ) -> OcaClassDescriptor {
    OcaClassDescriptor(
      classID: oca.classID,
      classVersion: oca.classVersion,
      // a generic class, such as OcaBlock<OcaRoot>, by the class's own name
      name: String(String(describing: oca.type).prefix { $0 != "<" }),
      properties: classes.flatMap(\.properties).map { property in
        OcaClassPropertyDescriptor(
          propertyID: property.propertyID,
          name: property.name,
          typeName: Self.typeName(declared: property.typeName, of: property.valueType),
          isReadOnly: !property.isSettable
        )
      },
      methods: classes.flatMap(\.methods).map { descriptor in
        let method = descriptor.method
        return OcaClassMethodDescriptor(
          methodID: method.methodID,
          name: method.name,
          parameters: parameters(of: method),
          resultTypeName: method.resultType.map { type in
            let declared = method.resultTypeNames?.count == 1 ? method.resultTypeNames?.first : nil
            return Self.typeName(declared: declared, of: type)
          } ?? ""
        )
      }
    )
  }

  /// A method's parameters: the fields of its record, or its one parameter.
  private static func parameters(of method: OcaAnyMethodDescriptor) -> [OcaClassParameterDescriptor] {
    guard let type = method.parametersType else { return [] }
    if type is any OcaParametersReflectable.Type {
      let fields = Ocp2Naming.fields(of: type)
      let declared = OcaAnyMethodDescriptor.declaredNames(
        method.parameterTypeNames, fieldCount: fields.count, isRecord: true
      )
      return fields.enumerated().map { index, field in
        let name = method.parameterNames.flatMap { index < $0.count ? $0[index] : nil }
          ?? Ocp2Naming.wireName(field.name)
        return OcaClassParameterDescriptor(
          name: name,
          typeName: Self.typeName(declared: declared?[index], of: field.type)
        )
      }
    }
    let declared = method.parameterTypeNames?.count == 1 ? method.parameterTypeNames?.first : nil
    return [OcaClassParameterDescriptor(
      name: method.parameterNames?.first ?? "Value",
      typeName: Self.typeName(declared: declared, of: type)
    )]
  }

  /// A type by the name it is declared with where that is an AES70 one, such
  /// as `OcaDB`, and by its run-time type's otherwise: a Swift typealias means nothing to a
  /// controller, and a list or map is better named for its elements.
  private nonisolated static func typeName(declared: String?, of type: Any.Type) -> String {
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
#endif
