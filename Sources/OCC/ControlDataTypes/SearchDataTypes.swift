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

public enum OcaStringComparisonType: OcaUint8, Codable {
    case exact = 0
    case substring = 1
    case contains = 2
    case exactCaseInsensitive = 3
    case substringCaseInsensitive = 4
    case containsCaseInsensitive = 5
}

public struct OcaObjectSearchResultFlags: OptionSet, Codable {
    public static let oNo = (1 << 0)
    public static let classIdentification = (1 << 1)
    public static let containerPath = (1 << 2)
    public static let role = (1 << 3)
    public static let label = (1 << 3)
    
    public let rawValue: OcaBitSet16
    
    public init(rawValue: OcaBitSet16) {
        self.rawValue = rawValue
    }
}

public struct OcaObjectSearchResult: Codable {
    let oNo: OcaONo
    let classIdentification: OcaClassIdentification
    let containerPath: OcaONoPath
    let role: OcaString
    let label: OcaString
}
