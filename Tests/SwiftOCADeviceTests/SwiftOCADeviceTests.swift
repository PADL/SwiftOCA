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

@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable import SwiftOCADevice
import XCTest

final class MyBooleanActuator: SwiftOCADevice.OcaBooleanActuator, OcaGroupPeerToPeerMember {
    weak var group: SwiftOCADevice.OcaGroup<MyBooleanActuator>?

    override class var classID: OcaClassID { OcaClassID(parent: super.classID, 65280) }

    func set(to value: Bool) async { setting = value }
}

extension OcaGetPortNameParameters: Equatable {
    public static func == (lhs: OcaGetPortNameParameters, rhs: OcaGetPortNameParameters) -> Bool {
        lhs.portID == rhs.portID
    }
}

extension Ocp1Parameters: Equatable {
    public static func == (lhs: Ocp1Parameters, rhs: Ocp1Parameters) -> Bool {
        lhs.parameterData == rhs.parameterData && lhs.parameterCount == rhs.parameterCount
    }
}

extension Ocp1Command: Equatable {
    public static func == (lhs: SwiftOCA.Ocp1Command, rhs: SwiftOCA.Ocp1Command) -> Bool {
        lhs.commandSize == rhs.commandSize &&
            lhs.handle == rhs.handle &&
            lhs.targetONo == rhs.targetONo &&
            lhs.methodID == rhs.methodID &&
            lhs.parameters == rhs.parameters
    }
}

extension Character {
    var ascii: UInt8 {
        UInt8(unicodeScalars.first!.value)
    }
}

final class SwiftOCADeviceTests: XCTestCase {
    func testSingleFieldOcp1Encoding() async throws {
        let parameters = OcaGetPortNameParameters(portID: OcaPortID(mode: .input, index: 2))
        let encodedParameters: [UInt8] = try Ocp1Encoder().encode(parameters)
        XCTAssertEqual(encodedParameters, [0x01, 0x00, 0x02])

        let command = Ocp1Command(
            commandSize: 0,
            handle: 100,
            targetONo: 5000,
            methodID: OcaMethodID("2.6"),
            parameters: Ocp1Parameters(
                parameterCount: _ocp1ParameterCount(value: parameters),
                parameterData: Data(encodedParameters)
            )
        )
        let encodedCommand: [UInt8] = try Ocp1Encoder().encode(command)
        XCTAssertEqual(
            encodedCommand,
            [0, 0, 0, 0, 0, 0, 0, 100, 0, 0, 19, 136, 0, 2, 0, 6, 1, 1, 0, 2]
        )

        let decodedCommand = try Ocp1Decoder().decode(Ocp1Command.self, from: encodedCommand)
        XCTAssertEqual(command, decodedCommand)

        let decodedParameters = try Ocp1Decoder()
            .decode(OcaGetPortNameParameters.self, from: decodedCommand.parameters.parameterData)
        XCTAssertEqual(parameters, decodedParameters)
    }

    func testMultipleFieldOcp1Encoding() async throws {
        let parameters = OcaBoundedPropertyValue<OcaInt64>(value: -100, minValue: -200, maxValue: 0)
        let encodedParameters: [UInt8] = try Ocp1Encoder().encode(parameters)
        XCTAssertEqual(
            encodedParameters,
            [255, 255, 255, 255, 255, 255, 255, 156, 255, 255, 255, 255, 255, 255, 255, 56, 0, 0, 0,
             0, 0, 0, 0, 0]
        )

        let command = Ocp1Command(
            commandSize: 0,
            handle: 101,
            targetONo: 5001,
            methodID: OcaMethodID("4.1"),
            parameters: Ocp1Parameters(
                parameterCount: _ocp1ParameterCount(value: parameters),
                parameterData: Data(encodedParameters)
            )
        )
        let encodedCommand: [UInt8] = try Ocp1Encoder().encode(command)
        XCTAssertEqual(
            encodedCommand,
            [0, 0, 0, 0, 0, 0, 0, 101, 0, 0, 19, 137, 0, 4, 0, 1, 3, 255, 255, 255, 255, 255, 255,
             255, 156, 255, 255, 255, 255, 255, 255, 255, 56, 0, 0, 0, 0, 0, 0, 0, 0]
        )

        let decodedCommand = try Ocp1Decoder().decode(Ocp1Command.self, from: encodedCommand)
        XCTAssertEqual(command, decodedCommand)

        let decodedParameters = try Ocp1Decoder()
            .decode(
                OcaBoundedPropertyValue<OcaInt64>.self,
                from: decodedCommand.parameters.parameterData
            )
        XCTAssertEqual(parameters, decodedParameters)
    }

