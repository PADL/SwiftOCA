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

import FlyingSocks
import Foundation
import SwiftOCA
import SwiftOCADevice

@main
public enum DeviceApp {
    static var testActuator: SwiftOCADevice.OcaBooleanActuator?

    public static func main() async throws {
        var localAddress = sockaddr_in.inet(port: 65000)
        var localAddressData = Data()

        signal(SIGPIPE, SIG_IGN)

        withUnsafeBytes(of: &localAddress) { bytes in
            localAddressData = Data(bytes: bytes.baseAddress!, count: bytes.count)
        }

        let device = AES70Device.shared
        try await device.initializeDefaultObjects()
        let endpoint = try await AES70OCP1DeviceEndpoint(address: localAddressData)

        class MyBooleanActuator: SwiftOCADevice.OcaBooleanActuator {
            override open class var classID: OcaClassID { OcaClassID(parent: super.classID, 65280) }
        }

        let matrix = try await SwiftOCADevice
            .OcaMatrix<MyBooleanActuator>(
                rows: 4,
                columns: 2,
                deviceDelegate: device
            )

        for x in 0..<matrix.members.nX {
            for y in 0..<matrix.members.nY {
                let coordinate = OcaVector2D(x: OcaMatrixCoordinate(x), y: OcaMatrixCoordinate(y))
                let actuator = try await MyBooleanActuator(
                    role: "Actuator \(x),\(y)",
                    deviceDelegate: device
                )
                try matrix.add(member: actuator, at: coordinate)
            }
        }

        // NB: we still need to add objects to the root block because they must have containing block
        print("Starting OCP.1 endpoint \(endpoint)...")
        try await endpoint.start()
    }
}
