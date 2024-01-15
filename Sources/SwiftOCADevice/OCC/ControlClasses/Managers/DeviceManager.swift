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
import SwiftOCA

open class OcaDeviceManager: OcaManager {
    override open class var classID: OcaClassID { OcaClassID("1.3.1") }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.2")
    )
    public var modelGUID = OcaModelGUID(
        reserved: 0,
        mfrCode: OcaOrganizationID((0, 0, 0)),
        modelCode: 0
    )

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.2"),
        getMethodID: OcaMethodID("3.3")
    )
    public var serialNumber = getPlatformUUID()

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.3"),
        getMethodID: OcaMethodID("3.6")
    )
    public var modelDescription = OcaModelDescription(
        manufacturer: "PADL",
        name: "SwiftOCA",
        version: "0.0"
    )

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.4"),
        getMethodID: OcaMethodID("3.4"),
        setMethodID: OcaMethodID("3.5")
    )
    public var deviceName = "SwiftOCA"

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.5"),
        getMethodID: OcaMethodID("3.1")
    )
    public var version = 2023

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.6"),
        getMethodID: OcaMethodID("3.7"),
        setMethodID: OcaMethodID("3.8")
    )
    public var deviceRole = ""

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.7"),
        getMethodID: OcaMethodID("3.9"),
        setMethodID: OcaMethodID("3.10")
    )
    public var userInventoryCode = ""

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.8"),
        getMethodID: OcaMethodID("3.11"),
        setMethodID: OcaMethodID("3.12")
    )
    public var enabled = true

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.9"),
        getMethodID: OcaMethodID("3.13")
    )
    public var state = OcaDeviceState()

    @OcaDeviceProperty(propertyID: OcaPropertyID("3.10"))
    public var busy = false

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.11"),
        getMethodID: OcaMethodID("3.15")
    )
    public var resetCause = OcaResetCause.powerOn

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.12"),
        getMethodID: OcaMethodID("3.17"),
        setMethodID: OcaMethodID("3.18")
    )
    public var message = ""

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.13"),
        getMethodID: OcaMethodID("3.19")
    )
    public var managers = OcaList<OcaManagerDescriptor>()

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.14"),
        getMethodID: OcaMethodID("3.20")
    )
    public var deviceRevisionID = ""

    public convenience init(deviceDelegate: AES70Device? = nil) async throws {
        try await self.init(
            objectNumber: OcaDeviceManagerONo,
            role: "Device Manager",
            deviceDelegate: deviceDelegate,
            addToRootBlock: false
        )
    }
}

private func getPlatformUUID() -> String {
    #if canImport(Darwin)
    let platformExpertDevice = IOServiceMatching("IOPlatformExpertDevice")
    let platformExpert: io_service_t = IOServiceGetMatchingService(
        kIOMainPortDefault,
        platformExpertDevice
    )
    let serialNumberAsCFString = IORegistryEntryCreateCFProperty(
        platformExpert,
        kIOPlatformUUIDKey as CFString,
        kCFAllocatorDefault,
        0
    )
    IOObjectRelease(platformExpert)

    return serialNumberAsCFString?.takeUnretainedValue() as! String
    #else
    ""
    #endif
}
