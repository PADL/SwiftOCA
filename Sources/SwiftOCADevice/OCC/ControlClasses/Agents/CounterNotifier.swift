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

open class OcaCounterNotifier: OcaAgent {
    override public class var classID: OcaClassID { OcaClassID("1.2.18") }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.2"),
        setMethodID: OcaMethodID("3.3")
    )
    public var filterParameters: OcaCounterNotifierFilterParameters?

    open func getLastUpdate() async throws -> OcaList<OcaCounterUpdate> {
        throw Ocp1Error.status(.notImplemented)
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: any OcaController
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("3.1"):
            try decodeNullCommand(command)
            try await ensureWritable(by: controller, command: command)
            return try encodeResponse(try await getLastUpdate())
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }
}