    func testVector_AES70_3_2023_8_2_4() async throws {
        let value = OcaCounter(id: 3, value: 100, innitialValue: 0, role: "Errors", notifiers: [])
        let referenceValue = [
            0,
            3,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            100,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            6,
            Character("E").ascii,
            Character("r").ascii,
            Character("r").ascii,
            Character("o").ascii,
            Character("r").ascii,
            Character("s").ascii,
            0,
            0,
        ]
        let encodedValue: [UInt8] = try Ocp1Encoder().encode(value)

        XCTAssertEqual(encodedValue, referenceValue)
    }

    func testVector_AES70_3_2023_9_4_8() async throws {
        let propertyChangedEventData = OcaPropertyChangedEventData(
            propertyID: OcaPropertyID("4.1"),
            propertyValue: OcaDB(-22.0),
            changeType: .currentChanged
        )
        let event = OcaEvent(emitterONo: 10001, eventID: OcaEventID("1.1"))
        let notification = try Ocp1Notification2(
            event: event,
            notificationType: .event,
            data: Ocp1Encoder().encode(propertyChangedEventData)
        )
        let pdu = try Ocp1Connection.encodeOcp1MessagePdu([notification], type: .ocaNtf2)

        let referenceValue: [UInt8] = [
            0x3B, // SyncVal
            0x00, // Protocol Version
            0x01, // Protocol Version = 1
            0x00, // PduSize
            0x00, // PduSize
            0x00, // PduSize
            0x1F, // PduSize = 31
            0x05, // PduType = 5 (notification2)
            0x00, // Message Count
            0x01, // Message Count = 1
            0x00, // Notification Size
            0x00, // Notification Size
            0x00, // Notification Size
            0x16, // Notification Size = 22
            0x00, // Emitter ONo
            0x00, // Emitter ONo
            0x27, // Emitter ONo
            0x11, // Emitter ONo = 10001
            0x00, // Event ID DefLevel
            0x01, // Event ID DefLevel = 1
            0x00, // Event ID EventIndex
            0x01, // Event ID EventIndex = 1
            0x00, // Notification Type = 0 (event)
            0x00, // Property ID DefLevel
            0x04, // Property ID DefLevel = 4
            0x00, // Property ID PropertyIndex
            0x01, // Property ID PropertyIndex = 1
            0xC1, // Property Value
            0xB0, // Property Value
            0x00, // Property Value
            0x00, // Property Value = -22.0
            0x01, // Change Type = 1
        ]
        let encodedValue: [UInt8] = try Ocp1Encoder().encode(pdu)

        XCTAssertEqual(encodedValue, referenceValue)
    }

    func testUnicodeStringEncoding() async throws {
        let string = "✨Unicode✨"
        let encodedString =
            Data([0, 9, 226, 156, 168, 85, 110, 105, 99, 111, 100, 101, 226, 156, 168])

        let ocp1Encoder = Ocp1Encoder()
        XCTAssertEqual(try ocp1Encoder.encode(string), encodedString)

        let ocp1Decoder = Ocp1Decoder()
        XCTAssertEqual(try ocp1Decoder.decode(String.self, from: encodedString), string)
    }

    func testUnicodeScalarEncoding() async throws {
        let string = "🍎"
        let encodedString = Data([0, 1, 0xF0, 0x9F, 0x8D, 0x8E])

        let ocp1Encoder = Ocp1Encoder()
        XCTAssertEqual(try ocp1Encoder.encode(string), encodedString)

        let ocp1Decoder = Ocp1Decoder()
        XCTAssertEqual(try ocp1Decoder.decode(String.self, from: encodedString), string)
    }

