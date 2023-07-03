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

public enum OcaTimeSourceAvailability: OcaUint8, Codable {
    case unavailable = 0
    case available = 1
}

public enum OcaTimeProtocol: OcaUint8, Codable {
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

public typealias OcaSDPString = OcaString

public enum OcaTimeReferenceType: OcaUint8, Codable {
    case undefined = 0
    case local = 1
    case `private` = 2
    case gps = 3
    case galileo = 4
    case glonass = 5
}

public enum OcaTimeSourceSyncStatus: OcaUint8, Codable {
    case undefined = 0
    case unsynchronized = 1
    case synchronizing = 2
    case synchronized = 3
}

public class OcaTimeSource: OcaAgent {
    public override class var classID: OcaClassID { OcaClassID("1.2.16") }
    
    public override class var classVersion: OcaClassVersionNumber { 1 }
    
    @OcaProperty(propertyID: OcaPropertyID("3.1"),
                 getMethodID: OcaMethodID("3.1"))
    public var availability: OcaProperty<OcaTimeSourceAvailability>.State

    @OcaProperty(propertyID: OcaPropertyID("3.2"),
                 getMethodID: OcaMethodID("3.2"),
                 setMethodID: OcaMethodID("3.3"))
    public var `protocol`: OcaProperty<OcaTimeProtocol>.State

    @OcaProperty(propertyID: OcaPropertyID("3.3"),
                 getMethodID: OcaMethodID("3.4"),
                 setMethodID: OcaMethodID("3.5"))
    public var parameters: OcaProperty<OcaSDPString>.State

    @OcaProperty(propertyID: OcaPropertyID("3.4"),
                 getMethodID: OcaMethodID("3.6"),
                 setMethodID: OcaMethodID("3.7"))
    public var referenceType: OcaProperty<OcaTimeReferenceType>.State

    @OcaProperty(propertyID: OcaPropertyID("3.5"),
                 getMethodID: OcaMethodID("3.8"),
                 setMethodID: OcaMethodID("3.9"))
    public var referenceID: OcaProperty<OcaString>.State

    @OcaProperty(propertyID: OcaPropertyID("3.6"),
                 getMethodID: OcaMethodID("3.10"))
    public var syncStatus: OcaProperty<OcaTimeSourceSyncStatus>.State
    
    public func reset() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.11"))
    }
}
