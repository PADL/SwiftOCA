//
// Copyright (c) 2023 PADL Software Pty Ltd
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

public typealias OcaBoolean = Bool
public typealias OcaBlob = LengthTaggedData16
public typealias OcaLongBlob = LengthTaggedData32

public typealias OcaInt8 = Int8
public typealias OcaInt16 = Int16
public typealias OcaInt32 = Int32
public typealias OcaInt64 = Int64

public typealias OcaUint8 = UInt8
public typealias OcaUint16 = UInt16
public typealias OcaUint32 = UInt32
public typealias OcaUint64 = UInt64

public typealias OcaFloat32 = Float32
public typealias OcaFloat64 = Float64

public typealias OcaDB = OcaFloat32
public typealias OcaString = String

public typealias OcaONo = OcaUint32
public typealias OcaSessionID = OcaUint16

public typealias OcaClassVersionNumber = OcaUint16

public typealias Ocp1List = Array

public typealias OcaList = Ocp1List
public typealias OcaMap = Dictionary
public typealias OcaMultiMap<K: Hashable, V> = OcaMap<K, [V]>

public typealias OcaNamePath = OcaList<OcaString>
public typealias OcaONoPath = OcaList<OcaONo>

public typealias OcaBitSet16 = OcaUint16

public enum OcaBaseDataType: OcaUint8, Codable, Sendable, CaseIterable {
  case none = 0
  case ocaBoolean = 1
  case ocaInt8 = 2
  case ocaInt16 = 3
  case ocaInt32 = 4
  case ocaInt64 = 5
  case ocaUint8 = 6
  case ocaUint16 = 7
  case ocaUint32 = 8
  case ocaUint64 = 9
  case ocaFloat32 = 10
  case ocaFloat64 = 11
  case ocaString = 12
  case ocaBitString = 13
  case ocaBlobFixedLen = 15
  case ocaBit = 16
}

public enum OcaStatus: OcaUint8, Codable, Sendable, CaseIterable {
  /// Method call was successful
  case ok = 0
  /// Controller sent a Control Protocol PDU whose protocol version the Device cannot handle
  case protocolVersionError = 1
  /// Command execution failed due to an internal Device error
  case deviceError = 2
  /// Command attempted to access an object with a lock status too restrictive for the requested
  /// operation
  case locked = 3
  /// One or more method parameters in a Command was in an invalid format
  case badFormat = 4
  /// Object number in a Command referenced a nonexistent object
  case badONo = 5
  /// One or more method parameters given in a Command was unacceptable in the current context, or
  /// a required parameter was missing
  case parameterError = 6
  /// One or more parameter values given in a Command was too large or too small for the current
  /// context
  case parameterOutOfRange = 7
  /// Method ID in Command referenced a method the Device does not implement
  case notImplemented = 8
  /// Command requested an action that is invalid in the current context
  case invalidRequest = 9
  /// Command execution failed, but not due to an internal Device error
  case processingFailed = 10
  /// Method ID in a Command referenced a nonexistent method
  case badMethod = 11
  /// Command execution partly succeeded.  Example:  in a method that operates on a specified list
  /// of items, some items were processed successfully, some not
  case partiallySucceeded = 12
  /// Device failed to process a Command within the given timeout time.  Valid only for methods
  /// with timeout parameters
  case timeout = 13
  /// Device did not have enough available memory to store an incoming PDU
  case bufferOverflow = 14
  /// Command requested an action for which the Controller had insufficient permission
  case permissionDenied = 15
  /// Device did not have enough available memory to process the Command
  case outOfMemory = 16
}