    func testAsciiStringEncoding() async throws {
        let string = "ASCII"
        let encodedString = Data([0, 5, 0x41, 0x53, 0x43, 0x49, 0x49])

        let ocp1Encoder = Ocp1Encoder()
        XCTAssertEqual(try ocp1Encoder.encode(string), encodedString)

        let ocp1Decoder = Ocp1Decoder()
        XCTAssertEqual(try ocp1Decoder.decode(String.self, from: encodedString), string)
    }

    func testEmptyStringEncoding() async throws {
        let string = ""
        let encodedString = Data([0, 0])

        let ocp1Encoder = Ocp1Encoder()
        XCTAssertEqual(try ocp1Encoder.encode(string), encodedString)

        let ocp1Decoder = Ocp1Decoder()
        XCTAssertEqual(try ocp1Decoder.decode(String.self, from: encodedString), string)
    }

    let testBlockONo: OcaONo = 10001
    let testGroupONo: OcaONo = 5001

    func testLoopbackDevice() async throws {
        let device = OcaDevice()
        try await device.initializeDefaultObjects()
        let endpoint = try await OcaLocalDeviceEndpoint(device: device)

        let testBlock = try await SwiftOCADevice
            .OcaBlock<MyBooleanActuator>(
                objectNumber: testBlockONo,
                deviceDelegate: device,
                addToRootBlock: true
            )
        let matrix = try await SwiftOCADevice
            .OcaMatrix<MyBooleanActuator>(
                rows: 4,
                columns: 2,
                deviceDelegate: device,
                addToRootBlock: true
            )

        let matrixMembers = await matrix.members
        for x in 0..<matrixMembers.nX {
            for y in 0..<matrixMembers.nY {
                let coordinate = OcaVector2D(x: OcaMatrixCoordinate(x), y: OcaMatrixCoordinate(y))
                let actuator = try await MyBooleanActuator(
                    role: "Actuator \(x),\(y)",
                    deviceDelegate: device,
                    addToRootBlock: false
                )
                try await matrix.add(member: actuator, at: coordinate)
                try await testBlock.add(actionObject: actuator)
            }
        }

        let jsonSerializationExpectation =
            XCTestExpectation(description: "Ensure JSON serialization round-trips")
        let jsonObject = await device.rootBlock.jsonObject
        let jsonResultData = try JSONSerialization.data(withJSONObject: jsonObject)
        let decoded = try JSONSerialization.jsonObject(with: jsonResultData) as! [String: Any]
        XCTAssertEqual(decoded as NSDictionary, jsonObject as NSDictionary)
        jsonSerializationExpectation.fulfill()
        await fulfillment(of: [jsonSerializationExpectation], timeout: 1)

        let connection = await OcaLocalConnection(endpoint)
        let endpointTask = Task { try? await endpoint.run() }
        try await connection.connect()

        let deviceExpectation = XCTestExpectation(description: "Check device properties")
        var oNo = await connection.deviceManager.objectNumber
        XCTAssertEqual(oNo, OcaDeviceManagerONo)
        oNo = await connection.subscriptionManager.objectNumber
        XCTAssertEqual(oNo, OcaSubscriptionManagerONo)
        let path = await matrix.objectNumberPath
        Task { @OcaDevice in XCTAssertEqual(path, [matrix.objectNumber]) }
        deviceExpectation.fulfill()
        await fulfillment(of: [deviceExpectation], timeout: 1)

        let controllerExpectation =
            XCTestExpectation(description: "Check rootBlock controller properties")
        let members = try await connection.rootBlock.resolveActionObjects()
        let deviceMembers = await device.rootBlock.actionObjects
        XCTAssertEqual(members.map(\.objectNumber), deviceMembers.map(\.objectNumber))
        controllerExpectation.fulfill()

        await fulfillment(of: [controllerExpectation], timeout: 1)

        let controllerExpectation2 =
            XCTestExpectation(description: "Check test block controller properties")
        let clientTestBlock: SwiftOCA.OcaBlock? = await connection
            .resolve(object: OcaObjectIdentification(
                oNo: testBlockONo,
                classIdentification: SwiftOCA.OcaBlock.classIdentification
            ))
        XCTAssertNotNil(clientTestBlock)
        let resolvedClientTestBlockActionObjects = try await clientTestBlock!.resolveActionObjects()
        let testBlockMembers = await testBlock.actionObjects
        XCTAssertEqual(
            resolvedClientTestBlockActionObjects.map(\.objectNumber),
            testBlockMembers.map(\.objectNumber)
        )
        controllerExpectation2.fulfill()

        await fulfillment(of: [controllerExpectation2], timeout: 1)

        try await connection.disconnect()
        endpointTask.cancel()
    }

