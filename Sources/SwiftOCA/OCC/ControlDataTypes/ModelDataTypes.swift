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

public struct OcaModelDescription: Codable, CustomStringConvertible {
    public let manufacturer: OcaString
    public let name: OcaString
    public let version: OcaString

    public var description: String {
        "\(manufacturer) \(name) \(version)"
    }

    public init(manufacturer: OcaString, name: OcaString, version: OcaString) {
        self.manufacturer = manufacturer
        self.name = name
        self.version = version
    }
}

public struct OcaModelGUID: Codable, CustomStringConvertible {
    public let reserved: OcaUint8
    public let mfrCode: OcaOrganizationID
    public let modelCode: OcaUint32 // TODO: should be tuple of OcaUint8

    public var description: String {
        mfrCode.description + String(format: "%08X", modelCode)
    }

    public init(reserved: OcaUint8, mfrCode: OcaOrganizationID, modelCode: OcaUint32) {
        self.reserved = reserved
        self.mfrCode = mfrCode
        self.modelCode = modelCode
    }
}
