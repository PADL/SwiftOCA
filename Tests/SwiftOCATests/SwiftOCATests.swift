@testable import SwiftOCADevice
@testable import SwiftOCA
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
                    deviceDelegate: device,
                    addToRootBlock: false
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
        XCTAssertEqual(members.map { $0.objectNumber }, deviceMembers.map { $0.objectNumber })
        controllerExpectation.fulfill()

        wait(for: [controllerExpectation], timeout: 1)

        try await connection.disconnect()
    }
}
