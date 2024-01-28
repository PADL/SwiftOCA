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

open class OcaApplicationNetwork: OcaRoot, OcaOwnable {
    override public class var classID: OcaClassID { OcaClassID("1.4") }
    override public class var classVersion: OcaClassVersionNumber { 1 }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("2.1"),
        getMethodID: OcaMethodID("2.1"),
        setMethodID: OcaMethodID("2.2")
    )
    public var label = ""

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("2.2"),
        getMethodID: OcaMethodID("2.3")
    )
    public var owner = OcaInvalidONo

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("2.3"),
        getMethodID: OcaMethodID("2.4"),
        setMethodID: OcaMethodID("2.5")
    )
    public var serviceID: OcaApplicationNetworkServiceID = .init()

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("2.4"),
        getMethodID: OcaMethodID("2.6"),
        setMethodID: OcaMethodID("2.7")
    )
    public var systemInterfaces = [OcaNetworkSystemInterfaceDescriptor]()

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("2.5"),
        getMethodID: OcaMethodID("2.8")
    )
    public var state: OcaApplicationNetworkState = .stopped

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("2.6"),
        getMethodID: OcaMethodID("2.9")
    )
    public var errorCode: OcaUint16 = 0

    @OcaDevice
    open func control(_ command: OcaApplicationNetworkCommand) async throws {
        throw Ocp1Error.status(.notImplemented)
    }

    override public func handleCommand(
        _ command: Ocp1Command,
        from controller: OcaController
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("2.10"):
            let params: OcaApplicationNetworkCommand = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await control(params)
            return Ocp1Response()
        case OcaMethodID("2.11"):
            return try await encodeResponse(path)
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }
}
