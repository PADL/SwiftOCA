//
// Copyright (c) 2026 PADL Software Pty Ltd
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

#if NonEmbeddedBuild
import Foundation
@testable import SwiftOCA
import XCTest

/// AES70-4 clause 6 framing, exercised with the standard's own example PDUs.
final class Ocp2MessageTests: XCTestCase {
  // MARK: AES70-4 Annex B examples

  static let exampleA01 = """
  {
    "ProtocolVersion" : 1,
    "Commands" : [
      {
        "Handle" : 47,
        "TargetONo" : 5000,
        "MethodID" : [ 3, 17, "FindActionObjectsByRole" ],
        "Parameters" : {
          "SearchName" : "Master Gain",
          "NameComparisonType" : "Exact",
          "SearchClassID" : [ 1, 1, 1, 5 ],
          "ResultFlags" : 1
        }
      }
    ]
  }

  """

  static let exampleA02 = """
  {
    "ProtocolVersion" : 1,
    "Responses" : [
      {
        "Handle" : 47,
        "StatusCode" : "OK",
        "Parameters" : {
          "Result" : [
            {
              "ONo" : "5000",
              "ClassIdentification" : [ 1, 1, 1, 5 ]
            }
          ]
        }
      }
    ]
  }

  """

  static let exampleA04 = """
  {
    "ProtocolVersion" : 1,
    "Responses" : [
      {
        "Handle" : 48,
        "StatusCode" : "OK"
      }
    ]
  }

  """

  static let exampleA05 = """
  {
    "ProtocolVersion" : 1,
    "Commands" : [
      {
        "Handle" : 49,
        "TargetONo" : 5000,
        "MethodID" : [ 4, 2, "SetGain" ],
        "Parameters" : {
          "Gain" : -3.5
        }
      }
    ]
  }

  """

  static let exampleA07 = """
  {
    "ProtocolVersion" : 1,
    "Notifications" : [
      {
        "Event" : {
          "EventIdentification" : {
            "EmitterONo" : 5000,
            "EventID" : [ 1, 1, "PropertyChanged" ]
          },
          "EventData" : {
            "PropertyID" : [ 4, 1, "Gain" ],
            "PropertyValue" : -3.5,
            "ChangeType" : "CurrentChanged"
          }
        }
      }
    ]
  }

  """

  static let exampleB = """
  {
    "ProtocolVersion" : 1,
    "KeepAlive" : {
      "HeartbeatTimeout" : 6000
    }
  }

  """

  static let exampleC = """
  {
    "ProtocolVersion" : 1,
    "DeviceReset" : {
      "ResetKey" : "ZGVhZmRhZGFjYWZlYmFiZQ=="
    }
  }

  """

  static let exampleD = """
  {
    "ProtocolVersion" : 1,
    "Notifications" : [
      {
        "Exception" : {
          "EventIdentification" : {
            "EmitterONo" : 5000,
            "EventID" : [ 1, 1, "PropertyChanged" ]
          },
          "ExceptionType" : "CancelledByDevice",
          "TryAgain" : false
        }
      }
    ]
  }

  """

  static let exampleE = """
  {
    "ProtocolVersion" : 1,
    "Commands" : [
      {
        "Handle" : 47,
        "TargetONo" : 5000,
        "MethodID" : [ 3, 17, "FindActionObjectsByRole" ],
        "Parameters" : {
          "SearchName" : "Master Gain",
          "NameComparisonType" : "Exact",
          "SearchClassID" : [ 1, 1, 1, 5 ],
          "ResultFlags" : 1
        }
      },
      {
        "Handle" : 49,
        "TargetONo" : 5000,
        "MethodID" : [ 4, 2, "SetGain" ],
        "Parameters" : {
          "Gain" : -3.5
        }
      }
    ]
  }

  """