    func testPeerToPeerGroup() async throws {
        let device = OcaDevice()
        try await device.initializeDefaultObjects()
        let endpoint = try await OcaLocalDeviceEndpoint(device: device)

        let testBlock = try await SwiftOCADevice
            .OcaBlock<MyBooleanActuator>(
                objectNumber: testBlockONo,
                deviceDelegate: device,
                addToRootBlock: true
            )

        let group = try await _OcaPeerToPeerGroup<MyBooleanActuator>(
            objectNumber: testGroupONo,
            deviceDelegate: device,
            addToRootBlock: true
        )

        for i in 0..<10 {
            let actuator = try await MyBooleanActuator(
                role: "Actuator \(i)",
                deviceDelegate: device,
                addToRootBlock: false
            )
            try await testBlock.add(actionObject: actuator)
            try await group.add(member: actuator)
        }

        let connection = await OcaLocalConnection(endpoint)
        let endpointTask = Task { try? await endpoint.run() }
        try await connection.connect()

        let controllerExpectation =
            XCTestExpectation(description: "Check test block controller properties")
        let clientTestBlock: SwiftOCA.OcaBlock? = await connection
            .resolve(object: OcaObjectIdentification(
                oNo: testBlockONo,
                classIdentification: SwiftOCA.OcaBlock.classIdentification
            ))
        XCTAssertNotNil(clientTestBlock)
        let resolvedClientTestBlockActionObjects = try await clientTestBlock!.resolveActionObjects()
        let testBlockMembers = await testBlock.actionObjects
        XCTAssertEqual(
            resolvedClientTestBlockActionObjects.map(\.objectNumber),
            testBlockMembers.map(\.objectNumber)
        )
        controllerExpectation.fulfill()
        await fulfillment(of: [controllerExpectation], timeout: 1)

        let allActuators = resolvedClientTestBlockActionObjects
            .compactMap { $0 as? SwiftOCA.OcaBooleanActuator }
        let anActuator = allActuators.first
        XCTAssertNotNil(anActuator)

        for object in allActuators {
            try await object.subscribe()
        }

        anActuator!.setting = .success(true)

        let deviceActuatorExpectation =
            XCTestExpectation(description: "All device actuators in group are set to true")
        try await Task.sleep(for: .milliseconds(100))
        for object in await testBlock.actionObjects {
            let settingValue = await object.setting
            XCTAssertTrue(settingValue)
        }
        deviceActuatorExpectation.fulfill()
        await fulfillment(of: [deviceActuatorExpectation], timeout: 1)

        XCTAssertTrue(allActuators.allSatisfy { $0.setting == .success(true) })
        try await connection.disconnect()
        endpointTask.cancel()
    }

