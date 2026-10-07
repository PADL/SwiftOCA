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

import Foundation

/// What kind of AES70 datatype a Swift type is, read from the type itself without a value
/// of it: what the class manager names a type by, and what a bridge to another control
/// protocol describes it from.
@_spi(SwiftOCAPrivate)
public enum OcaDatatypeKind: Sendable {
  /// A base type, by its AES70 name: `OcaBoolean`, `OcaInt8` to `OcaUint64`,
  /// `OcaFloat32`, `OcaFloat64` or `OcaString`.
  case base(String)
  /// `OcaBlob` or `OcaLongBlob`, by its AES70 name.
  case blob(String)
  /// A value that may be absent, which AES70 writes as the type it holds.
  case optional(Any.Type)
  /// `OcaList` of the element type.
  case list(Any.Type)
  /// `OcaMap` of the key and value types.
  case map(key: Any.Type, value: Any.Type)
  /// A bounded property's value, of the type given, with its bounds beside it.
  case bounded(Any.Type)
  /// An enumeration, with each case's name and value.
  case enumeration([(name: String, value: Int64)])
  /// A type written as the raw value of the type given.
  case rawValue(Any.Type)
  /// A structure coded as its stored properties, which `Ocp2Encoder.fields(of:)` lists.
  case structure
  /// A type of none of these kinds, such as a class or one coded by hand.
  case other

  public init(of type: Any.Type) {
    if let base = Self.bases[ObjectIdentifier(type)] {
      self = base
    } else if let generic = type as? any OcaKindedGeneric.Type {
      self = generic.kind
    } else if type is any Ocp1TypedBlobRepresentable.Type {
      self = .blob("OcaBlob")
    } else if let enumeration = type as? any (CaseIterable & RawRepresentable).Type,
              let cases = Self.cases(of: enumeration)
    {
      self = .enumeration(cases)
    } else if let raw = type as? any RawRepresentable.Type {
      self = .rawValue(Self.rawType(of: raw))
    } else if type is any Codable.Type, !(type is AnyClass) {
      self = .structure
    } else {
      self = .other
    }
  }

  private static let bases: [ObjectIdentifier: OcaDatatypeKind] = [
    ObjectIdentifier(Bool.self): .base("OcaBoolean"),
    ObjectIdentifier(Int8.self): .base("OcaInt8"),
    ObjectIdentifier(Int16.self): .base("OcaInt16"),
    ObjectIdentifier(Int32.self): .base("OcaInt32"),
    ObjectIdentifier(Int64.self): .base("OcaInt64"),
    ObjectIdentifier(Int.self): .base("OcaInt64"),
    ObjectIdentifier(UInt8.self): .base("OcaUint8"),
    ObjectIdentifier(UInt16.self): .base("OcaUint16"),
    ObjectIdentifier(UInt32.self): .base("OcaUint32"),
    ObjectIdentifier(UInt64.self): .base("OcaUint64"),
    ObjectIdentifier(UInt.self): .base("OcaUint64"),
    ObjectIdentifier(Float.self): .base("OcaFloat32"),
    ObjectIdentifier(Double.self): .base("OcaFloat64"),
    ObjectIdentifier(String.self): .base("OcaString"),
    ObjectIdentifier(LengthTaggedData16.self): .blob("OcaBlob"),
    ObjectIdentifier(LengthTaggedData32.self): .blob("OcaLongBlob"),
    ObjectIdentifier(Data.self): .blob("OcaBlob"),
  ]

  /// An enumeration's cases, where each value is a whole number.
  private static func cases<E: CaseIterable & RawRepresentable>(
    of type: E.Type
  ) -> [(name: String, value: Int64)]? {
    var cases = [(name: String, value: Int64)]()
    for item in type.allCases {
      guard let value = (item.rawValue as? any BinaryInteger).flatMap({ Int64(exactly: $0) }) else {
        return nil
      }
      cases.append(("\(item)", value))
    }
    return cases.isEmpty ? nil : cases
  }

  private static func rawType<R: RawRepresentable>(of type: R.Type) -> Any.Type { R.RawValue.self }
}

/// A generic type whose kind is made from its parameters.
private protocol OcaKindedGeneric {
  static var kind: OcaDatatypeKind { get }
}

extension Optional: OcaKindedGeneric {
  fileprivate static var kind: OcaDatatypeKind { .optional(Wrapped.self) }
}

extension Array: OcaKindedGeneric {
  fileprivate static var kind: OcaDatatypeKind { .list(Element.self) }
}

extension Set: OcaKindedGeneric {
  fileprivate static var kind: OcaDatatypeKind { .list(Element.self) }
}

extension Dictionary: OcaKindedGeneric {
  fileprivate static var kind: OcaDatatypeKind { .map(key: Key.self, value: Value.self) }
}

extension OcaBoundedPropertyValue: OcaKindedGeneric {
  fileprivate static var kind: OcaDatatypeKind { .bounded(Value.self) }
}