  static let exampleG = """
  {
    "ProtocolVersion" : 1,
    "Notifications" : [
      {
        "Event" : {
          "EventIdentification" : {
            "EmitterONo" : 5000,
            "EventID" : [ 1, 1, "PropertyChanged" ]
          },
          "EventData" : {
            "PropertyID" : [ 4, 1, "Gain" ],
            "PropertyValue" : -3.5,
            "ChangeType" : "CurrentChanged"
          }
        }
      },
      {
        "Exception" : {
          "EventIdentification" : {
            "EmitterONo" : 5000,
            "EventID" : [ 1, 1, "PropertyChanged" ]
          },
          "ExceptionType" : "CancelledByDevice",
          "TryAgain" : false
        }
      }
    ]
  }

  """

  /// invalid message array name
  static let exampleX01 = """
  {
    "ProtocolVersion" : 1,
    "xCommands" : [
      {
        "Handle" : 47,
        "TargetONo" : 5000,
        "MethodID" : [ 3, 17, "FindActionObjectsByRole" ],
        "Parameters" : { "SearchName" : "Master Gain" }
      }
    ]
  }

  """

  /// missing TargetONo
  static let exampleX02 = """
  {
    "ProtocolVersion" : 1,
    "Commands" : [
      {
        "Handle" : 47,
        "MethodID" : [ 3, 17, "FindActionObjectsByRole" ],
        "Parameters" : { "SearchName" : "Master Gain" }
      }
    ]
  }

  """

  /// spurious property in a command
  static let exampleX03 = """
  {
    "ProtocolVersion" : 1,
    "Commands" : [
      {
        "Handle" : 47,
        "TargetONo" : 5000,
        "MethodID" : [ 3, 17, "FindActionObjectsByRole" ],
        "Parameters" : { "SearchName" : "Master Gain" },
        "badProperty" : "abc"
      }
    ]
  }

  """

  private func decode(_ text: String) throws -> (OcaMessageType, [Ocp1Message]) {
    try OcaControlProtocol.ocp2.decodePdu(Data(text.utf8))
  }

  func testDecodeCommand() throws {
    let (type, messages) = try decode(Self.exampleA01)
    XCTAssertEqual(type, .ocaCmdRrq)
    let command = try XCTUnwrap(messages.first as? Ocp1Command)
    XCTAssertEqual(command.handle, 47)
    XCTAssertEqual(command.targetONo, 5000)
    XCTAssertEqual(command.methodID, OcaMethodID("3.17"))
    XCTAssertEqual(command.parameters.format, .ocp2)
    let params = try Ocp2Decoder().decodeParameters(
      OcaBlock.FindActionObjectsByRoleParameters.self,
      from: command.parameters.parameterData
    )
    XCTAssertEqual(params.searchName, "Master Gain")
    XCTAssertEqual(params.resultFlags, .oNo)
  }

  func testDecodeSetGain() throws {
    let (_, messages) = try decode(Self.exampleA05)
    let command = try XCTUnwrap(messages.first as? Ocp1Command)
    XCTAssertEqual(command.methodID, OcaMethodID("4.2"))
    let gain: Float = try Ocp2Decoder().decodeParameters(
      Float.self,
      from: command.parameters.parameterData,
      parameterNames: ["Gain"]
    )
    XCTAssertEqual(gain, -3.5)
  }

  func testDecodeResponses() throws {
    let (type, messages) = try decode(Self.exampleA02)
    XCTAssertEqual(type, .ocaRsp)
    let response = try XCTUnwrap(messages.first as? Ocp1Response)
    XCTAssertEqual(response.handle, 47)
    XCTAssertEqual(response.statusCode, .ok)
    XCTAssertFalse(response.parameters.isEmpty)

    let (_, bare) = try decode(Self.exampleA04)
    let bareResponse = try XCTUnwrap(bare.first as? Ocp1Response)
    XCTAssertEqual(bareResponse.handle, 48)
    XCTAssertTrue(bareResponse.parameters.isEmpty)

    let numeric =
      try decode("{\"ProtocolVersion\":1,\"Responses\":[{\"Handle\":1,\"StatusCode\":3}]}\n")
    XCTAssertEqual((numeric.1.first as? Ocp1Response)?.statusCode, .locked)
  }