public struct OcaPropertyID: Codable, Hashable, Equatable, Comparable, Sendable,
  CustomStringConvertible, ExpressibleByStringLiteral, _Ocp1Codable
{
  let defLevel: OcaUint16
  let propertyIndex: OcaUint16

  public init(defLevel: OcaUint16, propertyIndex: OcaUint16) {
    self.defLevel = defLevel
    self.propertyIndex = propertyIndex
  }

  public init(_ string: OcaString) {
    let s = string.split(separator: ".", maxSplits: 1).map { OcaUint16($0)! }
    defLevel = s[0]
    propertyIndex = s[1]
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }

  public var description: String {
    "\(defLevel).\(propertyIndex)"
  }

  public static func < (lhs: OcaPropertyID, rhs: OcaPropertyID) -> Bool {
    if lhs.defLevel == rhs.defLevel {
      lhs.propertyIndex < rhs.propertyIndex
    } else {
      lhs.defLevel < rhs.defLevel
    }
  }

  // SPI visibility for SwiftOCADevice and FlutterSwiftOCA
  @_spi(SwiftOCAPrivate)
  public init(bytes: borrowing[UInt8]) throws {
    guard bytes.count >= 4 else { throw Ocp1Error.pduTooShort }

    defLevel = bytes.withUnsafeBytes {
      OcaUint16(bigEndian: $0.loadUnaligned(fromByteOffset: 0, as: OcaUint16.self))
    }
    propertyIndex = bytes.withUnsafeBytes {
      OcaUint16(bigEndian: $0.loadUnaligned(fromByteOffset: 2, as: OcaUint16.self))
    }
  }

  // SPI visibility for SwiftOCADevice and FlutterSwiftOCA
  @_spi(SwiftOCAPrivate)
  public func encode(into bytes: inout [UInt8]) {
    withUnsafeBytes(of: defLevel.bigEndian) { bytes += $0 }
    withUnsafeBytes(of: propertyIndex.bigEndian) { bytes += $0 }
  }
}

public enum OcaIODirection: OcaUint8, Codable, Sendable, CaseIterable {
  case input = 1
  case output = 2
}

public typealias OcaPortMode = OcaIODirection

public struct OcaPortID: Codable, Sendable, Hashable {
  public let mode: OcaPortMode
  public let index: OcaUint16

  public init(mode: OcaPortMode, index: OcaUint16) {
    self.mode = mode
    self.index = index
  }
}

public struct OcaPort: Codable, Sendable {
  public let owner: OcaONo
  public let id: OcaPortID
  public let name: OcaString

  public init(owner: OcaONo, id: OcaPortID, name: OcaString) {
    self.owner = owner
    self.id = id
    self.name = name
  }
}

public struct OcaSignalPath: Codable, Sendable {
  public let sourcePort: OcaPort
  public let sinkPort: OcaPort

  public init(sourcePort: OcaPort, sinkPort: OcaPort) {
    self.sourcePort = sourcePort
    self.sinkPort = sinkPort
  }
}

public struct OcaLibVolIdentifier: Codable, Sendable {
  public let library: OcaONo
  public let id: OcaLibVolID

  public init(library: OcaONo, id: OcaLibVolID) {
    self.library = library
    self.id = id
  }
}

