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

import SocketAddress
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif

private extension _Ocp1Codable {
  var bytes: [UInt8] {
    var bytes = [UInt8]()
    encode(into: &bytes)
    return bytes
  }
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
  func testSingleFieldOcp1Encoding() throws {
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
    let encodedCommand: [UInt8] = command.bytes
    XCTAssertEqual(
      encodedCommand,
      [0, 0, 0, 0, 0, 0, 0, 100, 0, 0, 19, 136, 0, 2, 0, 6, 1, 1, 0, 2]
    )

    let decodedCommand = try Ocp1Command(bytes: encodedCommand)
    XCTAssertEqual(command, decodedCommand)

    let decodedParameters = try Ocp1Decoder()
      .decode(OcaGetPortNameParameters.self, from: decodedCommand.parameters.parameterData)
    XCTAssertEqual(parameters, decodedParameters)
  }

  func testMultipleFieldOcp1Encoding() throws {
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
    let encodedCommand: [UInt8] = command.bytes
    XCTAssertEqual(
      encodedCommand,
      [0, 0, 0, 0, 0, 0, 0, 101, 0, 0, 19, 137, 0, 4, 0, 1, 3, 255, 255, 255, 255, 255, 255,
       255, 156, 255, 255, 255, 255, 255, 255, 255, 56, 0, 0, 0, 0, 0, 0, 0, 0]
    )

    let decodedCommand = try Ocp1Command(bytes: encodedCommand)
    XCTAssertEqual(command, decodedCommand)

    let decodedParameters = try Ocp1Decoder()
      .decode(
        OcaBoundedPropertyValue<OcaInt64>.self,
        from: decodedCommand.parameters.parameterData
      )
    XCTAssertEqual(parameters, decodedParameters)
  }