  func testDecodeEventNotification() throws {
    let (type, messages) = try decode(Self.exampleA07)
    XCTAssertEqual(type, .ocaNtf2)
    let notification = try XCTUnwrap(messages.first as? Ocp1Notification2)
    XCTAssertEqual(
      notification.event,
      OcaEvent(emitterONo: 5000, eventID: OcaPropertyChangedEventID)
    )
    XCTAssertEqual(notification.notificationType, .event)
    XCTAssertEqual(notification.dataFormat, .ocp2)
    XCTAssertNoThrow(try notification.throwIfException())
    let eventData = try Ocp2Decoder().decodeValue(
      OcaPropertyChangedEventData<Float>.self,
      from: Ocp2JSON.parse(notification.data)
    )
    XCTAssertEqual(eventData.propertyValue, -3.5)
    XCTAssertEqual(eventData.changeType, .currentChanged)
  }

  func testDecodeExceptionNotification() throws {
    let (_, messages) = try decode(Self.exampleD)
    let notification = try XCTUnwrap(messages.first as? Ocp1Notification2)
    XCTAssertEqual(notification.notificationType, .exception)
    XCTAssertThrowsError(try notification.throwIfException()) { error in
      guard case let Ocp1Error.exception(exception) = error else {
        return XCTFail("unexpected error \(error)")
      }
      XCTAssertEqual(exception.exceptionType, .cancelledByDevice)
      XCTAssertFalse(exception.tryAgain)
    }
  }

  func testDecodeMultipleMessages() throws {
    XCTAssertEqual(try decode(Self.exampleE).1.count, 2)
    let notifications = try decode(Self.exampleG).1
    XCTAssertEqual(notifications.count, 2)
    XCTAssertEqual((notifications[0] as? Ocp1Notification2)?.notificationType, .event)
    XCTAssertEqual((notifications[1] as? Ocp1Notification2)?.notificationType, .exception)
  }

  func testDecodeKeepAliveAndDeviceReset() throws {
    let (type, messages) = try decode(Self.exampleB)
    XCTAssertEqual(type, .ocaKeepAlive)
    XCTAssertEqual((messages.first as? Ocp1KeepAlive2)?.heartBeatTime, 6000)

    let (_, reset) = try decode(Self.exampleC)
    XCTAssertEqual((reset.first as? Ocp2DeviceReset)?.resetKey, Data("deafdadacafebabe".utf8))
  }

  func testMalformedExamplesAreRejected() {
    XCTAssertThrowsError(try decode(Self.exampleX01))
    XCTAssertThrowsError(try decode(Self.exampleX02))
    XCTAssertThrowsError(try decode(Self.exampleX03))
    XCTAssertThrowsError(
      try decode("{\"ProtocolVersion\":2,\"KeepAlive\":{\"HeartbeatTimeout\":1}}\n")
    )
    XCTAssertThrowsError(try decode("{\"KeepAlive\":{\"HeartbeatTimeout\":1}}\n"))
    XCTAssertThrowsError(
      try decode(
        "{\"ProtocolVersion\":1,\"KeepAlive\":{\"HeartbeatTimeout\":1},\"Responses\":[]}\n"
      )
    )
    XCTAssertThrowsError(
      try decode(
        "{\"ProtocolVersion\":1,\"Commands\":[{\"Handle\":1.5,\"TargetONo\":1,\"MethodID\":[1,1]}]}\n"
      )
    )
    XCTAssertThrowsError(try decode("[1,2]\n"))
    XCTAssertThrowsError(try decode("not json\n"))
  }

  // MARK: encoding

  private func roundTrip(_ messages: [Ocp1Message], type: OcaMessageType) throws -> [Ocp1Message] {
    let pdu = try OcaControlProtocol.ocp2.encodePdu(messages, type: type)
    XCTAssertEqual(pdu.last, UInt8(ascii: "\n"))
    XCTAssertEqual(pdu.first, UInt8(ascii: "{"))
    let (decodedType, decoded) = try OcaControlProtocol.ocp2.decodePdu(pdu)
    XCTAssertEqual(decodedType, type)
    return decoded
  }

