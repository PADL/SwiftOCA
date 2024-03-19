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

public enum OcaTimeSourceAvailability: OcaUint8, Codable, Sendable, CaseIterable {
    case unavailable = 0
    case available = 1
}

public enum OcaTimeProtocol: OcaUint8, Codable, Sendable, CaseIterable {
    case undefined = 0
    case none = 1
    case `private` = 2
    case ntp = 3
    case sntp = 4
    case ieee1588_2002 = 5
    case ieee1588_2008 = 6
    case ieee_avb = 7
    case aes11 = 8
    case genlock = 9
}

public enum OcaTimeDeliveryMechanism: OcaUint8, Codable, Sendable, CaseIterable {
    case undefined = 0
    case none = 1
    case `private` = 2
    case ntp = 3
    case sntp = 4
    case ieee1588v1 = 5
    case ieee1588v2 = 6
    case ieee1588v2_1 = 7
    case ieee8021AS = 8 // gPTP
    case streamEndpoint = 9
    case aes11 = 10
    case expansionBase = 128
}

public typealias OcaSDPString = OcaString

public enum OcaTimeReferenceType: OcaUint8, Codable, Sendable, CaseIterable {
    case undefined = 0
    case local = 1
    case `private` = 2
    case gps = 3
    case galileo = 4
    case glonass = 5
    case beidou = 6
    case inrss = 7
    case _expansionBase = 128
}

public enum OcaTimeSourceSyncStatus: OcaUint8, Codable, Sendable, CaseIterable {
    case undefined = 0
    case unsynchronized = 1
    case synchronizing = 2
    case synchronized = 3
}

public struct OcaTimeDeliveryParameters_StreamEndpoint: Codable, Sendable {
    public let endpointOwner: OcaONo
    public let endpointID: OcaMediaStreamEndpointID
}

open class OcaTimeSource: OcaAgent {
    override public class var classID: OcaClassID { OcaClassID("1.2.16") }
    override public class var classVersion: OcaClassVersionNumber { 3 }

    @OcaProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.1")
    )
    public var availability: OcaProperty<OcaTimeSourceAvailability>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.2"),
        getMethodID: OcaMethodID("3.1"),
        setMethodID: OcaMethodID("3.3")
    )
    public var timeDeliveryMechanism: OcaProperty<OcaTimeDeliveryMechanism>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.3"),
        getMethodID: OcaMethodID("3.4"),
        setMethodID: OcaMethodID("3.5")
    )
    public var referenceSDPDescription: OcaProperty<OcaSDPString>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.4"),
        getMethodID: OcaMethodID("3.6"),
        setMethodID: OcaMethodID("3.7")
    )
    public var referenceType: OcaProperty<OcaTimeReferenceType>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.5"),
        getMethodID: OcaMethodID("3.8"),
        setMethodID: OcaMethodID("3.9")
    )
    public var referenceID: OcaProperty<OcaString>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.6"),
        getMethodID: OcaMethodID("3.10")
    )
    public var syncStatus: OcaProperty<OcaTimeSourceSyncStatus>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.7"),
        getMethodID: OcaMethodID("3.12"),
        setMethodID: OcaMethodID("3.13")
    )
    public var timeDeliveryParameters: OcaProperty<OcaParameterRecord>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.8"),
        getMethodID: OcaMethodID("3.14"),
        setMethodID: OcaMethodID("3.15")
    )
    public var `protocol`: OcaProperty<OcaTimeProtocol>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.9"),
        getMethodID: OcaMethodID("3.16"),
        setMethodID: OcaMethodID("3.17")
    )
    public var parameters: OcaProperty<OcaSDPString>.PropertyValue

    public func reset() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.11"))
    }
}
