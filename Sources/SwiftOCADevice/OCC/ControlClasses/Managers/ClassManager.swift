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

  public nonisolated static let objectNumber = SwiftOCA.OcaClassManager.objectNumber

  public convenience init(deviceDelegate: OcaDevice? = nil) async throws {
    try await self.init(
      objectNumber: Self.objectNumber,
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
          typeName: Self._ocaTypeName(for: property.valueType),
          isReadOnly: !property.isSettable
        )
      },
      methods: classes.flatMap(\.methods).map { descriptor in
        let method = descriptor.method
        return OcaClassMethodDescriptor(
          methodID: method.methodID,
          name: method.name,
          parameters: parameters(of: method),
          resultTypeName: method.resultType.map(Self._ocaTypeName(for:)) ?? ""
        )
      }
    )
  }

  /// A method's parameters: the fields of its record, or its one parameter.
  private static func parameters(of method: OcaAnyMethodDescriptor) -> [OcaClassParameterDescriptor] {
    guard let type = method.parametersType else { return [] }
    if type is any OcaParametersReflectable.Type {
      let fields = Ocp2Encoder.fields(of: type)
      return fields.enumerated().map { index, field in
        let name = method.parameterNames.flatMap { index < $0.count ? $0[index] : nil }
          ?? Ocp2Encoder.fieldName(field.name)
        return OcaClassParameterDescriptor(name: name, typeName: Self._ocaTypeName(for: field.type))
      }
    }
    return [OcaClassParameterDescriptor(name: method.parameterNames?.first ?? "Value", typeName: Self._ocaTypeName(for: type))]
  }

  /// The AES70 name of a type: the base types and collections as AES70-2 names them,
  /// anything else by its own name. A typealias such as `OcaDB` is not known at run
  /// time, so it is named for the type it stands for.
  fileprivate nonisolated static func _ocaTypeName(for type: Any.Type) -> String {
    if let type = type as? any OcaTypeNamed.Type { return type.ocaTypeName }
    return switch type {
    case is Bool.Type: "OcaBoolean"
    case is Int8.Type: "OcaInt8"
    case is Int16.Type: "OcaInt16"
    case is Int32.Type: "OcaInt32"
    case is Int64.Type: "OcaInt64"
    case is UInt8.Type: "OcaUint8"
    case is UInt16.Type: "OcaUint16"
    case is UInt32.Type: "OcaUint32"
    case is UInt64.Type: "OcaUint64"
    case is Float.Type: "OcaFloat32"
    case is Double.Type: "OcaFloat64"
    case is String.Type: "OcaString"
    case is LengthTaggedData16.Type: "OcaBlob"
    case is LengthTaggedData32.Type: "OcaLongBlob"
    default: String(describing: type)
    }
  }
}

/// A generic type whose AES70 name is made from its parameters' AES70 names.
private protocol OcaTypeNamed {
  static var ocaTypeName: String { get }
}

extension Array: OcaTypeNamed {
  fileprivate static var ocaTypeName: String { "OcaList<\(OcaClassManager._ocaTypeName(for: Element.self))>" }
}

extension Dictionary: OcaTypeNamed {
  fileprivate static var ocaTypeName: String {
    "OcaMap<\(OcaClassManager._ocaTypeName(for: Key.self)), \(OcaClassManager._ocaTypeName(for: Value.self))>"
  }
}

// AES70 has no optional type: a value that may be absent is of the type it holds
extension Optional: OcaTypeNamed {
  fileprivate static var ocaTypeName: String { OcaClassManager._ocaTypeName(for: Wrapped.self) }
}

// a bounded property's value is of its type, with the bounds beside it
extension OcaBoundedPropertyValue: OcaTypeNamed {
  fileprivate static var ocaTypeName: String { OcaClassManager._ocaTypeName(for: Value.self) }
}