  func testEncodeCommandMatchesExampleA05() throws {
    let command = try Ocp1Command(
      handle: 49,
      targetONo: 5000,
      methodID: OcaMethodID("4.2"),
      parameters: Ocp1Parameters(
        ocp2ParameterData: Ocp2Encoder().encodeParametersData(Float(-3.5), parameterNames: ["Gain"])
      )
    )
    let pdu = try OcaControlProtocol.ocp2.encodePdu([command], type: .ocaCmdRrq)
    let expected = try XCTUnwrap(try JSONSerialization
      .jsonObject(with: Data(Self.exampleA05.utf8)) as? NSDictionary)
    let actual = try XCTUnwrap(try JSONSerialization.jsonObject(with: pdu) as? NSDictionary)
    // the example carries the optional method name; we don't
    let commands = try XCTUnwrap(actual["Commands"] as? [[String: Any]])
    XCTAssertEqual(commands[0]["Handle"] as? Int, 49)
    XCTAssertEqual(commands[0]["MethodID"] as? [Int], [4, 2])
    XCTAssertEqual(commands[0]["Parameters"] as? [String: Double], ["Gain": -3.5])
    XCTAssertEqual(actual["ProtocolVersion"] as? Int, expected["ProtocolVersion"] as? Int)

    let decoded = try XCTUnwrap(try roundTrip([command], type: .ocaCmdRrq).first as? Ocp1Command)
    XCTAssertEqual(decoded.handle, 49)
    XCTAssertEqual(decoded.methodID, OcaMethodID("4.2"))
  }

  func testEncodeCommandWithoutParameters() throws {
    let command = Ocp1Command(handle: 1, targetONo: 1, methodID: OcaMethodID("1.1"))
    let pdu = try OcaControlProtocol.ocp2.encodePdu([command], type: .ocaCmd)
    XCTAssertFalse(String(decoding: pdu, as: UTF8.self).contains("Parameters"))
    XCTAssertTrue(String(decoding: pdu, as: UTF8.self).contains("CommandNRs"))
    XCTAssertEqual(try roundTrip([command], type: .ocaCmd).count, 1)
  }

  func testOcp1ParametersCannotBeFramedAsOcp2() {
    let command = Ocp1Command(
      handle: 1,
      targetONo: 1,
      methodID: OcaMethodID("4.2"),
      parameters: Ocp1Parameters(parameterCount: 1, parameterData: Data([0, 0, 0, 0]))
    )
    XCTAssertThrowsError(try OcaControlProtocol.ocp2.encodePdu([command], type: .ocaCmdRrq))
  }

  func testEncodeResponse() throws {
    let response = Ocp1Response(handle: 7, statusCode: .locked)
    let text = try String(
      decoding: OcaControlProtocol.ocp2.encodePdu([response], type: .ocaRsp),
      as: UTF8.self
    )
    XCTAssertTrue(text.contains("\"StatusCode\":\"Locked\""), text)
    let decoded = try XCTUnwrap(try roundTrip([response], type: .ocaRsp).first as? Ocp1Response)
    XCTAssertEqual(decoded.statusCode, .locked)
    XCTAssertEqual(decoded.handle, 7)
  }

