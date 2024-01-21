//
// Copyright (c) 2024 PADL Software Pty Ltd
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

public typealias OcaLibVolID = OcaUint32

public struct OcaLibVolData_ParamSet: Codable, Sendable {
    public let targetBlockType: OcaONo
    public let parData: OcaBlob
}

public struct OcaLibVolType: Codable, Sendable {
    public let authority: OcaOrganizationID
    public let id: OcaUint32

    public init(authority: OcaOrganizationID, id: OcaUint32) {
        self.authority = authority
        self.id = id
    }
}

public struct OcaLibraryIdentifier: Codable, Sendable {
    public let type: OcaLibVolType
    public let oNo: OcaONo

    public init(type: OcaLibVolType, oNo: OcaONo) {
        self.type = type
        self.oNo = oNo
    }
}