public struct OcaClassID: Codable, Hashable, Sendable, CustomStringConvertible,
  ExpressibleByStringLiteral
{
  let fields: [OcaUint16]

  static let ProprietaryClassFieldMask = OcaUint16(0x8000)
  static let ProprietaryTestClassFieldMask = OcaUint16(0xFF00)
  static let ProprietaryClassField = OcaUint16(0xFFFF)
  public static let OcaAllianceCompanyID = OcaOrganizationID((0xFA, 0x2E, 0xE9))

  public init(_ string: OcaString) {
    fields = string.split(separator: ".").map { OcaUint16($0)! }
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }

  public init(unsafeString string: OcaString) throws {
    let fields = try string.split(separator: ".").map {
      let value = OcaUint16($0)
      guard let value else {
        throw Ocp1Error.objectClassMismatch
      }
      return value
    }
    guard fields.count > 1 else {
      throw Ocp1Error.objectClassMismatch
    }
    self.fields = fields
  }

  init(_ fields: [OcaUint16]) {
    self.fields = fields
  }

  init(_ fields: [OcaUint16], parent: OcaClassID) {
    self.fields = parent.fields + fields
  }

  init() {
    self.init([])
  }

  public init(parent: OcaClassID, _ string: String) {
    self.init(parent.fields, parent: OcaClassID(string))
  }

  public init(parent: OcaClassID, _ integer: OcaUint16) {
    self.init(parent.fields + [integer])
  }

  private init(parent: OcaClassID, authority: OcaOrganizationID, _ extraFields: [OcaUint16]) {
    fields = parent.fields + [
      Self.ProprietaryClassField,
      OcaUint16(authority.id.0),
      OcaUint16(authority.id.1 << 8 | authority.id.2),
    ] + extraFields
  }

  public init(parent: OcaClassID, authority: OcaOrganizationID, _ string: String) {
    self.init(parent: parent, authority: authority, OcaClassID(string).fields)
  }

  public init(parent: OcaClassID, authority: OcaOrganizationID, _ integer: OcaUint16) {
    self.init(parent: parent, authority: authority, [integer])
  }

  public var parent: OcaClassID? {
    guard fieldCount > 1 else {
      return nil
    }

    var parentFieldCount = fields.count - 1
    if parentFieldCount >= 4, fields[parentFieldCount - 3] == Self.ProprietaryClassField {
      parentFieldCount = parentFieldCount - 3
    }

    let parent = OcaClassID(Array(fields.prefix(parentFieldCount)))
    precondition(parent.isValid)
    return parent
  }

  public func isSubclass(of classID: OcaClassID) -> Bool {
    if self == classID || classID.fields.count == 0 {
      return true
    }

    var parent: OcaClassID? = parent

    while parent != nil {
      if parent == classID {
        return true
      }
      parent = parent?.parent
    }
    return false
  }

  public var fieldCount: OcaUint16 {
    OcaUint16(fields.count)
  }

  public var defLevel: OcaUint16 {
    guard isValid else {
      return 0
    }

    for field in fields {
      if field == Self.ProprietaryClassField {
        precondition(fieldCount >= 5)
        return fieldCount - 5
      }
    }

    return fieldCount
  }

  public var description: String {
    fields.map { String($0) }.joined(separator: ".")
  }

  public var isValid: Bool {
    var proprietaryClass = false
    var testClass = false
    var proprietaryFieldPresent = false

    guard fieldCount > 0, fields[0] == 1 else {
      return false
    }

    for i in 0..<fields.count {
      let field = fields[i]

      if field != Self.ProprietaryClassField {
        if proprietaryClass, !proprietaryFieldPresent {
          guard (
            field & Self.ProprietaryClassFieldMask == Self
              .ProprietaryClassFieldMask
          ) ||
            (
              testClass && field & Self.ProprietaryTestClassFieldMask == Self
                .ProprietaryTestClassFieldMask
            )
          else {
            return false
          }
        }
      } else {
        guard (fields.count - i) >= 3, !proprietaryClass else {
          return false
        }
        proprietaryFieldPresent = true
      }

      proprietaryClass = field & Self.ProprietaryClassFieldMask == Self
        .ProprietaryClassFieldMask
      testClass = (
        field & Self.ProprietaryTestClassFieldMask == Self
          .ProprietaryTestClassFieldMask
      ) && field != Self.ProprietaryClassField
    }

    return true
  }
}

public struct OcaMethodID: Codable, Hashable, Sendable, CustomStringConvertible,
  ExpressibleByStringLiteral, _Ocp1Codable
{
  public let defLevel: OcaUint16
  public let methodIndex: OcaUint16

  public init(defLevel: OcaUint16, methodIndex: OcaUint16) {
    self.defLevel = defLevel
    self.methodIndex = methodIndex
  }

  public init(_ string: OcaString) {
    let s = string.split(separator: ".", maxSplits: 1).map { OcaUint16($0)! }
    defLevel = s[0]
    methodIndex = s[1]
  }

  public init(unsafeString string: OcaString) throws {
    let s = try string.split(separator: ".", maxSplits: 1).map {
      let value = OcaUint16($0)
      guard let value else {
        throw Ocp1Error.status(.badFormat)
      }
      return value
    }
    guard s.count == 2 else {
      throw Ocp1Error.status(.badFormat)
    }
    defLevel = s[0]
    methodIndex = s[1]
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }

  init(bytes: borrowing[UInt8]) throws {
    guard bytes.count >= 4 else { throw Ocp1Error.pduTooShort }

    defLevel = bytes.withUnsafeBytes {
      OcaUint16(bigEndian: $0.loadUnaligned(fromByteOffset: 0, as: OcaUint16.self))
    }
    methodIndex = bytes.withUnsafeBytes {
      OcaUint16(bigEndian: $0.loadUnaligned(fromByteOffset: 2, as: OcaUint16.self))
    }
  }

  func encode(into bytes: inout [UInt8]) {
    withUnsafeBytes(of: defLevel.bigEndian) { bytes += $0 }
    withUnsafeBytes(of: methodIndex.bigEndian) { bytes += $0 }
  }

  public var description: String {
    "\(defLevel).\(methodIndex)"
  }
}