  func testEncodeNotifications() throws {
    let event = OcaEvent(emitterONo: 5000, eventID: OcaPropertyChangedEventID)
    let eventData = OcaPropertyChangedEventData<Float>(
      propertyID: "4.1",
      propertyValue: -3.5,
      changeType: .currentChanged
    )
    let notification = try Ocp1Notification2(
      event: event,
      notificationType: .event,
      data: Ocp2JSON.serialize(Ocp2Encoder().encodeValue(eventData)),
      dataFormat: .ocp2
    )
    let exception = try Ocp1Notification2(
      event: event,
      notificationType: .exception,
      data: Ocp1Encoder().encode(Ocp1Notification2ExceptionData(
        exceptionType: .objectDeleted,
        tryAgain: true,
        exceptionData: OcaBlob()
      ))
    )
    let decoded = try roundTrip([notification, exception], type: .ocaNtf2)
    XCTAssertEqual(decoded.count, 2)
    let decodedEvent = try XCTUnwrap(decoded[0] as? Ocp1Notification2)
    XCTAssertEqual(decodedEvent.event, event)
    let decodedData = try Ocp2Decoder().decodeValue(
      OcaPropertyChangedEventData<Float>.self,
      from: Ocp2JSON.parse(decodedEvent.data)
    )
    XCTAssertEqual(decodedData.propertyID, eventData.propertyID)
    XCTAssertEqual(decodedData.propertyValue, eventData.propertyValue)
    XCTAssertEqual(decodedData.changeType, eventData.changeType)
    XCTAssertThrowsError(try (decoded[1] as? Ocp1Notification2)?.throwIfException()) { error in
      guard case let Ocp1Error.exception(exception) = error else {
        return XCTFail("unexpected error \(error)")
      }
      XCTAssertEqual(exception.exceptionType, .objectDeleted)
      XCTAssertTrue(exception.tryAgain)
    }
  }

  func testEncodeKeepAliveConvertsSecondsToMilliseconds() throws {
    let seconds = try roundTrip([Ocp1KeepAlive1(heartBeatTime: 2)], type: .ocaKeepAlive)
    XCTAssertEqual((seconds.first as? Ocp1KeepAlive2)?.heartBeatTime, 2000)
    let milliseconds = try roundTrip([Ocp1KeepAlive2(heartBeatTime: 250)], type: .ocaKeepAlive)
    XCTAssertEqual((milliseconds.first as? Ocp1KeepAlive2)?.heartBeatTime, 250)
    XCTAssertThrowsError(try OcaControlProtocol.ocp2.encodePdu(
      [Ocp1KeepAlive1(heartBeatTime: 1), Ocp1KeepAlive1(heartBeatTime: 1)],
      type: .ocaKeepAlive
    ))
  }

  func testEncodeDeviceReset() throws {
    let reset = Ocp2DeviceReset(resetKey: Data("deafdadacafebabe".utf8))
    let text = try String(
      decoding: OcaControlProtocol.ocp2.encodePdu([reset], type: .ocaCmd),
      as: UTF8.self
    )
    XCTAssertEqual(
      text,
      "{\"ProtocolVersion\":1,\"DeviceReset\":{\"ResetKey\":\"ZGVhZmRhZGFjYWZlYmFiZQ==\"}}\n"
    )
  }

  func testEv1NotificationsCannotBeFramed() {
    let notification = Ocp1Notification1(
      targetONo: 1,
      methodID: OcaMethodID("1.1"),
      parameters: Ocp1NtfParams(
        parameterCount: 2,
        context: OcaBlob(),
        eventData: Ocp1EventData(
          event: OcaEvent(emitterONo: 1, eventID: OcaEventID("1.1")),
          eventParameters: Data()
        )
      )
    )
    XCTAssertThrowsError(try OcaControlProtocol.ocp2.encodePdu([notification], type: .ocaNtf1))
  }

  func testBatchingAssemblesOneArray() throws {
    let format = OcaControlProtocol.ocp2
    let commands = (1...3).map { Ocp1Command(
      handle: OcaUint32($0),
      targetONo: 1,
      methodID: OcaMethodID("1.1")
    ) }
    let encoded = try commands.map { try format.encodeMessage($0, type: .ocaCmdRrq) }
    let pdu = try format.assemblePdu(type: .ocaCmdRrq, encodedMessages: encoded)
    XCTAssertGreaterThanOrEqual(
      format.pduOverhead(messageCount: 3) + encoded.reduce(0) { $0 + $1.count },
      pdu.count
    )
    let (type, decoded) = try format.decodePdu(Data(pdu))
    XCTAssertEqual(type, .ocaCmdRrq)
    XCTAssertEqual(decoded.compactMap { ($0 as? Ocp1Command)?.handle }, [1, 2, 3])
  }

  // MARK: reader

  private final class Feed {
    var chunks: [Data]
    init(_ chunks: [Data]) {
      self.chunks = chunks
    }

