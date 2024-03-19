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

public struct OcaDeviceState: OptionSet, Codable, Sendable, CustomStringConvertible {
    public static let operational = OcaDeviceState(rawValue: 1 << 0)
    public static let disabled = OcaDeviceState(rawValue: 1 << 1)
    public static let error = OcaDeviceState(rawValue: 1 << 2)
    public static let initializing = OcaDeviceState(rawValue: 1 << 3)
    public static let updating = OcaDeviceState(rawValue: 1 << 4)

    public let rawValue: OcaBitSet16

    public init(rawValue: OcaBitSet16) {
        self.rawValue = rawValue
    }

    static let descriptions: [(Self, String)] = [
        (.operational, "Operational"),
        (.disabled, "Disabled"),
        (.error, "Error"),
        (.initializing, "Initializing"),
        (.updating, "Updating"),
    ]

    public var description: String {
        Self.descriptions.filter { contains($0.0) }.map(\.1).joined(separator: ", ")
    }
}

public struct OcaManufacturer: Codable, Sendable {
    public let name: OcaString
    public let organizationID: OcaOrganizationID
    public let website: OcaString
    public let businessContact: OcaString
    public let technicalContact: OcaString

    public init(
        name: OcaString = "",
        organizationID: OcaOrganizationID = .init(),
        website: OcaString = "",
        businessContact: OcaString = "",
        technicalContact: OcaString = ""
    ) {
        self.name = name
        self.organizationID = organizationID
        self.website = website
        self.businessContact = businessContact
        self.technicalContact = technicalContact
    }
}

public typealias OcaUUID = OcaString

public struct OcaProduct: Codable, Sendable {
    public let name: OcaString
    public let modelID: OcaString
    public let revisionLevel: OcaString
    public let brandName: OcaString
    public let uuid: OcaUUID
    public let description: OcaString

    public init(
        name: OcaString = "",
        modelID: OcaString = "",
        revisionLevel: OcaString = "",
        brandName: OcaString = "",
        uuid: OcaUUID = "",
        description: OcaString = ""
    ) {
        self.name = name
        self.modelID = modelID
        self.revisionLevel = revisionLevel
        self.brandName = brandName
        self.uuid = uuid
        self.description = description
    }
}

public enum OcaDeviceGenericState: OcaUint8, Codable, Sendable, CaseIterable {
    case normalOperation = 0
    case initializing = 1
    case updating = 2
    case fault = 3
    case expansionBase = 128
}

public struct OcaDeviceOperationalState: Codable, Sendable {
    public let generic: OcaDeviceGenericState
    public let details: OcaBlob

    public init(generic: OcaDeviceGenericState = .normalOperation, details: OcaBlob = .init()) {
        self.generic = generic
        self.details = details
    }
}