public struct OcaMethod: Codable, Sendable, Equatable, Hashable {
  public let oNo: OcaONo
  public let methodID: OcaMethodID

  public init(oNo: OcaONo, methodID: OcaMethodID) {
    self.oNo = oNo
    self.methodID = methodID
  }
}

public struct OcaClassIdentification: Codable, Sendable, Hashable {
  public let classID: OcaClassID
  public let classVersion: OcaClassVersionNumber

  public init(classID: OcaClassID, classVersion: OcaClassVersionNumber) {
    self.classID = classID
    self.classVersion = classVersion
  }

  public func isSubclass(of classIdentification: OcaClassIdentification) -> Bool {
    classID.isSubclass(of: classIdentification.classID) && classVersion <= classIdentification
      .classVersion
  }
}

public struct OcaObjectIdentification: Codable, Sendable, Hashable {
  public let oNo: OcaONo
  public let classIdentification: OcaClassIdentification

  public init(oNo: OcaONo, classIdentification: OcaClassIdentification) {
    self.oNo = oNo
    self.classIdentification = classIdentification
  }
}

public typealias OcaProtoONo = OcaUint32

public struct OcaGlobalTypeIdentifier: Codable, Sendable, Equatable {
  public let authority: OcaOrganizationID
  public let id: OcaUint32

  public init(authority: OcaOrganizationID, id: OcaUint32) {
    self.authority = authority
    self.id = id
  }
}

public struct OcaOrganizationID: Equatable, Hashable, Codable, Sendable, CustomStringConvertible {
  public let id: (OcaUint8, OcaUint8, OcaUint8)

  public init() {
    id = (0, 0, 0)
  }

  public init(_ id: (OcaUint8, OcaUint8, OcaUint8)) {
    self.id = id
  }

  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    id.0 = try container.decode(OcaUint8.self)
    id.1 = try container.decode(OcaUint8.self)
    id.2 = try container.decode(OcaUint8.self)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(id.0)
    try container.encode(id.1)
    try container.encode(id.2)
  }

  public var description: String {
    String(format: "%02X%02X%02X", id.0, id.1, id.2)
  }

  public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
    lhs.id.0 == rhs.id.0 &&
      lhs.id.1 == rhs.id.1 &&
      lhs.id.2 == rhs.id.2
  }

  public func hash(into hasher: inout Hasher) {
    id.0.hash(into: &hasher)
    id.1.hash(into: &hasher)
    id.2.hash(into: &hasher)
  }
}

public enum OcaLockState: OcaUint8, Codable, Sendable, CaseIterable {
  case noLock = 0
  case lockNoWrite = 1
  case lockNoReadWrite = 2
}

public typealias OcaID16 = OcaUint16
public typealias OcaID32 = OcaUint32

public typealias OcaInterval = Range

public typealias OcaJsonValue = OcaString
public typealias OcaParameterRecord = OcaJsonValue

public typealias OcaMimeType = OcaString

public enum OcaSecurityType: OcaUint8, Codable, Sendable, CaseIterable {
  case none = 0
  case `default` = 1
}

public typealias OcaNetworkHostID = OcaBlob

public struct OcaOPath: Codable, Sendable {
  public let hostID: OcaNetworkHostID
  public let oNo: OcaONo

  public init(hostID: OcaNetworkHostID, oNo: OcaONo) {
    self.hostID = hostID
    self.oNo = oNo
  }
}