    func read(_ count: Int, awaitingAllRead: Bool) async throws -> Data {
      guard !awaitingAllRead else {
        XCTFail("OCP.2 must not use exact-length reads")
        return Data()
      }
      guard !chunks.isEmpty else { return Data() }
      var chunk = chunks.removeFirst()
      if chunk.count > count {
        chunks.insert(chunk.dropFirst(count), at: 0)
        chunk = chunk.prefix(count)
      }
      return chunk
    }
  }

  private func readAll(
    _ chunks: [String],
    isMessageOriented: Bool = false,
    maximumPduSize: Int = 1024
  ) async throws -> [String] {
    let reader = OcaControlProtocol.ocp2.makeReader(
      isMessageOriented: isMessageOriented,
      maximumPduSize: maximumPduSize
    )
    let feed = Feed(chunks.map { Data($0.utf8) })
    var pdus = [String]()
    while true {
      do {
        let pdu = try await reader.nextPdu(read: feed.read)
        pdus.append(String(decoding: pdu, as: UTF8.self))
      } catch Ocp1Error.notConnected {
        return pdus
      }
    }
  }

  func testReaderSplitsAndJoinsLines() async throws {
    let whole = try await readAll(["{\"a\":1}\n{\"b\":2}\n"])
    XCTAssertEqual(whole, ["{\"a\":1}", "{\"b\":2}"])
    let split = try await readAll(["{\"a\"", ":1}\n{\"b", "\":2}\n"])
    XCTAssertEqual(split, ["{\"a\":1}", "{\"b\":2}"])
    let crlf = try await readAll(["{\"a\":1}\r\n\n{\"b\":2}\n"])
    XCTAssertEqual(crlf, ["{\"a\":1}", "{\"b\":2}"])
    // an unterminated trailing line is not a PDU
    let unterminated = try await readAll(["{\"a\":1}\n{\"b\""])
    XCTAssertEqual(unterminated, ["{\"a\":1}"])
  }

  func testReaderEnforcesMaximumPduSize() async {
    do {
      _ = try await readAll([String(repeating: "x", count: 2048)], maximumPduSize: 1024)
      XCTFail("expected an error")
    } catch {
      XCTAssertEqual(error as? Ocp1Error, .invalidPduSize)
    }
  }

  func testReaderAcceptsAPduOfExactlyMaximumSize() async throws {
    // the cap excludes the terminator, however it is delivered
    let exact = String(repeating: "x", count: 1024)
    for chunks in [[exact + "\n"], [exact + "\r\n"], [exact, "\n"], [exact, "\r", "\n"]] {
      let pdus = try await readAll(chunks, maximumPduSize: 1024)
      XCTAssertEqual(pdus, [exact], "\(chunks.map(\.count))")
    }
    do {
      _ = try await readAll([exact + "x\n"], maximumPduSize: 1024)
      XCTFail("expected an error")
    } catch {
      XCTAssertEqual(error as? Ocp1Error, .invalidPduSize)
    }
  }

  func testReaderEnforcesMaximumPduSizeWithinOneRead() async {
    // a transport may deliver a whole frame at once: the cap still applies
    let big = String(repeating: "x", count: 2048) + "\n"
    for messageOriented in [false, true] {
      do {
        _ = try await readAll([big], isMessageOriented: messageOriented, maximumPduSize: 1024)
        XCTFail("expected an error (messageOriented: \(messageOriented))")
      } catch {
        XCTAssertEqual(error as? Ocp1Error, .invalidPduSize)
      }
    }
    // several small PDUs in one large read are fine
    let many = String(repeating: "{\"a\":1}\n", count: 500)
    let pdus = try? await readAll([many], maximumPduSize: 1024)
    XCTAssertEqual(pdus?.count, 500)
  }

  func testReaderMessageOrientedMode() async throws {
    let pdus = try await readAll(
      ["{\"a\":1}\n", "{\"b\":2}\r\n", "{\"c\":3}"],
      isMessageOriented: true
    )
    XCTAssertEqual(pdus, ["{\"a\":1}", "{\"b\":2}", "{\"c\":3}"])
  }
}
#endif
