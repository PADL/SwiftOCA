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

// What a class manager says of a device's classes and datatypes, shaped as the AES70-2
// model describes them: a method's parameters each with a direction, types by their model
// names, and datatypes as primitives, typedefs, structs, enums and template instances.
// Each corresponds to an MS-05-02 descriptor, with OCA's IDs and names.

/// A control class: its own properties and methods, or with those of the classes it
/// derives from too where they were asked for.
public struct OcaClassDescriptor: Codable, Sendable, Equatable {
  public var classID: OcaClassID
  public var classVersion: OcaClassVersionNumber
  public var name: OcaString
  public var properties: [OcaClassPropertyDescriptor]
  /// Every method, property accessors included, as the model lists its operations.
  public var methods: [OcaClassMethodDescriptor]
  public var events: [OcaClassEventDescriptor]
  /// The model marks it deprecated.
  public var isDeprecated: OcaBoolean

  public init(
    classID: OcaClassID,
    classVersion: OcaClassVersionNumber,
    name: OcaString,
    properties: [OcaClassPropertyDescriptor],
    methods: [OcaClassMethodDescriptor],
    events: [OcaClassEventDescriptor] = [],
    isDeprecated: OcaBoolean = false
  ) {
    self.classID = classID
    self.classVersion = classVersion
    self.name = name
    self.properties = properties
    self.methods = methods
    self.events = events
    self.isDeprecated = isDeprecated
  }
}

/// An event, by its OCA ID and model name, with the model name of the data it carries.
public struct OcaClassEventDescriptor: Codable, Sendable, Equatable {
  public var eventID: OcaEventID
  public var name: OcaString
  public var eventDataTypeName: OcaString
  /// The model marks it deprecated.
  public var isDeprecated: OcaBoolean

  public init(
    eventID: OcaEventID,
    name: OcaString,
    eventDataTypeName: OcaString,
    isDeprecated: OcaBoolean = false
  ) {
    self.eventID = eventID
    self.name = name
    self.eventDataTypeName = eventDataTypeName
    self.isDeprecated = isDeprecated
  }
}

/// A property, by its OCA ID and model name; read only where it has no setter, static where
/// it is of the class (as ClassID is). Unlike IS-12's it has no constraints: a bounded
/// property's range is the object's, from its getter, like IS-12's runtime constraints.
public struct OcaClassPropertyDescriptor: Codable, Sendable, Equatable {
  public var propertyID: OcaPropertyID
  public var name: OcaString
  public var typeName: OcaString
  public var isReadOnly: OcaBoolean
  public var isStatic: OcaBoolean
  /// The model marks it deprecated.
  public var isDeprecated: OcaBoolean

  public init(
    propertyID: OcaPropertyID,
    name: OcaString,
    typeName: OcaString,
    isReadOnly: OcaBoolean,
    isStatic: OcaBoolean = false,
    isDeprecated: OcaBoolean = false
  ) {
    self.propertyID = propertyID
    self.name = name
    self.typeName = typeName
    self.isReadOnly = isReadOnly
    self.isStatic = isStatic
    self.isDeprecated = isDeprecated
  }
}

/// A method, by its OCA ID and model name, with its parameters in order: what it takes,
/// then what it returns. Every method also returns an `OcaStatus`, which is not listed.
public struct OcaClassMethodDescriptor: Codable, Sendable, Equatable {
  public var methodID: OcaMethodID
  public var name: OcaString
  public var parameters: [OcaClassParameterDescriptor]
  /// The model marks it deprecated.
  public var isDeprecated: OcaBoolean

  public init(
    methodID: OcaMethodID,
    name: OcaString,
    parameters: [OcaClassParameterDescriptor],
    isDeprecated: OcaBoolean = false
  ) {
    self.methodID = methodID
    self.name = name
    self.parameters = parameters
    self.isDeprecated = isDeprecated
  }
}

/// Whether a method takes a parameter, returns it, or both.
public enum OcaParameterDirection: OcaUint8, Codable, Sendable, CaseIterable {
  case `in` = 1
  case out = 2
  case `inout` = 3
}

