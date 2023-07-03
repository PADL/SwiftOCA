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

import Foundation
import BinaryCoder

public typealias OcaBoolean = Bool
public typealias OcaBlob = LengthTaggedData

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

public typealias OcaTimeInterval = TimeInterval

public typealias OcaList = Array
public typealias OcaMap = Dictionary

public typealias OcaNamePath = OcaList<OcaString>
public typealias OcaONoPath = OcaList<OcaONo>

public typealias OcaNetworkAddress = OcaBlob

public typealias OcaBitSet16 = OcaUint16

public enum OcaBaseDataType: OcaUint8, Codable {
    case `none` = 0
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

public enum OcaStatus: OcaUint8, Codable {
    case ok = 0
    case protocolVersionError = 1
    case deviceError = 2
    case locked = 3
    case badFormat = 4
    case badONo = 5
    case parameterError = 6
    case parameterOutOfRange = 7
    case notImplemented = 8
    case invalidRequest = 9
    case processingFailed = 10
    case badMethod = 11
    case partiallySucceeded = 12
    case timeout = 13
    case bufferOverflow = 14
}

public struct OcaPropertyID: Codable, Hashable, Equatable, Comparable, CustomStringConvertible {
    let defLevel: OcaUint16
    let propertyIndex: OcaUint16
    
    public init(_ string: OcaString) {
        let s = string.split(separator: ".", maxSplits: 1).map { OcaUint16($0)! }
        defLevel = s[0]
        propertyIndex = s[1]
    }
    
    public var description: String {
        return "\(defLevel).\(propertyIndex)"
    }
    
    public static func < (lhs: OcaPropertyID, rhs: OcaPropertyID) -> Bool {
        if lhs.defLevel == rhs.defLevel {
            return lhs.propertyIndex < rhs.propertyIndex
        } else {
            return lhs.defLevel < rhs.defLevel
        }
    }
}

public enum OcaPortMode: OcaUint8, Codable {
    case input = 1
    case output = 2
}

public struct OcaPortID: Codable {
    let mode: OcaPortMode
    let index: OcaUint16
}

public struct OcaPort: Codable {
    let owner: OcaONo
    let id: OcaPortID
    let name: OcaString
}

public struct OcaSignalPath: Codable {
    let sourcePort: OcaPort
    let sinkPort: OcaPort
}

public struct OcaLibVolIdentifier: Codable {
    let library: OcaONo
    let id: OcaLibVolID
}

public struct OcaClassID: Codable, Hashable, CustomStringConvertible {
    let fields: [OcaUint16]
    
    static let ProprietaryClassFieldMask = OcaUint16(0x8000)
    static let ProprietaryTestClassFieldMask = OcaUint16(0xff00)
    static let ProprietaryClassField = OcaUint16(0xffff)
    public static let OcaAllianceCompanyID = OcaOrganizationID((0xFA, 0x2E, 0xE9))
    
    public init(_ string: OcaString) {
        fields = string.split(separator: ".").map { OcaUint16($0)! }
    }
    
    init(_ fields: [OcaUint16]) {
        self.fields = fields
    }
    
    public var parent: OcaClassID? {
        guard self.fieldCount > 1 else {
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

    public var fieldCount: OcaUint16 {
        return OcaUint16(fields.count)
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
        return fields.map { String($0) }.joined(separator: ".")
    }
    
    public var isValid: Bool {
        var proprietaryClass = false
        var testClass = false
        var proprietaryFieldPresent = false
        
        guard self.fieldCount > 0, self.fields[0] == 1 else {
            return false
        }
        
        for i in 0..<fields.count {
            let field = fields[i]
            
            if field != Self.ProprietaryClassField {
                if proprietaryClass, !proprietaryFieldPresent {
                    guard (field & Self.ProprietaryClassFieldMask == Self.ProprietaryClassFieldMask) ||
                            (testClass && field & Self.ProprietaryTestClassFieldMask == Self.ProprietaryTestClassFieldMask) else {
                        return false
                    }
                }
            } else {
                guard (fields.count - i) >= 3, !proprietaryClass else {
                    return false
                }
                proprietaryFieldPresent = true
            }
            
            proprietaryClass = field & Self.ProprietaryClassFieldMask == Self.ProprietaryClassFieldMask
            testClass = (field & Self.ProprietaryTestClassFieldMask == Self.ProprietaryTestClassFieldMask) && field != Self.ProprietaryClassField
        }
        
        return true
    }
}

public struct OcaMethodID: Codable, Hashable, CustomStringConvertible {
    let defLevel: OcaUint16
    let methodIndex: OcaUint16
    
    public init(_ string: OcaString) {
        let s = string.split(separator: ".", maxSplits: 1).map { OcaUint16($0)! }
        defLevel = s[0]
        methodIndex = s[1]
    }
    
    public var description: String {
        return "\(defLevel).\(methodIndex)"
    }
}

public struct OcaMethod: Codable {
    let oNo: OcaONo
    let methodID: OcaMethodID
}

public struct OcaClassIdentification: Codable, Hashable {
    let classID: OcaClassID
    let classVersion: OcaClassVersionNumber
}

public struct OcaObjectIdentification: Codable {
    let oNo: OcaONo
    let classIdentification: OcaClassIdentification
    
    public init(oNo: OcaONo, classIdentification: OcaClassIdentification) {
        self.oNo = oNo
        self.classIdentification = classIdentification
    }
}

public typealias OcaProtoONo = OcaUint32

public struct OcaGlobalTypeIdentifier: Codable {
    let authority: OcaOrganizationID
    let id: OcaUint32
}

public struct OcaOrganizationID: Codable, CustomStringConvertible {
    let id: (OcaUint8, OcaUint8, OcaUint8)
    
    init(_ id: (OcaUint8, OcaUint8, OcaUint8)) {
        self.id = id
    }
    
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.id.0 = try container.decode(OcaUint8.self)
        self.id.1 = try container.decode(OcaUint8.self)
        self.id.2 = try container.decode(OcaUint8.self)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.id.0)
        try container.encode(self.id.1)
        try container.encode(self.id.2)
    }
    
    public var description: String {
        String(format: "%02X%02X%02X", id.0, id.1, id.2)
    }
}
