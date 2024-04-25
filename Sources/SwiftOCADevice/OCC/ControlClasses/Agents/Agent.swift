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

open class OcaAgent: OcaRoot, OcaOwnable, OcaLabelRepresentable {
    override open class var classID: OcaClassID { OcaClassID("1.2") }

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

    override public func handleCommand(
        _ command: Ocp1Command,
        from controller: any OcaController
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("2.4"):
            try decodeNullCommand(command)
            return try await encodeResponse(path)
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }
}