/// A method parameter, by its model name, with the model name of its type.
public struct OcaClassParameterDescriptor: Codable, Sendable, Equatable {
  public var name: OcaString
  public var typeName: OcaString
  public var direction: OcaParameterDirection

  public init(name: OcaString, typeName: OcaString, direction: OcaParameterDirection) {
    self.name = name
    self.typeName = typeName
    self.direction = direction
  }
}

/// The kinds of datatype the AES70-2 model has, by their stereotypes.
public enum OcaDatatypeDescriptorKind: OcaUint8, Codable, Sendable, CaseIterable {
  /// A base type, or a blob.
  case primitive = 1
  /// Another name for the type `baseTypeName`.
  case typedef = 2
  /// A record of named `fields`.
  case `struct` = 3
  /// A set of named `items`.
  case `enum` = 4
  /// A template, `baseTypeName`, given `typeArguments`: `OcaList<OcaONo>`.
  case template = 5
  /// Flags, each a bit of the integer type `baseTypeName`.
  case bitset = 6
}

/// A datatype, by its model name. Only the members its kind has are filled: an enum's or
/// a bitset's `baseTypeName` is the integer it is coded as, and a struct's `typeArguments`
/// are its type parameters, which its fields may name (`DT`).
public struct OcaDatatypeDescriptor: Codable, Sendable, Equatable {
  public var name: OcaString
  public var kind: OcaDatatypeDescriptorKind
  public var baseTypeName: OcaString
  public var typeArguments: [OcaString]
  public var fields: [OcaFieldDescriptor]
  public var items: [OcaEnumItemDescriptor]
  /// The model marks it deprecated.
  public var isDeprecated: OcaBoolean

  public init(
    name: OcaString,
    kind: OcaDatatypeDescriptorKind,
    baseTypeName: OcaString = "",
    typeArguments: [OcaString] = [],
    fields: [OcaFieldDescriptor] = [],
    items: [OcaEnumItemDescriptor] = [],
    isDeprecated: OcaBoolean = false
  ) {
    self.name = name
    self.kind = kind
    self.baseTypeName = baseTypeName
    self.typeArguments = typeArguments
    self.fields = fields
    self.items = items
    self.isDeprecated = isDeprecated
  }
}

/// A field of a struct, by its model name, with the model name of its type.
public struct OcaFieldDescriptor: Codable, Sendable, Equatable {
  public var name: OcaString
  public var typeName: OcaString
  /// The model marks it deprecated.
  public var isDeprecated: OcaBoolean

  public init(name: OcaString, typeName: OcaString, isDeprecated: OcaBoolean = false) {
    self.name = name
    self.typeName = typeName
    self.isDeprecated = isDeprecated
  }
}

/// An item of an enum, by its model name, with its value.
public struct OcaEnumItemDescriptor: Codable, Sendable, Equatable {
  public var name: OcaString
  public var value: OcaInt64
  /// The model marks it deprecated.
  public var isDeprecated: OcaBoolean

  public init(name: OcaString, value: OcaInt64, isDeprecated: OcaBoolean = false) {
    self.name = name
    self.value = value
    self.isDeprecated = isDeprecated
  }
}

/// A datatype whose Swift declaration is not how it is coded, which says how the model
/// describes it instead: `OcaClassID`, coded as a count and its fields.
@_spi(SwiftOCAPrivate)
public protocol OcaDatatypeDescribing {
  static var datatypeDescriptor: OcaDatatypeDescriptor { get }
  /// The datatypes the descriptor refers to by name, which have no Swift type.
  static var referredDatatypes: [OcaDatatypeDescriptor] { get }
  /// The Swift types the descriptor refers to, which describe themselves.
  static var referredTypes: [Any.Type] { get }
}

@_spi(SwiftOCAPrivate)
public extension OcaDatatypeDescribing {
  static var referredDatatypes: [OcaDatatypeDescriptor] { [] }
  static var referredTypes: [Any.Type] { [] }
}

/// A datatype the model marks deprecated.
@_spi(SwiftOCAPrivate)
public protocol OcaDeprecatedDatatype {}

