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

open class OcaFirmwareManager: OcaManager {
    override open class var classID: OcaClassID { OcaClassID("1.3.3") }
    override open class var classVersion: OcaClassVersionNumber { 3 }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.1")
    )
    public var componentVersions = [OcaVersion]()

    override public func handleCommand(
        _ command: Ocp1Command,
        from controller: AES70Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("3.2"):
            try await ensureWritable(by: controller, command: command)
            try await startUpdateProcess()
            return Ocp1Response()
        case OcaMethodID("3.3"):
            let component: OcaComponent = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await beginActiveImageUpdate(component: component)
            return Ocp1Response()
        case OcaMethodID("3.4"):
            let parameters: SwiftOCA.OcaFirmwareManager
                .AddImageDataParameters = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await addImageData(id: parameters.id, parameters.imageData)
            return Ocp1Response()
        case OcaMethodID("3.5"):
            let verifyData: OcaBlob = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await verifyImage(verifyData)
            return Ocp1Response()
        case OcaMethodID("3.6"):
            try await ensureWritable(by: controller, command: command)
            try await endActiveImageUpdate()
            return Ocp1Response()
        case OcaMethodID("3.7"):
            let parameters: SwiftOCA.OcaFirmwareManager
                .BeginPassiveComponentUpdateParameters = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            try await beginPassiveComponentUpdate(
                component: parameters.component,
                serverAddress: parameters.serverAddress,
                updateFileName: parameters.updateFileName
            )
            return Ocp1Response()
        case OcaMethodID("3.8"):
            try await ensureWritable(by: controller, command: command)
            try await endUpdateProcess()
            return Ocp1Response()
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }

    public convenience init(deviceDelegate: AES70Device? = nil) async throws {
        try await self.init(
            objectNumber: OcaFirmwareManagerONo,
            role: "Firmware Manager",
            deviceDelegate: deviceDelegate,
            addToRootBlock: true
        )
    }

    open func startUpdateProcess() async throws {
        throw Ocp1Error.status(.notImplemented)
    }

    open func beginActiveImageUpdate(component: OcaComponent) async throws {
        throw Ocp1Error.status(.notImplemented)
    }

    open func addImageData(id: OcaUint32, _ imageData: OcaBlob) async throws {
        throw Ocp1Error.status(.notImplemented)
    }

    open func verifyImage(_ verifyData: OcaBlob) async throws {
        throw Ocp1Error.status(.notImplemented)
    }

    open func endActiveImageUpdate() async throws {
        throw Ocp1Error.status(.notImplemented)
    }

    open func beginPassiveComponentUpdate(
        component: OcaComponent,
        serverAddress: OcaNetworkAddress,
        updateFileName: OcaString
    ) async throws {
        throw Ocp1Error.status(.notImplemented)
    }

    public func endUpdateProcess() async throws {
        throw Ocp1Error.status(.notImplemented)
    }
}
