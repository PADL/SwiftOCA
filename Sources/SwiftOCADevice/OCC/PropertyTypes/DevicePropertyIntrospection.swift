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
/// Which of a device property and its accessors the model deprecates. A property is
/// renamed by deprecating a copy, so its accessors can be deprecated while it is not.
public struct OcaPropertyDeprecation: OptionSet, Sendable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }

  public static let property = Self(rawValue: 1 << 0)
  public static let getter = Self(rawValue: 1 << 1)
  public static let setter = Self(rawValue: 1 << 2)
  public static let all: Self = [.property, .getter, .setter]
}

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
  /// The AES70 name of the type the property is declared with, which keeps a typealias
  /// such as `OcaDB` that `valueType` cannot.
  public let typeName: String?
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
    /// The model deprecates the property, its getter, or its setter.
    public static let deprecated = Flags(rawValue: 1 << 3)
    public static let getterDeprecated = Flags(rawValue: 1 << 4)
    public static let setterDeprecated = Flags(rawValue: 1 << 5)
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
    // which of the class's properties are its label and its owner, as the class says
    let label = (self as? any OcaLabelRepresentable).map { type(of: $0).labelPropertyID }
    let owner = (self as? any OcaOwnable).map { type(of: $0).ownerPropertyID }
    let typeNames = type(of: self).devicePropertyTypeNames
    let deprecations = type(of: self).devicePropertyDeprecations
    return allDevicePropertyKeyPaths.compactMap { name, keyPath in
      guard let property = self[keyPath: keyPath] as? any OcaDevicePropertyRepresentable else { return nil }
      var flags: OcaDevicePropertyDescriptor.Flags = []
      if property is any _OcaBoundedDevicePropertyRepresentable { flags.insert(.bounded) }
      if property.propertyID == label { flags.insert(.label) }
      if property.propertyID == owner { flags.insert(.owner) }
      let deprecation = deprecations[name] ?? []
      if deprecation.contains(.property) { flags.insert(.deprecated) }
      if deprecation.contains(.getter) { flags.insert(.getterDeprecated) }
      if deprecation.contains(.setter) { flags.insert(.setterDeprecated) }
      return property.description(named: name, typeName: typeNames[name], flags: flags)
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
  func description(
    named name: String,
    typeName: String?,
    flags: OcaDevicePropertyDescriptor.Flags
  ) -> OcaDevicePropertyDescriptor {
    OcaDevicePropertyDescriptor(
      name: name,
      propertyID: propertyID,
      getMethodID: getMethodID,
      setMethodID: setMethodID,
      valueType: valueType,
      typeName: typeName,
      yPropertyID: vectorComponents?.yPropertyID,
      componentType: vectorComponents?.type,
      flags: flags,
      componentNames: vectorComponents.map { _ in
        let stem = name.hasSuffix("XY") ? String(name.dropLast(2)) : name
        return (stem + "X", stem + "Y")
      },
      ocp2GetNames: responseNames(propertyName: name),
      ocp2SetName: setName(propertyName: name)
    )
  }
}

/// An event a device class emits: its ID, its model name and the data it carries.
public struct OcaDeviceEventDescriptor: Sendable {
  public let eventID: OcaEventID
  public let name: String
  public let eventDataType: any (Codable & Sendable).Type

  public init(eventID: OcaEventID, name: String, eventDataType: any (Codable & Sendable).Type) {
    self.eventID = eventID
    self.name = name
    self.eventDataType = eventDataType
  }
}
