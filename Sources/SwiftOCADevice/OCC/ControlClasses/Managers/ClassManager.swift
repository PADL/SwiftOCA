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
@OcaDeviceMethods
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
      name: name(of: oca.type),
      properties: classes.flatMap(\.properties).map { property in
        OcaClassPropertyDescriptor(
          propertyID: property.propertyID,
          name: property.name,
          typeName: name(of: property.valueType),
          isReadOnly: !property.isSettable
        )
      },
      methods: classes.flatMap(\.methods).map { descriptor in
        let method = descriptor.method
        return OcaClassMethodDescriptor(
          methodID: method.methodID,
          name: method.name,
          parameters: parameters(of: method),
          resultTypeName: method.resultType.map(name(of:)) ?? ""
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
        return OcaClassParameterDescriptor(name: name, typeName: Self.name(of: field.type))
      }
    }
    return [OcaClassParameterDescriptor(name: method.parameterNames?.first ?? "Value", typeName: name(of: type))]
  }

  /// A Swift type's name, as a controller would recognise it.
  private static func name(of type: Any.Type) -> String {
    String(describing: type)
  }
}
