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

@testable import SwiftOCA
@testable import SwiftOCADevice
import XCTest

class MyBooleanActuator: SwiftOCADevice.OcaBooleanActuator {
    override open class var classID: OcaClassID { OcaClassID(parent: super.classID, 65280) }
}

final class SwiftOCADeviceTests: XCTestCase {
    func testLoopbackDevice() async throws {
        var device: AES70LocalDevice

        device = try await AES70LocalDevice()

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

        let deviceMembers = await device.rootBlock.actionObjects
        let connection = await AES70LocalDeviceConnection(device: device)
        try await connection.connect()

        let deviceExpectation = XCTestExpectation(description: "Check device properties")
        var oNo = await connection.deviceManager.objectNumber
        XCTAssertEqual(oNo, OcaDeviceManagerONo)
        oNo = await connection.subscriptionManager.objectNumber
        XCTAssertEqual(oNo, OcaSubscriptionManagerONo)
        let path = await matrix.objectNumberPath
        XCTAssertEqual(path, [OcaRootBlockONo, matrix.objectNumber])
        deviceExpectation.fulfill()
        wait(for: [deviceExpectation], timeout: 1)

        let controllerExpectation = XCTestExpectation(description: "Check controller properties")
        let members = try await connection.rootBlock.resolveActionObjects()
        XCTAssertEqual(members.map(\.objectNumber), deviceMembers.map(\.objectNumber))
        controllerExpectation.fulfill()

        wait(for: [controllerExpectation], timeout: 1)

        try await connection.disconnect()
    }
}
