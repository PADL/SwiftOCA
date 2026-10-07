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

/// What a device property declares about itself, for a bridge that presents an object's
/// properties through another control protocol and so has to describe them first.
@_spi(SwiftOCAPrivate)
public struct OcaDevicePropertyDescriptor: Sendable {
  /// The Swift name of the property.
  public let name: String
  public let propertyID: OcaPropertyID
  public let getMethodID: OcaMethodID?
  public let setMethodID: OcaMethodID?
  /// The type a controller reads and writes: the value alone, without the bounds a
  /// bounded property keeps beside it. For a vector property it is the pair.
  public let valueType: any (Codable & Sendable).Type
  /// A vector property is two OCA properties read and written together: `propertyID`
  /// is its x component and this is its y. Nil for any other property.
  public let yPropertyID: OcaPropertyID?
  /// The type of each component of a vector property, which is what its change events
  /// carry, one for each of the two property IDs. Nil for any other property.
  public let componentType: (any (Codable & Sendable).Type)?
  /// What else is known of a property.
  public struct Flags: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// It keeps a range beside its value (`OcaBoundedDeviceProperty`), which its getter
    /// answers with after the value.
    public static let bounded = Flags(rawValue: 1 << 0)
    /// It is the object's label, which AES70 gives several classes under different IDs
    /// (OcaWorker's, OcaAgent's, OcaNetworkApplication's and others).
    public static let label = Flags(rawValue: 1 << 1)
    /// It is the block that contains the object (`OcaOwnable`).
    public static let owner = Flags(rawValue: 1 << 2)
  }

  public let flags: Flags
  /// For a vector property, the names of its two components: the property's name without
  /// its `XY`, with `X` and `Y` after it. Nil for any other property.
  public let componentNames: (x: String, y: String)?
  /// The OCP.2 names of the getter's response parameters. A bounded property has three,
  /// its value first; a vector has none, as its fields name themselves.
  public let ocp2GetNames: [String]
  /// The OCP.2 name of the setter's parameter.
  public let ocp2SetName: String

  /// Whether the property was declared with a setter method. A class can still accept
  /// or refuse a set in its `handleCommand`, whatever this says.
  public var isSettable: Bool { setMethodID != nil }
}

/// A class in an object's lineage with the device properties that class defines.
@_spi(SwiftOCAPrivate)
public struct OcaDeviceClassDescriptor: Sendable {
  /// The Swift class nearest the root that has this class ID.
  public let type: OcaRoot.Type
  public let classID: OcaClassID
  public let classVersion: OcaClassVersionNumber
  /// In property ID order.
  public let properties: [OcaDevicePropertyDescriptor]
  /// The methods the class declares with `@OcaDeviceMethod`, in method ID order. Property
  /// accessors are described by the properties, and hand-written arms not at all.
  public let methods: [OcaDeviceMethodDescriptor]
}

@_spi(SwiftOCAPrivate)
public extension OcaRoot {
  /// Every device property of this object, inherited ones included, in property ID
  /// order. The descriptors are of the class, not of this instance's values.
  var devicePropertyDescriptors: [OcaDevicePropertyDescriptor] {
    allDevicePropertyKeyPaths.compactMap { name, keyPath in
      (self[keyPath: keyPath] as? any OcaDevicePropertyRepresentable)?.description(named: name)
    }.sorted { $0.propertyID < $1.propertyID }
  }

  /// Every method of this object declared with `@OcaDeviceMethod`, inherited ones
  /// included, in method ID order.
  var deviceMethodDescriptors: [OcaDeviceMethodDescriptor] {
    Self.deviceMethods.sorted {
      ($0.methodID.defLevel, $0.methodID.methodIndex) < ($1.methodID.defLevel, $1.methodID.methodIndex)
    }
  }

  /// This object's lineage from `OcaRoot` to its own class, each class with the
  /// properties and methods it defines: those whose ID is at the class's definition level.
  var deviceClassDescriptors: [OcaDeviceClassDescriptor] {
    var lineage = [OcaRoot.Type]()
    var next: AnyClass? = type(of: self)
    while let current = next as? OcaRoot.Type {
      // a Swift subclass that keeps its parent's class ID is the same OCA class
      if lineage.last?.classID == current.classID {
        lineage.removeLast()
      }
      lineage.append(current)
      next = _getSuperclass(current)
    }

    // a class's definition level is its class ID's, not its depth in the lineage, where
    // the Swift classes skip a class the ID names
    let properties = devicePropertyDescriptors
    let methods = deviceMethodDescriptors
    return lineage.reversed().map { type in
      let level = type.classID.defLevel
      return OcaDeviceClassDescriptor(
        type: type,
        classID: type.classID,
        classVersion: type.classVersion,
        properties: properties.filter { $0.propertyID.defLevel == level },
        methods: methods.filter { $0.methodID.defLevel == level }
      )
    }
  }
}

@_spi(SwiftOCAPrivate)
public extension Ocp2Encoder {
  /// The OCP.2 name the encoder gives a field of a composite datatype, from the name
  /// of its Swift property or coding key.
  static func fieldName(_ swiftName: String) -> String {
    Ocp2Naming.wireName(swiftName)
  }

  /// The stored properties of a composite datatype and their types, in declaration
  /// order, read from its metadata: its fields, where its coding is synthesised.
  static func fields(of type: Any.Type) -> [(name: String, type: Any.Type)] {
    Ocp2Naming.fields(of: type)
  }
}

private extension OcaDevicePropertyRepresentable {
  /// The classes that have a label or an owner all call it by the same Swift name.
  func flags(named name: String) -> OcaDevicePropertyDescriptor.Flags {
    var flags: OcaDevicePropertyDescriptor.Flags = []
    if self is any _OcaBoundedDevicePropertyRepresentable { flags.insert(.bounded) }
    if name == "label", valueType == OcaString.self { flags.insert(.label) }
    if name == "owner", valueType == OcaONo.self { flags.insert(.owner) }
    return flags
  }

  func description(named name: String) -> OcaDevicePropertyDescriptor {
    OcaDevicePropertyDescriptor(
      name: name,
      propertyID: propertyID,
      getMethodID: getMethodID,
      setMethodID: setMethodID,
      valueType: valueType,
      yPropertyID: vectorComponents?.yPropertyID,
      componentType: vectorComponents?.type,
      flags: flags(named: name),
      componentNames: vectorComponents.map { _ in
        let stem = name.hasSuffix("XY") ? String(name.dropLast(2)) : name
        return (stem + "X", stem + "Y")
      },
      ocp2GetNames: responseNames(propertyName: name),
      ocp2SetName: setName(propertyName: name)
    )
  }
}
