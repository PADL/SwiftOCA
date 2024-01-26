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

import SwiftOCA

open class OcaWorker: OcaRoot, OcaOwnable, OcaPortsRepresentable, OcaPortClockMapRepresentable {
    override public class var classID: OcaClassID { OcaClassID("1.1.1") }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("2.1"),
        getMethodID: OcaMethodID("2.1"),
        setMethodID: OcaMethodID("2.2")
    )
    public var enabled = true

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("2.2"),
        getMethodID: OcaMethodID("2.5")
    )
    public var ports = [OcaPort]()

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("2.3"),
        getMethodID: OcaMethodID("2.8"),
        setMethodID: OcaMethodID("2.9")
    )
    public var label = ""

    // 2.4
    @OcaDeviceProperty(
        propertyID: OcaPropertyID("2.4"),
        getMethodID: OcaMethodID("2.10")
    )
    public var owner: OcaONo = OcaInvalidONo

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("2.5"),
        getMethodID: OcaMethodID("2.11"),
        setMethodID: OcaMethodID("2.12")
    )
    public var latency: OcaTimeInterval?

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("2.6"),
        getMethodID: OcaMethodID("2.14"),
        setMethodID: OcaMethodID("2.15")
    )
    public var portClockMap: OcaMap<OcaPortID, OcaPortClockMapEntry> = [:]

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: OcaController
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("2.6"):
            return try await encodeResponse(handleGetPortName(command, from: controller))
        case OcaMethodID("2.7"):
            try await handleSetPortName(command, from: controller)
            return Ocp1Response()
        case OcaMethodID("2.17"):
            let portClockMapEntry = try await handleGetPortClockMapEntry(command, from: controller)
            return try encodeResponse(portClockMapEntry)
        case OcaMethodID("2.17"):
            try await handleSetPortClockMapEntry(command, from: controller)
            return Ocp1Response()
        case OcaMethodID("2.18"):
            try await handleDeletePortClockMapEntry(command, from: controller)
            return Ocp1Response()
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }
}
