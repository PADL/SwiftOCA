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

public enum OcaStringComparisonType: OcaUint8, Codable, Sendable, CaseIterable {
    /// Exact comparison. Case-sensitive
    case exact = 0
    /// Match all strings whose initial substrings equal the given key. Case-sensitive
    case substring = 1
    /// Match all strings that contain the given key. Case-sensitive
    case contains = 2
    /// Exact comparison. Case-insensitive
    case exactCaseInsensitive = 3
    /// Match all strings whose initial substrings equal the given key. Case-insensitive
    case substringCaseInsensitive = 4
    /// Match all strings that contain the given key. Case-insensitive
    case containsCaseInsensitive = 5
}

public struct OcaActionObjectSearchResultFlags: OptionSet, Codable, Sendable {
    public static let oNo = OcaActionObjectSearchResultFlags(rawValue: 1 << 0)
    public static let classIdentification = OcaActionObjectSearchResultFlags(rawValue: 1 << 1)
    public static let containerPath = OcaActionObjectSearchResultFlags(rawValue: 1 << 2)
    public static let role = OcaActionObjectSearchResultFlags(rawValue: 1 << 3)
    public static let label = OcaActionObjectSearchResultFlags(rawValue: 1 << 4)

    public let rawValue: OcaBitSet16

    public init(rawValue: OcaBitSet16) {
        self.rawValue = rawValue
    }
}

public struct OcaObjectSearchResult: Codable, Sendable {
    public let oNo: OcaONo?
    public let classIdentification: OcaClassIdentification?
    public let containerPath: OcaONoPath?
    public let role: OcaString?
    public let label: OcaString?

    public init(
        oNo: OcaONo?,
        classIdentification: OcaClassIdentification?,
        containerPath: OcaONoPath?,
        role: OcaString?,
        label: OcaString?
    ) {
        self.oNo = oNo
        self.classIdentification = classIdentification
        self.containerPath = containerPath
        self.role = role
        self.label = label
    }

    enum CodingKeys: CodingKey {
        case oNo
        case classIdentification
        case containerPath
        case role
        case label
    }

    static var FlagsUserInfoKey: CodingUserInfoKey {
        CodingUserInfoKey(rawValue: "com.padl.SwiftOCA.FlagsUserInfoKey")!
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let searchResultFlags = decoder
            .userInfo[Self.FlagsUserInfoKey] as? OcaActionObjectSearchResultFlags ??
            OcaActionObjectSearchResultFlags([.oNo, .classIdentification, .containerPath, .role,
                                              .label])

        if searchResultFlags.contains(.oNo) {
            oNo = try container.decodeIfPresent(OcaONo.self, forKey: .oNo)
        } else {
            oNo = OcaInvalidONo
        }
        if searchResultFlags.contains(.classIdentification) {
            classIdentification = try container.decodeIfPresent(
                OcaClassIdentification.self,
                forKey: .classIdentification
            )
        } else {
            classIdentification = nil
        }
        if searchResultFlags.contains(.containerPath) {
            containerPath = try container.decodeIfPresent(OcaONoPath.self, forKey: .containerPath)
        } else {
            containerPath = nil
        }
        if searchResultFlags.contains(.role) {
            role = try container.decodeIfPresent(OcaString.self, forKey: .role)
        } else {
            role = nil
        }
        if searchResultFlags.contains(.label) {
            label = try container.decodeIfPresent(OcaString.self, forKey: .label)
        } else {
            label = nil
        }
    }
}
