//
// Copyright (c) 2024 PADL Software Pty Ltd
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
import XCTest

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

extension OcaMediaSinkConnector: Equatable {
    public static func == (
        lhs: SwiftOCA.OcaMediaSinkConnector,
        rhs: SwiftOCA.OcaMediaSinkConnector
    ) -> Bool {
        lhs.idInternal == rhs.idInternal &&
            lhs.idExternal == rhs.idExternal &&
            lhs.connection == rhs.connection &&
            lhs.availableCodings == rhs.availableCodings &&
            lhs.pinCount == rhs.pinCount &&
            lhs.channelPinMap == rhs.channelPinMap &&
            lhs.alignmentLevel == rhs.alignmentLevel &&
            lhs.alignmentGain == rhs.alignmentGain &&
            lhs.currentCoding == rhs.currentCoding
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
        let parameters = OcaBoundedPropertyValue<OcaInt64>(
            value: -100,
            minValue: -200,
            maxValue: 0
        )
        let encodedParameters: [UInt8] = try Ocp1Encoder().encode(parameters)
        XCTAssertEqual(
            encodedParameters,
            [
                255,
                255,
                255,
                255,
                255,
                255,
                255,
                156,
                255,
                255,
                255,
                255,
                255,
                255,
                255,
                56,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
            ]
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

    func testMapEncoding() async throws {
        let map = ["A": UInt16(1), "B": UInt16(2)]

        // dictionary keys are unordered so test both permutations
        let encodedMap_1 =
            Data([0x00, 0x02, 0x00, 0x01, 0x41, 0x00, 0x01, 0x00, 0x01, 0x42, 0x00, 0x02])
        let encodedMap_2 =
            Data([0x00, 0x02, 0x00, 0x01, 0x42, 0x00, 0x02, 0x00, 0x01, 0x41, 0x00, 0x01])

        let ocp1Encoder = Ocp1Encoder()
        let encodedMap: Data = try ocp1Encoder.encode(map)
        XCTAssertTrue(encodedMap == encodedMap_1 || encodedMap == encodedMap_2)

        let ocp1Decoder = Ocp1Decoder()
        XCTAssertEqual(try ocp1Decoder.decode([String: UInt16].self, from: encodedMap), map)
    }

    func testMultiMapEncoding() async throws {
        let multiMap: OcaMultiMap<String, OcaUint16> = ["A": [1, 2, 3]]
        let encodedMultiMap =
            Data([0x00, 0x01, 0x00, 0x01, 0x41, 0x00, 0x03, 0x00, 0x01, 0x00, 0x02, 0x00, 0x03])

        let ocp1Encoder = Ocp1Encoder()
        XCTAssertEqual(try ocp1Encoder.encode(multiMap), encodedMultiMap)

        let ocp1Decoder = Ocp1Decoder()
        XCTAssertEqual(
            try ocp1Decoder.decode(OcaMultiMap<String, OcaUint16>.self, from: encodedMultiMap),
            multiMap
        )
    }

    func testMediaSinkConnectorEncoding() async throws {
        let mediaCoding = OcaMediaCoding(
            codingSchemeID: 1,
            codecParameters: "1234",
            clockONo: 4096
        )
        let sink = OcaMediaSinkConnector(
            idInternal: 0,
            idExternal: "0000",
            connection: OcaMediaConnection(
                secure: false,
                streamParameters: LengthTaggedData(),
                streamCastMode: .multicast,
                streamChannelCount: 0xA
            ),
            availableCodings: [mediaCoding],
            pinCount: 8,
            channelPinMap: [:],
            alignmentLevel: 0.0,
            alignmentGain: 0.0,
            currentCoding: mediaCoding
        )
        let encodedSink = Data([
            0x00,
            0x00,
            0x00,
            0x04,
            0x30,
            0x30,
            0x30,
            0x30,
            0x00,
            0x00,
            0x00,
            0x02,
            0x00,
            0x0A,
            0x00,
            0x01,
            0x00,
            0x01,
            0x00,
            0x04,
            0x31,
            0x32,
            0x33,
            0x34,
            0x00,
            0x00,
            0x10,
            0x00,
            0x00,
            0x08,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x01,
            0x00,
            0x04,
            0x31,
            0x32,
            0x33,
            0x34,
            0x00,
            0x00,
            0x10,
            0x00,
        ])

        let ocp1Encoder = Ocp1Encoder()
        XCTAssertEqual(try ocp1Encoder.encode(sink), encodedSink)

        let ocp1Decoder = Ocp1Decoder()
        XCTAssertEqual(try ocp1Decoder.decode(OcaMediaSinkConnector.self, from: encodedSink), sink)
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