  func testVector_AES70_3_2023_8_2_4() throws {
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

  func testVector_AES70_3_2023_9_4_8() throws {
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

  func testUnicodeStringEncoding() throws {
    let string = "✨Unicode✨"
    let encodedString =
      Data([0, 9, 226, 156, 168, 85, 110, 105, 99, 111, 100, 101, 226, 156, 168])

    let ocp1Encoder = Ocp1Encoder()
    XCTAssertEqual(try ocp1Encoder.encode(string), encodedString)

    let ocp1Decoder = Ocp1Decoder()
    XCTAssertEqual(try ocp1Decoder.decode(String.self, from: encodedString), string)
  }

  func testUnicodeScalarEncoding() throws {
    let string = "🍎"
    let encodedString = Data([0, 1, 0xF0, 0x9F, 0x8D, 0x8E])

    let ocp1Encoder = Ocp1Encoder()
    XCTAssertEqual(try ocp1Encoder.encode(string), encodedString)

    let ocp1Decoder = Ocp1Decoder()
    XCTAssertEqual(try ocp1Decoder.decode(String.self, from: encodedString), string)
  }

  func testAsciiStringEncoding() throws {
    let string = "ASCII"
    let encodedString = Data([0, 5, 0x41, 0x53, 0x43, 0x49, 0x49])

    let ocp1Encoder = Ocp1Encoder()
    XCTAssertEqual(try ocp1Encoder.encode(string), encodedString)

    let ocp1Decoder = Ocp1Decoder()
    XCTAssertEqual(try ocp1Decoder.decode(String.self, from: encodedString), string)
  }

  func testEmptyStringEncoding() throws {
    let string = ""
    let encodedString = Data([0, 0])

    let ocp1Encoder = Ocp1Encoder()
    XCTAssertEqual(try ocp1Encoder.encode(string), encodedString)

    let ocp1Decoder = Ocp1Decoder()
    XCTAssertEqual(try ocp1Decoder.decode(String.self, from: encodedString), string)
  }

  func testMapEncoding() throws {
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

  func testMultiMapEncoding() throws {
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

  func testMediaSinkConnectorEncoding() throws {
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

  func testBuiltinEncoderDecoderNtf1() throws {
    let eventParameters = Data([0x00, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x01])
    let eventData = Ocp1EventData(
      event: OcaEvent(emitterONo: 0x1234, eventID: OcaEventID(defLevel: 1, eventIndex: 1)),
      eventParameters: eventParameters
    )
    let params = Ocp1NtfParams(parameterCount: 1, context: OcaBlob(), eventData: eventData)
    let aNotification = Ocp1Notification1(
      notificationSize: 0,
      targetONo: 0x5678,
      methodID: "1.1",
      parameters: params
    )

    let encodedNotification = aNotification.bytes
    XCTAssertEqual(
      encodedNotification,
      [
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x56,
        0x78,
        0x00,
        0x01,
        0x00,
        0x01,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x12,
        0x34,
        0x00,
        0x01,
        0x00,
        0x01,
        0x00,
        0x04,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x01,
      ]
    )

    let decodedNotification = try Ocp1Notification1(bytes: aNotification.bytes)
    XCTAssertEqual(decodedNotification, aNotification)
  }

  func testBuiltinEncoderDecoderNtf2() throws {
    let eventParameters = Data([0x00, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x01])
    let aNotification = Ocp1Notification2(
      notificationSize: 0,
      event: OcaEvent(emitterONo: 0x1234, eventID: OcaEventID(defLevel: 1, eventIndex: 1)),
      notificationType: .event,
      data: eventParameters
    )

    let encodedNotification = aNotification.bytes
    XCTAssertEqual(
      encodedNotification,
      [0, 0, 0, 0, 0, 0, 18, 52, 0, 1, 0, 1, 0, 0, 4, 0, 1, 0, 0, 0, 0, 1]
    )

    let decodedNotification = try Ocp1Notification2(bytes: encodedNotification)
    XCTAssertEqual(decodedNotification, aNotification)
  }

  func testBuiltinEncoderDecoderKeepAlive1() throws {
    let encodedKeepAlive1 = Ocp1KeepAlive1(heartBeatTime: 100).bytes
    XCTAssertEqual(
      encodedKeepAlive1,
      [0, 100]
    )

    let decodedKeepAlive1 = try Ocp1KeepAlive1(bytes: encodedKeepAlive1)
    XCTAssertEqual(decodedKeepAlive1.heartBeatTime, 100)
  }

  func testBuiltinEncoderDecoderKeepAlive2() throws {
    let encodedKeepAlive2 = Ocp1KeepAlive2(heartBeatTime: 200).bytes
    XCTAssertEqual(
      encodedKeepAlive2,
      [0, 0, 0, 200]
    )

    let decodedKeepAlive2 = try Ocp1KeepAlive2(bytes: encodedKeepAlive2)
    XCTAssertEqual(decodedKeepAlive2.heartBeatTime, 200)
  }

  func testEmptyOcaBlob() throws {
    let encoded = OcaBlob().bytes
    XCTAssertEqual(encoded, [0, 0])
    XCTAssertEqual(try OcaBlob(bytes: encoded), OcaBlob())
  }

  func testEmptyOcaLongBlob() throws {
    let encoded = OcaLongBlob().bytes
    XCTAssertEqual(encoded, [0, 0, 0, 0])
    XCTAssertEqual(try OcaLongBlob(bytes: encoded), OcaLongBlob())
  }

  func testOcaBlobRoundTrip() throws {
    let blob = OcaBlob([0xDE, 0xAD, 0xBE, 0xEF])
    let ocp1EncodedBlob: [UInt8] = try Ocp1Encoder().encode(blob)
    var rawEncodedBlob = [UInt8]()
    blob.encode(into: &rawEncodedBlob)

    XCTAssertEqual(ocp1EncodedBlob, rawEncodedBlob)

    let ocp1DecodedBlob = try Ocp1Decoder().decode(OcaBlob.self, from: rawEncodedBlob)
    let rawDecodedBlob = try OcaBlob(bytes: ocp1EncodedBlob)

    XCTAssertEqual(ocp1DecodedBlob, rawDecodedBlob)
  }

  func testOcaLongBlobRoundTrip() throws {
    let blob = OcaLongBlob([0xDE, 0xAD, 0xBE, 0xEF])
    let ocp1EncodedBlob: [UInt8] = try Ocp1Encoder().encode(blob)
    var rawEncodedBlob = [UInt8]()
    blob.encode(into: &rawEncodedBlob)

    XCTAssertEqual(ocp1EncodedBlob, rawEncodedBlob)

    let ocp1DecodedBlob = try Ocp1Decoder().decode(OcaLongBlob.self, from: rawEncodedBlob)
    let rawDecodedBlob = try OcaLongBlob(bytes: ocp1EncodedBlob)

    XCTAssertEqual(ocp1DecodedBlob, rawDecodedBlob)
  }

  func testEmptyCommand() throws {
    let encoded: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0]
    let command = try Ocp1Command(bytes: encoded)
    XCTAssertEqual(command, Ocp1Command(handle: 0, targetONo: 0, methodID: "1.1"))
  }

  func testEmptyResponse() throws {
    let encoded: [UInt8] = [0, 0, 0, 0, 0, 0, 2, 0, 1, 0]
    let response = try Ocp1Response(bytes: encoded)
    XCTAssertEqual(response.statusCode, .protocolVersionError)
    XCTAssertEqual(response.handle, 512)
    XCTAssertEqual(response.parameters.parameterCount, 0)
    XCTAssertEqual(response.parameters.parameterData, Data())
  }

  func testNonEmptyResponse() throws {
    let encoded: [UInt8] = [0, 0, 0, 0, 0, 0, 2, 0, 1, 1, 1]
    let response = try Ocp1Response(bytes: encoded)
    XCTAssertEqual(response.statusCode, .protocolVersionError)
    XCTAssertEqual(response.handle, 512)
    XCTAssertEqual(response.parameters.parameterCount, 1)
    XCTAssertEqual(response.parameters.parameterData, Data([1]))
  }

  func testTypeErasedPropertyChangedEvent() throws {
    let propertyChangedEventData = OcaPropertyChangedEventData(
      propertyID: OcaPropertyID("4.1"),
      propertyValue: OcaDB(-22.0),
      changeType: .currentChanged
    )
    let encodedPropertyChangedEvent: Data = try Ocp1Encoder().encode(propertyChangedEventData)
    let typeErasedPropertyChangedEvent =
      try OcaAnyPropertyChangedEventData(data: encodedPropertyChangedEvent)
    XCTAssertEqual(typeErasedPropertyChangedEvent.propertyID, propertyChangedEventData.propertyID)
    XCTAssertEqual(
      typeErasedPropertyChangedEvent.propertyValue,
      try Ocp1Encoder().encode(OcaDB(-22.0))
    )
    XCTAssertEqual(typeErasedPropertyChangedEvent.changeType, propertyChangedEventData.changeType)
  }

  // MARK: - Additional Serialization Tests

  func testOcaPropertyIDEncoding() throws {
    let propertyID = OcaPropertyID("3.5")
    let encodedData: [UInt8] = try Ocp1Encoder().encode(propertyID)
    XCTAssertEqual(encodedData, [0x00, 0x03, 0x00, 0x05])

    let decodedPropertyID = try Ocp1Decoder().decode(OcaPropertyID.self, from: encodedData)
    XCTAssertEqual(propertyID, decodedPropertyID)
  }

  func testOcaMethodIDEncoding() throws {
    let methodID = OcaMethodID("2.10")
    let encodedData: [UInt8] = try Ocp1Encoder().encode(methodID)
    XCTAssertEqual(encodedData, [0x00, 0x02, 0x00, 0x0A])

    let decodedMethodID = try Ocp1Decoder().decode(OcaMethodID.self, from: encodedData)
    XCTAssertEqual(methodID, decodedMethodID)
  }

  func testOcaClassIDEncoding() throws {
    let classID = OcaClassID([1, 2, 3, 4])
    let encodedData: [UInt8] = try Ocp1Encoder().encode(classID)
    XCTAssertEqual(encodedData, [0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04])

    let decodedClassID = try Ocp1Decoder().decode(OcaClassID.self, from: encodedData)
    XCTAssertEqual(classID, decodedClassID)
  }

  func testOcaPortIDEncoding() throws {
    let portID = OcaPortID(mode: .output, index: 5)
    let encodedData: [UInt8] = try Ocp1Encoder().encode(portID)
    XCTAssertEqual(encodedData, [0x02, 0x00, 0x05])

    let decodedPortID = try Ocp1Decoder().decode(OcaPortID.self, from: encodedData)
    XCTAssertEqual(portID, decodedPortID)
  }

  func testOcaEventIDEncoding() throws {
    let eventID = OcaEventID(defLevel: 2, eventIndex: 7)
    let encodedData: [UInt8] = try Ocp1Encoder().encode(eventID)
    XCTAssertEqual(encodedData, [0x00, 0x02, 0x00, 0x07])

    let decodedEventID = try Ocp1Decoder().decode(OcaEventID.self, from: encodedData)
    XCTAssertEqual(eventID, decodedEventID)
  }

  func testOcaVector2DEncoding() throws {
    let vector = OcaVector2D<OcaUint16>(x: 10, y: 20)
    let encodedData: [UInt8] = try Ocp1Encoder().encode(vector)
    XCTAssertEqual(encodedData, [0x00, 0x0A, 0x00, 0x14])

    let decodedVector = try Ocp1Decoder().decode(OcaVector2D<OcaUint16>.self, from: encodedData)
    XCTAssertEqual(vector.x, decodedVector.x)
    XCTAssertEqual(vector.y, decodedVector.y)
  }

  func testOcaTimePTPEncoding() throws {
    let timePTP = OcaTimePTP(seconds: 1000, nanoseconds: 500_000_000)
    let encodedData: [UInt8] = try Ocp1Encoder().encode(timePTP)

    let decodedTimePTP = try Ocp1Decoder().decode(OcaTimePTP.self, from: encodedData)
    XCTAssertEqual(timePTP.seconds, decodedTimePTP.seconds)
    XCTAssertEqual(timePTP.nanoseconds, decodedTimePTP.nanoseconds)
  }

  func testOcaTimeEncoding() throws {
    let time = OcaTime(seconds: 1000, nanoseconds: 500_000_000)
    let encodedData: [UInt8] = try Ocp1Encoder().encode(time)

    let decodedTime = try Ocp1Decoder().decode(OcaTime.self, from: encodedData)
    XCTAssertEqual(time.seconds, decodedTime.seconds)
    XCTAssertEqual(time.nanoseconds, decodedTime.nanoseconds)
  }

  func testOcaLibVolTypeEncoding() throws {
    let libVolType = OcaLibVolType(authority: OcaOrganizationID((0x01, 0x02, 0x03)), id: 1)
    let encodedData: [UInt8] = try Ocp1Encoder().encode(libVolType)

    let decodedLibVolType = try Ocp1Decoder().decode(OcaLibVolType.self, from: encodedData)
    XCTAssertEqual(libVolType.authority, decodedLibVolType.authority)
    XCTAssertEqual(libVolType.id, decodedLibVolType.id)
  }

  func testOcaStatusEncoding() throws {
    let status = OcaStatus.ok
    let encodedData: [UInt8] = try Ocp1Encoder().encode(status)
    XCTAssertEqual(encodedData, [0x00])

    let decodedStatus = try Ocp1Decoder().decode(OcaStatus.self, from: encodedData)
    XCTAssertEqual(status, decodedStatus)
  }

  func testComplexStructEncoding() throws {
    let objectIdentification = OcaObjectIdentification(
      oNo: 1234,
      classIdentification: OcaClassIdentification(
        classID: OcaClassID([1, 2, 3]),
        classVersion: 100
      )
    )

    let encodedData: [UInt8] = try Ocp1Encoder().encode(objectIdentification)
    let decodedObjectIdentification = try Ocp1Decoder().decode(
      OcaObjectIdentification.self,
      from: encodedData
    )

    XCTAssertEqual(objectIdentification.oNo, decodedObjectIdentification.oNo)
    XCTAssertEqual(
      objectIdentification.classIdentification.classID,
      decodedObjectIdentification.classIdentification.classID
    )
    XCTAssertEqual(
      objectIdentification.classIdentification.classVersion,
      decodedObjectIdentification.classIdentification.classVersion
    )
  }

  func testNestedArrayEncoding() throws {
    let nestedArray: [[OcaUint16]] = [[1, 2, 3], [4, 5], [6, 7, 8, 9]]
    let encodedData: [UInt8] = try Ocp1Encoder().encode(nestedArray)
    let decodedArray = try Ocp1Decoder().decode([[OcaUint16]].self, from: encodedData)

    XCTAssertEqual(nestedArray, decodedArray)
  }

  func testEmptyCollectionsEncoding() throws {
    let emptyArray: [OcaUint16] = []
    let emptyMap: [String: OcaUint16] = [:]

    let encodedArray: [UInt8] = try Ocp1Encoder().encode(emptyArray)
    let encodedMap: [UInt8] = try Ocp1Encoder().encode(emptyMap)

    let decodedArray = try Ocp1Decoder().decode([OcaUint16].self, from: encodedArray)
    let decodedMap = try Ocp1Decoder().decode([String: OcaUint16].self, from: encodedMap)

    XCTAssertEqual(emptyArray, decodedArray)
    XCTAssertEqual(emptyMap, decodedMap)
  }

  func testLargeNumberEncoding() throws {
    let largeUInt64: OcaUint64 = 18_446_744_073_709_551_615 // Max UInt64
    let largeInt64: OcaInt64 = -9_223_372_036_854_775_808 // Min Int64

    let encodedUInt64: [UInt8] = try Ocp1Encoder().encode(largeUInt64)
    let encodedInt64: [UInt8] = try Ocp1Encoder().encode(largeInt64)

    let decodedUInt64 = try Ocp1Decoder().decode(OcaUint64.self, from: encodedUInt64)
    let decodedInt64 = try Ocp1Decoder().decode(OcaInt64.self, from: encodedInt64)

    XCTAssertEqual(largeUInt64, decodedUInt64)
    XCTAssertEqual(largeInt64, decodedInt64)
  }

  func testFloatingPointPrecision() throws {
    let float32: OcaFloat32 = 3.14159265359
    let float64: OcaFloat64 = 3.141592653589793238462643383279

    let encodedFloat32: [UInt8] = try Ocp1Encoder().encode(float32)
    let encodedFloat64: [UInt8] = try Ocp1Encoder().encode(float64)

    let decodedFloat32 = try Ocp1Decoder().decode(OcaFloat32.self, from: encodedFloat32)
    let decodedFloat64 = try Ocp1Decoder().decode(OcaFloat64.self, from: encodedFloat64)

    XCTAssertEqual(float32, decodedFloat32)
    XCTAssertEqual(float64, decodedFloat64)
  }

  func testSpecialFloatingPointValues() throws {
    let infinityFloat: OcaFloat32 = .infinity
    let negativeInfinityFloat: OcaFloat32 = -.infinity
    let nanFloat: OcaFloat32 = .nan
    let zeroFloat: OcaFloat32 = 0.0
    let negativeZeroFloat: OcaFloat32 = -0.0

    let encodedInfinity: [UInt8] = try Ocp1Encoder().encode(infinityFloat)
    let encodedNegativeInfinity: [UInt8] = try Ocp1Encoder().encode(negativeInfinityFloat)
    let encodedNaN: [UInt8] = try Ocp1Encoder().encode(nanFloat)
    let encodedZero: [UInt8] = try Ocp1Encoder().encode(zeroFloat)
    let encodedNegativeZero: [UInt8] = try Ocp1Encoder().encode(negativeZeroFloat)

    let decodedInfinity = try Ocp1Decoder().decode(OcaFloat32.self, from: encodedInfinity)
    let decodedNegativeInfinity = try Ocp1Decoder().decode(
      OcaFloat32.self,
      from: encodedNegativeInfinity
    )
    let decodedNaN = try Ocp1Decoder().decode(OcaFloat32.self, from: encodedNaN)
    let decodedZero = try Ocp1Decoder().decode(OcaFloat32.self, from: encodedZero)
    let decodedNegativeZero = try Ocp1Decoder().decode(OcaFloat32.self, from: encodedNegativeZero)

    XCTAssertEqual(infinityFloat, decodedInfinity)
    XCTAssertEqual(negativeInfinityFloat, decodedNegativeInfinity)
    XCTAssertTrue(decodedNaN.isNaN)
    XCTAssertEqual(zeroFloat, decodedZero)
    XCTAssertEqual(negativeZeroFloat, decodedNegativeZero)
  }

  func testLargeBlobEncoding() throws {
    let largeData = Data(repeating: 0xAB, count: 65536)
    let largeBlob = OcaLongBlob(largeData)

    let encodedBlob: Data = try Ocp1Encoder().encode(largeBlob)
    let decodedBlob = try Ocp1Decoder().decode(OcaLongBlob.self, from: encodedBlob)

    XCTAssertEqual(largeBlob, decodedBlob)
  }

  func testOptionalEncoding() throws {
    // Test encoding of optional values that are not nil
    let someValue: OcaUint16? = 42

    let encodedSomeValue: Data = try Ocp1Encoder().encode(someValue)
    let decodedSomeValue = try Ocp1Decoder().decode(OcaUint16?.self, from: encodedSomeValue)

    XCTAssertEqual(someValue, decodedSomeValue)

    // Note: OCP.1 encoder appears to not support encoding nil values directly
    // This is consistent with the protocol specification where nil values
    // are typically handled at a higher level
  }

  func testRoundTripConsistency() throws {
    let testValues: [Any] = [
      OcaUint8(255),
      OcaInt8(-128),
      OcaUint16(65535),
      OcaInt16(-32768),
      OcaUint32(4_294_967_295),
      OcaInt32(-2_147_483_648),
      OcaFloat32(123.456),
      OcaFloat64(123.456789012345),
      "Test String with émojis 🚀",
      true,
      false,
    ]

    for value in testValues {
      switch value {
      case let v as OcaUint8:
        let encoded: Data = try Ocp1Encoder().encode(v)
        let decoded = try Ocp1Decoder().decode(OcaUint8.self, from: encoded)
        XCTAssertEqual(v, decoded)
      case let v as OcaInt8:
        let encoded: Data = try Ocp1Encoder().encode(v)
        let decoded = try Ocp1Decoder().decode(OcaInt8.self, from: encoded)
        XCTAssertEqual(v, decoded)
      case let v as OcaUint16:
        let encoded: Data = try Ocp1Encoder().encode(v)
        let decoded = try Ocp1Decoder().decode(OcaUint16.self, from: encoded)
        XCTAssertEqual(v, decoded)
      case let v as OcaInt16:
        let encoded: Data = try Ocp1Encoder().encode(v)
        let decoded = try Ocp1Decoder().decode(OcaInt16.self, from: encoded)
        XCTAssertEqual(v, decoded)
      case let v as OcaUint32:
        let encoded: Data = try Ocp1Encoder().encode(v)
        let decoded = try Ocp1Decoder().decode(OcaUint32.self, from: encoded)
        XCTAssertEqual(v, decoded)
      case let v as OcaInt32:
        let encoded: Data = try Ocp1Encoder().encode(v)
        let decoded = try Ocp1Decoder().decode(OcaInt32.self, from: encoded)
        XCTAssertEqual(v, decoded)
      case let v as OcaFloat32:
        let encoded: Data = try Ocp1Encoder().encode(v)
        let decoded = try Ocp1Decoder().decode(OcaFloat32.self, from: encoded)
        XCTAssertEqual(v, decoded)
      case let v as OcaFloat64:
        let encoded: Data = try Ocp1Encoder().encode(v)
        let decoded = try Ocp1Decoder().decode(OcaFloat64.self, from: encoded)
        XCTAssertEqual(v, decoded)
      case let v as String:
        let encoded: Data = try Ocp1Encoder().encode(v)
        let decoded = try Ocp1Decoder().decode(String.self, from: encoded)
        XCTAssertEqual(v, decoded)
      case let v as Bool:
        let encoded: Data = try Ocp1Encoder().encode(v)
        let decoded = try Ocp1Decoder().decode(Bool.self, from: encoded)
        XCTAssertEqual(v, decoded)
      default:
        XCTFail("Unhandled test value type")
      }
    }
  }
}

extension Ocp1EventData: Equatable {
  public static func == (_ lhs: Ocp1EventData, _ rhs: Ocp1EventData) -> Bool {
    lhs.event == rhs.event && lhs.eventParameters == rhs.eventParameters
  }
}

extension Ocp1NtfParams: Equatable {
  public static func == (_ lhs: Ocp1NtfParams, _ rhs: Ocp1NtfParams) -> Bool {
    lhs.parameterCount == rhs.parameterCount && lhs.context == rhs.context && lhs.eventData == rhs
      .eventData
  }
}

extension Ocp1Notification1: Equatable {
  public static func == (_ lhs: Ocp1Notification1, _ rhs: Ocp1Notification1) -> Bool {
    lhs.notificationSize == rhs.notificationSize && lhs.targetONo == rhs.targetONo && lhs
      .methodID == rhs.methodID && lhs.parameters == rhs.parameters
  }
}

extension Ocp1Notification2: Equatable {
  public static func == (_ lhs: Ocp1Notification2, _ rhs: Ocp1Notification2) -> Bool {
    lhs.notificationSize == rhs.notificationSize &&
      lhs.event == rhs.event &&
      lhs.notificationType == rhs.notificationType &&
      lhs.data == rhs.data
  }
}

final class SocketAddressHelperTests: XCTestCase {
  func testPresentationAddressNoPortIPv4() throws {
    let ipv4Address = try AnySocketAddress(
      family: sa_family_t(AF_INET),
      presentationAddress: "192.168.1.100:8080"
    )
    let addressNoPort = try ipv4Address.presentationAddressNoPort
    XCTAssertEqual(addressNoPort, "192.168.1.100")
  }

  func testPresentationAddressNoPortIPv4Loopback() throws {
    let loopbackAddress = try AnySocketAddress(
      family: sa_family_t(AF_INET),
      presentationAddress: "127.0.0.1:3000"
    )
    let addressNoPort = try loopbackAddress.presentationAddressNoPort
    XCTAssertEqual(addressNoPort, "127.0.0.1")
  }

  func testPresentationAddressNoPortIPv4ZeroAddress() throws {
    let zeroAddress = try AnySocketAddress(
      family: sa_family_t(AF_INET),
      presentationAddress: "0.0.0.0:80"
    )
    let addressNoPort = try zeroAddress.presentationAddressNoPort
    XCTAssertEqual(addressNoPort, "0.0.0.0")
  }

  func testPresentationAddressNoPortIPv6Standard() throws {
    let ipv6Address = try AnySocketAddress(
      family: sa_family_t(AF_INET6),
      presentationAddress: "[2001:db8::1]:8080"
    )
    let addressNoPort = try ipv6Address.presentationAddressNoPort
    XCTAssertEqual(addressNoPort, "2001:db8::1")
  }

  func testPresentationAddressNoPortIPv6Loopback() throws {
    let loopbackAddress = try AnySocketAddress(
      family: sa_family_t(AF_INET6),
      presentationAddress: "[::1]:3000"
    )
    let addressNoPort = try loopbackAddress.presentationAddressNoPort
    XCTAssertEqual(addressNoPort, "::1")
  }

  func testPresentationAddressNoPortIPv6FullAddress() throws {
    let ipv6Address = try AnySocketAddress(
      family: sa_family_t(AF_INET6),
      presentationAddress: "[2001:0db8:85a3:0000:0000:8a2e:0370:7334]:443"
    )
    let addressNoPort = try ipv6Address.presentationAddressNoPort
    XCTAssertEqual(addressNoPort, "2001:db8:85a3::8a2e:370:7334")
  }

  func testPresentationAddressNoPortIPv6ZeroAddress() throws {
    let zeroAddress = try AnySocketAddress(
      family: sa_family_t(AF_INET6),
      presentationAddress: "[::]:80"
    )
    let addressNoPort = try zeroAddress.presentationAddressNoPort
    XCTAssertEqual(addressNoPort, "::")
  }

  func testPresentationAddressNoPortIPv6WithoutPort() throws {
    let ipv6Address = try AnySocketAddress(
      family: sa_family_t(AF_INET6),
      presentationAddress: "[2001:db8::1]:0"
    )
    let addressNoPort = try ipv6Address.presentationAddressNoPort
    XCTAssertEqual(addressNoPort, "2001:db8::1")
  }

  func testPresentationAddressNoPortUnixDomainSocket() throws {
    let unixAddress = try AnySocketAddress(
      family: sa_family_t(AF_UNIX),
      presentationAddress: "/tmp/test.socket"
    )
    let addressNoPort = try unixAddress.presentationAddressNoPort
    XCTAssertEqual(addressNoPort, "/tmp/test.socket")
  }

  func testPresentationAddressNoPortUnixDomainSocketEmptyPath() throws {
    let unixAddress = try AnySocketAddress(family: sa_family_t(AF_UNIX), presentationAddress: "")
    let addressNoPort = try unixAddress.presentationAddressNoPort
    XCTAssertEqual(addressNoPort, "")
  }

  func testPresentationAddressNoPortUnixDomainSocketWithSpecialChars() throws {
    let unixAddress = try AnySocketAddress(
      family: sa_family_t(AF_UNIX),
      presentationAddress: "/tmp/socket with spaces & symbols!"
    )
    let addressNoPort = try unixAddress.presentationAddressNoPort
    XCTAssertEqual(addressNoPort, "/tmp/socket with spaces & symbols!")
  }
}

final class UnsafeStringInitializerTests: XCTestCase {
  // MARK: - OcaPropertyID unsafeString tests

  func testOcaPropertyIDUnsafeStringValid() throws {
    let propertyID = try OcaPropertyID(unsafeString: "3.5")
    XCTAssertEqual(propertyID.defLevel, 3)
    XCTAssertEqual(propertyID.propertyIndex, 5)
  }

  func testOcaPropertyIDUnsafeStringLargeValues() throws {
    let propertyID = try OcaPropertyID(unsafeString: "65535.65535")
    XCTAssertEqual(propertyID.defLevel, 65535)
    XCTAssertEqual(propertyID.propertyIndex, 65535)
  }

  func testOcaPropertyIDUnsafeStringMissingComponent() throws {
    XCTAssertThrowsError(try OcaPropertyID(unsafeString: "3")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaPropertyIDUnsafeStringTooManyComponents() throws {
    XCTAssertThrowsError(try OcaPropertyID(unsafeString: "3.5.7")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaPropertyIDUnsafeStringNonNumeric() throws {
    XCTAssertThrowsError(try OcaPropertyID(unsafeString: "abc.5")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }

    XCTAssertThrowsError(try OcaPropertyID(unsafeString: "3.xyz")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaPropertyIDUnsafeStringEmpty() throws {
    XCTAssertThrowsError(try OcaPropertyID(unsafeString: "")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaPropertyIDUnsafeStringNegativeValues() throws {
    XCTAssertThrowsError(try OcaPropertyID(unsafeString: "-1.5")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaPropertyIDUnsafeStringOverflow() throws {
    XCTAssertThrowsError(try OcaPropertyID(unsafeString: "65536.1")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  // MARK: - OcaMethodID unsafeString tests

  func testOcaMethodIDUnsafeStringValid() throws {
    let methodID = try OcaMethodID(unsafeString: "2.10")
    XCTAssertEqual(methodID.defLevel, 2)
    XCTAssertEqual(methodID.methodIndex, 10)
  }

  func testOcaMethodIDUnsafeStringLargeValues() throws {
    let methodID = try OcaMethodID(unsafeString: "65535.65535")
    XCTAssertEqual(methodID.defLevel, 65535)
    XCTAssertEqual(methodID.methodIndex, 65535)
  }

  func testOcaMethodIDUnsafeStringMissingComponent() throws {
    XCTAssertThrowsError(try OcaMethodID(unsafeString: "2")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaMethodIDUnsafeStringTooManyComponents() throws {
    XCTAssertThrowsError(try OcaMethodID(unsafeString: "2.10.3")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaMethodIDUnsafeStringNonNumeric() throws {
    XCTAssertThrowsError(try OcaMethodID(unsafeString: "xyz.10")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }

    XCTAssertThrowsError(try OcaMethodID(unsafeString: "2.abc")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaMethodIDUnsafeStringEmpty() throws {
    XCTAssertThrowsError(try OcaMethodID(unsafeString: "")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaMethodIDUnsafeStringNegativeValues() throws {
    XCTAssertThrowsError(try OcaMethodID(unsafeString: "-2.10")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaMethodIDUnsafeStringOverflow() throws {
    XCTAssertThrowsError(try OcaMethodID(unsafeString: "65536.10")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  // MARK: - OcaEventID unsafeString tests

  func testOcaEventIDUnsafeStringValid() throws {
    let eventID = try OcaEventID(unsafeString: "2.7")
    XCTAssertEqual(eventID.defLevel, 2)
    XCTAssertEqual(eventID.eventIndex, 7)
  }

  func testOcaEventIDUnsafeStringLargeValues() throws {
    let eventID = try OcaEventID(unsafeString: "65535.65535")
    XCTAssertEqual(eventID.defLevel, 65535)
    XCTAssertEqual(eventID.eventIndex, 65535)
  }

  func testOcaEventIDUnsafeStringMissingComponent() throws {
    XCTAssertThrowsError(try OcaEventID(unsafeString: "2")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaEventIDUnsafeStringTooManyComponents() throws {
    XCTAssertThrowsError(try OcaEventID(unsafeString: "2.7.3")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaEventIDUnsafeStringNonNumeric() throws {
    XCTAssertThrowsError(try OcaEventID(unsafeString: "xyz.7")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }

    XCTAssertThrowsError(try OcaEventID(unsafeString: "2.abc")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaEventIDUnsafeStringEmpty() throws {
    XCTAssertThrowsError(try OcaEventID(unsafeString: "")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaEventIDUnsafeStringNegativeValues() throws {
    XCTAssertThrowsError(try OcaEventID(unsafeString: "-2.7")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  func testOcaEventIDUnsafeStringOverflow() throws {
    XCTAssertThrowsError(try OcaEventID(unsafeString: "65536.7")) { error in
      XCTAssertEqual(error as? Ocp1Error, .status(.parameterError))
    }
  }

  // MARK: - OcaClassID unsafeString tests

  func testOcaClassIDUnsafeStringValid() throws {
    let classID = try OcaClassID(unsafeString: "1.2.3")
    XCTAssertEqual(classID.fields, [1, 2, 3])
  }

  func testOcaClassIDUnsafeStringMinimumValid() throws {
    let classID = try OcaClassID(unsafeString: "1.2")
    XCTAssertEqual(classID.fields, [1, 2])
  }

  func testOcaClassIDUnsafeStringLongChain() throws {
    let classID = try OcaClassID(unsafeString: "1.2.3.4.5.6")
    XCTAssertEqual(classID.fields, [1, 2, 3, 4, 5, 6])
  }

  func testOcaClassIDUnsafeStringLargeValues() throws {
    let classID = try OcaClassID(unsafeString: "1.65535")
    XCTAssertEqual(classID.fields, [1, 65535])
  }

  func testOcaClassIDUnsafeStringSingleComponent() throws {
    XCTAssertThrowsError(try OcaClassID(unsafeString: "1")) { error in
      XCTAssertEqual(error as? Ocp1Error, .objectClassMismatch)
    }
  }

  func testOcaClassIDUnsafeStringEmpty() throws {
    XCTAssertThrowsError(try OcaClassID(unsafeString: "")) { error in
      XCTAssertEqual(error as? Ocp1Error, .objectClassMismatch)
    }
  }

  func testOcaClassIDUnsafeStringNonNumeric() throws {
    XCTAssertThrowsError(try OcaClassID(unsafeString: "1.abc.3")) { error in
      XCTAssertEqual(error as? Ocp1Error, .objectClassMismatch)
    }

    XCTAssertThrowsError(try OcaClassID(unsafeString: "xyz.2.3")) { error in
      XCTAssertEqual(error as? Ocp1Error, .objectClassMismatch)
    }
  }

  func testOcaClassIDUnsafeStringNegativeValues() throws {
    XCTAssertThrowsError(try OcaClassID(unsafeString: "1.-2.3")) { error in
      XCTAssertEqual(error as? Ocp1Error, .objectClassMismatch)
    }
  }

  func testOcaClassIDUnsafeStringOverflow() throws {
    XCTAssertThrowsError(try OcaClassID(unsafeString: "1.65536")) { error in
      XCTAssertEqual(error as? Ocp1Error, .objectClassMismatch)
    }
  }

  func testOcaClassIDUnsafeStringWithSpaces() throws {
    XCTAssertThrowsError(try OcaClassID(unsafeString: "1. 2.3")) { error in
      XCTAssertEqual(error as? Ocp1Error, .objectClassMismatch)
    }
  }
}