    func testGroupControllerGroup() async throws {
        let device = OcaDevice()
        try await device.initializeDefaultObjects()
        let endpoint = try await OcaLocalDeviceEndpoint(device: device)

        let testBlock = try await SwiftOCADevice
            .OcaBlock<MyBooleanActuator>(
                objectNumber: testBlockONo,
                deviceDelegate: device,
                addToRootBlock: true
            )

        let group = try await _OcaGroupControllerGroup<MyBooleanActuator>(
            objectNumber: testGroupONo,
            deviceDelegate: device,
            addToRootBlock: true
        )

        for i in 0..<10 {
            let actuator = try await MyBooleanActuator(
                role: "Actuator \(i)",
                deviceDelegate: device,
                addToRootBlock: false
            )
            try await testBlock.add(actionObject: actuator)
            try await group.add(member: actuator)
        }

        let connection = await OcaLocalConnection(endpoint)
        let endpointTask = Task { try? await endpoint.run() }
        try await connection.connect()

        let controllerExpectation =
            XCTestExpectation(description: "Check test block controller properties")
        let clientTestBlock: SwiftOCA.OcaBlock? = await connection
            .resolve(object: OcaObjectIdentification(
                oNo: testBlockONo,
                classIdentification: SwiftOCA.OcaBlock.classIdentification
            ))
        XCTAssertNotNil(clientTestBlock)

        let resolvedClientTestBlockActionObjects = try await clientTestBlock!.resolveActionObjects()
        let testBlockMembers = await testBlock.actionObjects
        XCTAssertEqual(
            resolvedClientTestBlockActionObjects.map(\.objectNumber),
            testBlockMembers.map(\.objectNumber)
        )
        controllerExpectation.fulfill()
        await fulfillment(of: [controllerExpectation], timeout: 1)

        let allActuators = resolvedClientTestBlockActionObjects
            .compactMap { $0 as? SwiftOCA.OcaBooleanActuator }
        let anActuator = allActuators.first
        XCTAssertNotNil(anActuator)

        for object in allActuators {
            try await object.subscribe()
        }

        let clientGroupExpectation =
            XCTestExpectation(description: "Resolved actuator group proxy and set setting to true")

        let clientGroupObject: SwiftOCA.OcaGroup? = await connection
            .resolve(object: OcaObjectIdentification(
                oNo: testGroupONo,
                classIdentification: SwiftOCA.OcaGroup.classIdentification
            ))
        XCTAssertNotNil(clientGroupObject)

        if let clientGroupObject {
            let clientGroupProxy: SwiftOCA.OcaBooleanActuator = try await clientGroupObject
                .resolveGroupController()
            XCTAssertNotNil(clientGroupProxy)
            clientGroupProxy.setting = .success(true)
            clientGroupExpectation.fulfill()
        }

        await fulfillment(of: [clientGroupExpectation], timeout: 1)

        let deviceActuatorExpectation =
            XCTestExpectation(description: "All device actuators in group are set to true")
        try await Task.sleep(for: .milliseconds(100))

        for object in await testBlock.actionObjects {
            let settingValue = await object.setting
            XCTAssertTrue(settingValue)
        }
        deviceActuatorExpectation.fulfill()
        await fulfillment(of: [deviceActuatorExpectation], timeout: 1)

        XCTAssertTrue(allActuators.allSatisfy { $0.setting == .success(true) })
        try await connection.disconnect()
        endpointTask.cancel()
    }
}

/// https://github.com/apple/swift-corelibs-xctest/issues/436
extension XCTestCase {
    /// Wait on an array of expectations for up to the specified timeout, and optionally specify
    /// whether they
    /// must be fulfilled in the given order. May return early based on fulfillment of the waited on
    /// expectations.
    ///
    /// - Parameter expectations: The expectations to wait on.
    /// - Parameter timeout: The maximum total time duration to wait on all expectations.
    /// - Parameter enforceOrder: Specifies whether the expectations must be fulfilled in the order
    ///   they are specified in the `expectations` Array. Default is false.
    /// - Parameter file: The file name to use in the error message if
    ///   expectations are not fulfilled before the given timeout. Default is the file
    ///   containing the call to this method. It is rare to provide this
    ///   parameter when calling this method.
    /// - Parameter line: The line number to use in the error message if the
    ///   expectations are not fulfilled before the given timeout. Default is the line
    ///   number of the call to this method in the calling file. It is rare to
    ///   provide this parameter when calling this method.
    ///
    /// - SeeAlso: XCTWaiter
    func fulfillment(
        of expectations: [XCTestExpectation],
        timeout: TimeInterval,
        enforceOrder: Bool = false
    ) async {
        await withCheckedContinuation { continuation in
            // This function operates by blocking a background thread instead of one owned by
            // libdispatch or by the
            // Swift runtime (as used by Swift concurrency.) To ensure we use a thread owned by
            // neither subsystem, use
            // Foundation's Thread.detachNewThread(_:).
            Thread.detachNewThread { [self] in
                wait(for: expectations, timeout: timeout, enforceOrder: enforceOrder)
                continuation.resume()
            }
        }
    }
}