/// A generic datatype coded as an AES70 template: `OcaArray2D<OcaONo>` is
/// `OcaList2D<OcaONo>`, two counts and then the elements.
@_spi(SwiftOCAPrivate)
public protocol OcaTemplateDatatype {
  static var templateName: String { get }
  static var templateArguments: [Any.Type] { get }
}

@_spi(SwiftOCAPrivate)
extension OcaArray2D: OcaTemplateDatatype {
  public static var templateName: String { "OcaList2D" }
  public static var templateArguments: [Any.Type] { [Element.self] }
}

/// A fixed-length blob of `length` bytes, as a datatype descriptor names it.
private func fixedLengthBlobs(_ lengths: [Int]) -> [OcaDatatypeDescriptor] {
  [OcaDatatypeDescriptor(name: "OcaBlobFixedLen", kind: .primitive)] + lengths.map {
    OcaDatatypeDescriptor(
      name: "OcaBlobFixedLen<\($0)>", kind: .template, baseTypeName: "OcaBlobFixedLen", typeArguments: ["\($0)"]
    )
  }
}

@_spi(SwiftOCAPrivate)
extension OcaClassID: OcaDatatypeDescribing {
  public static var datatypeDescriptor: OcaDatatypeDescriptor {
    OcaDatatypeDescriptor(name: "OcaClassID", kind: .struct, fields: [
      OcaFieldDescriptor(name: "FieldCount", typeName: "OcaUint16"),
      OcaFieldDescriptor(name: "Fields", typeName: "OcaList<OcaClassIDField>"),
    ])
  }

  public static var referredDatatypes: [OcaDatatypeDescriptor] {
    [
      OcaDatatypeDescriptor(name: "OcaUint16", kind: .primitive),
      OcaDatatypeDescriptor(name: "OcaList", kind: .primitive),
      OcaDatatypeDescriptor(
        name: "OcaList<OcaClassIDField>", kind: .template, baseTypeName: "OcaList", typeArguments: ["OcaClassIDField"]
      ),
      OcaDatatypeDescriptor(name: "OcaClassIDField", kind: .struct, fields: [
        OcaFieldDescriptor(name: "Value", typeName: "OcaUint16"),
      ]),
    ]
  }
}

@_spi(SwiftOCAPrivate)
extension OcaOrganizationID: OcaDatatypeDescribing {
  public static var datatypeDescriptor: OcaDatatypeDescriptor {
    OcaDatatypeDescriptor(name: "OcaOrganizationID", kind: .typedef, baseTypeName: "OcaBlobFixedLen<3>")
  }

  public static var referredDatatypes: [OcaDatatypeDescriptor] { fixedLengthBlobs([3]) }
}

@_spi(SwiftOCAPrivate)
extension OcaModelGUID: OcaDatatypeDescribing {
  public static var datatypeDescriptor: OcaDatatypeDescriptor {
    OcaDatatypeDescriptor(name: "OcaModelGUID", kind: .struct, fields: [
      OcaFieldDescriptor(name: "Reserved", typeName: "OcaBlobFixedLen<1>"),
      OcaFieldDescriptor(name: "MfrCode", typeName: "OcaBlobFixedLen<3>"),
      OcaFieldDescriptor(name: "ModelCode", typeName: "OcaBlobFixedLen<4>"),
    ])
  }

  public static var referredDatatypes: [OcaDatatypeDescriptor] { fixedLengthBlobs([1, 3, 4]) }
}

/// The data of an event that carries none.
public struct OcaEmptyEventData: Codable, Sendable, Equatable {
  public init() {}
}

@_spi(SwiftOCAPrivate)
extension OcaPropertyChangedEventData: OcaDatatypeDescribing {
  public static var datatypeDescriptor: OcaDatatypeDescriptor {
    OcaDatatypeDescriptor(name: "OcaPropertyChangedEventData", kind: .struct, typeArguments: ["DT"], fields: [
      OcaFieldDescriptor(name: "PropertyID", typeName: "OcaPropertyID"),
      OcaFieldDescriptor(name: "PropertyValue", typeName: "DT"),
      OcaFieldDescriptor(name: "ChangeType", typeName: "OcaPropertyChangeType"),
    ])
  }

  public static var referredTypes: [Any.Type] { [OcaPropertyID.self, OcaPropertyChangeType.self] }
}
