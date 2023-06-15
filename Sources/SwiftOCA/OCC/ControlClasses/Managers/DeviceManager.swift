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

public struct OcaDeviceState: OptionSet, Codable {
    public static let operational = OcaDeviceState(rawValue: 1 << 0)
    public static let disabled = OcaDeviceState(rawValue: 1 << 1)
    public static let error = OcaDeviceState(rawValue: 1 << 2)
    public static let initializing = OcaDeviceState(rawValue: 1 << 3)
    public static let updating = OcaDeviceState(rawValue: 1 << 4)
    
    public let rawValue: OcaBitSet16
    
    public init(rawValue: OcaBitSet16) {
        self.rawValue = rawValue
    }
}

public class OcaDeviceManager: OcaManager {
    public override class var classID: OcaClassID { OcaClassID("1.3.1") }

    @OcaProperty(propertyID: OcaPropertyID("3.1"),
                 getMethodID: OcaMethodID("3.2"))
    public var modelGUID: OcaProperty<OcaModelGUID>.State

    @OcaProperty(propertyID: OcaPropertyID("3.2"),
                 getMethodID: OcaMethodID("3.3"))
    public var serialNumber: OcaProperty<OcaString>.State

    @OcaProperty(propertyID: OcaPropertyID("3.3"),
                 getMethodID: OcaMethodID("3.6"))
    public var modelDescription: OcaProperty<OcaModelDescription>.State

    @OcaProperty(propertyID: OcaPropertyID("3.4"),
                 getMethodID: OcaMethodID("3.4"),
                 setMethodID: OcaMethodID("3.5"))
    public var deviceName: OcaProperty<OcaString>.State

    @OcaProperty(propertyID: OcaPropertyID("3.5"),
                 getMethodID: OcaMethodID("3.1"))
    public var version: OcaProperty<OcaUint16>.State

    @OcaProperty(propertyID: OcaPropertyID("3.6"),
                 getMethodID: OcaMethodID("3.7"),
                 setMethodID: OcaMethodID("3.8"))
    public var deviceRole: OcaProperty<OcaString>.State

    @OcaProperty(propertyID: OcaPropertyID("3.7"),
                 getMethodID: OcaMethodID("3.9"),
                 setMethodID: OcaMethodID("3.10"))
    public var userInventoryCode: OcaProperty<OcaString>.State

    @OcaProperty(propertyID: OcaPropertyID("3.8"),
                 getMethodID: OcaMethodID("3.11"),
                 setMethodID: OcaMethodID("3.12"))
    public var enabled: OcaProperty<OcaBoolean>.State

    @OcaProperty(propertyID: OcaPropertyID("3.8"),
                 getMethodID: OcaMethodID("3.13"))
    public var state: OcaProperty<OcaDeviceState>.State

    // TODO: property 3.10 can only be set by events???
    var busy: OcaBoolean = false
    
    @OcaProperty(propertyID: OcaPropertyID("3.12"),
                 getMethodID: OcaMethodID("3.17"),
                 setMethodID: OcaMethodID("3.18"))
    public var message: OcaProperty<OcaString>.State

    @OcaProperty(propertyID: OcaPropertyID("3.13"),
                 getMethodID: OcaMethodID("3.18"))
    public var managers: OcaProperty<OcaList<OcaManagerDescriptor>>.State

    @OcaProperty(propertyID: OcaPropertyID("3.4"),
                 getMethodID: OcaMethodID("3.20"))
    public var deviceRevisionID: OcaProperty<OcaString>.State
    
    convenience init() {
        self.init(objectNumber: OcaDeviceManagerONo)
    }
    
    //OcaStatus SetResetKey(OcaBlobFixedLen<16> Key, OcaNetworkAddress Address)
    //OcaStatus GetResetCause(OcaResetCause &resetCause)

    func clearResetCause() async -> OcaStatus {
        return .notImplemented
    }
}
