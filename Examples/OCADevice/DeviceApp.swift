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
import SwiftOCADevice

@main
public enum DeviceApp {
    static var testActuator: SwiftOCADevice.OcaBooleanActuator?
    static let port: UInt16 = 65000

    public static func main() async throws {
        var listenAddress = sockaddr_in()
        listenAddress.sin_family = sa_family_t(AF_INET)
        listenAddress.sin_addr.s_addr = INADDR_ANY
        listenAddress.sin_port = port.bigEndian

        var listenAddressData = Data()
        withUnsafeBytes(of: &listenAddress) { bytes in
            listenAddressData = Data(bytes: bytes.baseAddress!, count: bytes.count)
        }

        let device = AES70Device.shared
        try await device.initializeDefaultObjects()
        #if os(Linux)
        let streamEndpoint =
            try await AES70OCP1IORingStreamDeviceEndpoint(address: listenAddressData)
        let datagramEndpoint =
            try await AES70OCP1IORingDatagramDeviceEndpoint(address: listenAddressData)
        #else
        let streamEndpoint = try await AES70OCP1DeviceEndpoint(address: listenAddressData)
        #endif

        class MyBooleanActuator: SwiftOCADevice.OcaBooleanActuator {
            override open class var classID: OcaClassID { OcaClassID(parent: super.classID, 65280) }
        }

        let matrix = try await SwiftOCADevice
            .OcaMatrix<MyBooleanActuator>(
                rows: 4,
                columns: 2,
                deviceDelegate: device
            )

        let block = try await SwiftOCADevice
            .OcaBlock<SwiftOCADevice.OcaWorker>(role: "Test Block", deviceDelegate: device)

        for x in 0..<matrix.members.nX {
            for y in 0..<matrix.members.nY {
                let coordinate = OcaVector2D(x: OcaMatrixCoordinate(x), y: OcaMatrixCoordinate(y))
                let actuator = try await MyBooleanActuator(
                    role: "Actuator \(x),\(y)",
                    deviceDelegate: device,
                    addToRootBlock: false
                )
                try block.add(actionObject: actuator)
                try matrix.add(member: actuator, at: coordinate)
            }
        }

        let gain = try await SwiftOCADevice.OcaGain(
            role: "Test Gain",
            deviceDelegate: device,
            addToRootBlock: false
        )
        try block.add(actionObject: gain)

        try await serializeDeserialize(block)

        let _ = try await SwiftOCADevice.OcaControlNetwork(
            role: "OCA Control Network",
            deviceDelegate: device
        )

        await withThrowingTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask {
                print("Starting OCP.1 stream endpoint \(streamEndpoint)...")
                try await streamEndpoint.start()
            }
            #if os(Linux)
            taskGroup.addTask {
                print("Starting OCP.1 datagram endpoint \(datagramEndpoint)...")
                try await datagramEndpoint.start()
            }
            #endif
        }
    }
}

func serializeDeserialize(
    _ object: SwiftOCADevice
        .OcaBlock<SwiftOCADevice.OcaWorker>
) async throws {
    do {
        let jsonResultData = try JSONSerialization.data(withJSONObject: object.jsonObject)
        print(String(data: jsonResultData, encoding: .utf8)!)

        let decoded = try JSONSerialization.jsonObject(with: jsonResultData) as! [String: Any]
        try await AES70Device.shared.deserialize(jsonObject: decoded)
    } catch {
        debugPrint("coding error: \(error)")
    }
}
