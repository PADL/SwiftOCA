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

public enum OcaStringComparisonType: OcaUint8, Codable, Sendable {
    case exact = 0
    case substring = 1
    case contains = 2
    case exactCaseInsensitive = 3
    case substringCaseInsensitive = 4
    case containsCaseInsensitive = 5
}

public struct OcaObjectSearchResultFlags: OptionSet, Codable, Sendable {
    public static let oNo = OcaObjectSearchResultFlags(rawValue: 1 << 0)
    public static let classIdentification = OcaObjectSearchResultFlags(rawValue: 1 << 1)
    public static let containerPath = OcaObjectSearchResultFlags(rawValue: 1 << 2)
    public static let role = OcaObjectSearchResultFlags(rawValue: 1 << 3)
    public static let label = OcaObjectSearchResultFlags(rawValue: 1 << 4)

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
}
