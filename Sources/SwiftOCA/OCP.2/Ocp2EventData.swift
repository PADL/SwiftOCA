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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Event data as a notification carries it: OCP.1 bytes, or the OCP.2 JSON value as
/// parsed from or encoded for the wire, `nil` when there is none. The value is passed
/// through unserialised, so only a recipient wanting bytes pays for them.
package enum OcaEncodedEventData: Sendable {
  case ocp1(Data)
  #if NonEmbeddedBuild
  case ocp2((any Sendable)?)
  #endif

  /// Wire bytes in `format`; OCP.2 data is parsed, which can fail.
  package init(_ data: Data, format: OcaParameterFormat) throws {
    switch format {
    case .ocp1:
      self = .ocp1(data)
    case .ocp2:
      #if NonEmbeddedBuild
      self = .ocp2(data.isEmpty ? nil : Ocp2JSON.sendable(try Ocp2JSON.parse(data)))
      #else
      throw Ocp1Error.unsupportedControlProtocol
      #endif
    }
  }

  package var format: OcaParameterFormat {
    switch self {
    case .ocp1: .ocp1
    #if NonEmbeddedBuild
    case .ocp2: .ocp2
    #endif
    }
  }

  package var isEmpty: Bool {
    switch self {
    case let .ocp1(data): data.isEmpty
    #if NonEmbeddedBuild
    case let .ocp2(value): value == nil
    #endif
    }
  }

  /// The wire bytes, serialised on demand for OCP.2.
  package var data: Data {
    get throws {
      switch self {
      case let .ocp1(data):
        return data
      #if NonEmbeddedBuild
      case let .ocp2(value):
        guard let value else { return Data() }
        return try Ocp2JSON.serialize(value)
      #endif
      }
    }
  }
}

/// Event data as delivered by a notification: OCP.1 bytes or an OCP.2 JSON object.
/// A subscription callback receives the data in the connection's `parameterFormat`.
public enum OcaEventDataCoding {
  /// Decodes event-specific data in `format`.
  public static func decode<T: Decodable>(
    _ type: T.Type,
    from data: Data,
    format: OcaParameterFormat
  ) throws -> T {
    try decode(type, from: OcaEncodedEventData(data, format: format))
  }

  package static func decode<T: Decodable>(
    _ type: T.Type,
    from eventData: OcaEncodedEventData
  ) throws -> T {
    switch eventData {
    case let .ocp1(data):
      return try Ocp1Decoder().decode(type, from: data)
    #if NonEmbeddedBuild
    case let .ocp2(value):
      guard let value else { throw Ocp1Error.status(.badFormat) }
      return try Ocp2Decoder().decodeValue(type, from: value)
    #endif
    }
  }

  /// The property a property-changed event refers to, without decoding its value.
  public static func propertyID(from data: Data, format: OcaParameterFormat) throws -> OcaPropertyID {
    try propertyID(from: OcaEncodedEventData(data, format: format))
  }

  package static func propertyID(from eventData: OcaEncodedEventData) throws -> OcaPropertyID {
    switch eventData {
    case let .ocp1(data):
      return try OcaPropertyID(bytes: data)
    #if NonEmbeddedBuild
    case let .ocp2(value):
      guard let object = value as? [String: Any],
            let propertyID = Ocp2Decoder.member(named: "PropertyID", in: object)
      else {
        throw Ocp1Error.status(.badFormat)
      }
      return try Ocp2Decoder().decodeValue(OcaPropertyID.self, from: propertyID)
    #endif
    }
  }

  /// Encodes event-specific data in `format`.
  public static func encode(_ value: some Encodable, format: OcaParameterFormat) throws -> Data {
    try encodeEventData(value, format: format).data
  }

  package static func encodeEventData(
    _ value: some Encodable,
    format: OcaParameterFormat
  ) throws -> OcaEncodedEventData {
    switch format {
    case .ocp1:
      return .ocp1(try Ocp1Encoder().encode(value))
    case .ocp2:
      #if NonEmbeddedBuild
      return .ocp2(Ocp2JSON.sendable(try Ocp2Encoder().encodeValue(value)))
      #else
      throw Ocp1Error.unsupportedControlProtocol
      #endif
    }
  }
}

public extension OcaControlProtocol {
  /// The format of parameters and event data carried by this protocol.
  var parameterFormat: OcaParameterFormat {
    switch self {
    case .ocp1: .ocp1
    #if NonEmbeddedBuild
    case .ocp2: .ocp2
    #endif
    }
  }
}
