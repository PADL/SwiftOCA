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

/// AES70-4 clause 6.3: the OCP.2 PDU is a JSON object with `ProtocolVersion` and
/// exactly one payload member. Messages are the same model types OCP.1 uses.
///
/// Encoding assembles text directly so a message's already-serialised `Parameters`
/// object can be spliced in unchanged; decoding goes through `JSONSerialization` and
/// re-serialises each `Parameters` object for the message model.
package enum Ocp2Message {
  package static let protocolVersion = 1

  enum Key {
    static let protocolVersion = "ProtocolVersion"
    static let commands = "Commands"
    static let commandNRs = "CommandNRs"
    static let responses = "Responses"
    static let notifications = "Notifications"
    static let keepAlive = "KeepAlive"
    static let deviceReset = "DeviceReset"

    static let handle = "Handle"
    static let targetONo = "TargetONo"
    static let methodID = "MethodID"
    static let parameters = "Parameters"
    static let statusCode = "StatusCode"

    static let event = "Event"
    static let exception = "Exception"
    static let eventIdentification = "EventIdentification"
    static let emitterONo = "EmitterONo"
    static let eventID = "EventID"
    static let eventData = "EventData"
    static let exceptionType = "ExceptionType"
    static let tryAgain = "TryAgain"
    static let exceptionData = "ExceptionData"

    static let heartbeatTimeout = "HeartbeatTimeout"
    static let resetKey = "ResetKey"

    static let payloads: Set<String> = [
      commands, commandNRs, responses, notifications, keepAlive, deviceReset,
    ]
  }

  /// `Ocp2ExceptionType` spelled as in the AES70-4 JSON schema.
  static let exceptionTypeNames: [Ocp1Notification2ExceptionType: String] = [
    .unspecified: "Unspecified",
    .cancelledByDevice: "CancelledByDevice",
    .objectDeleted: "ObjectDeleted",
    .deviceError: "DeviceError",
  ]

  // MARK: - encoding

  static func payloadKey(for messageType: OcaMessageType) throws -> String {
    switch messageType {
    case .ocaCmd: Key.commandNRs
    case .ocaCmdRrq: Key.commands
    case .ocaRsp: Key.responses
    case .ocaNtf2: Key.notifications
    case .ocaKeepAlive: Key.keepAlive
    case .ocaNtf1: throw Ocp1Error.invalidMessageType // EV1 is not part of OCP.2
    }
  }

  /// One message as serialised JSON (no trailing newline).
  package static func encodeMessage(
    _ message: Ocp1Message,
    type messageType: OcaMessageType
  ) throws -> [UInt8] {
    try Array(Ocp2JSON.serialize(messageObject(message, type: messageType)))
  }

  /// The message's JSON object.
  static func messageObject(
    _ message: Ocp1Message,
    type messageType: OcaMessageType
  ) throws -> [String: Any] {
    switch message {
    case let command as Ocp1Command:
      guard messageType == .ocaCmd || messageType == .ocaCmdRrq else {
        throw Ocp1Error.invalidMessageType
      }
      var object: [String: Any] = [
        Key.handle: command.handle,
        Key.targetONo: command.targetONo,
        Key.methodID: _ocp2ElementID(command.methodID.defLevel, command.methodID.methodIndex),
      ]
      if let parameters = try parametersObject(command.parameters) {
        object[Key.parameters] = parameters
      }
      return object
    case let response as Ocp1Response:
      guard messageType == .ocaRsp else { throw Ocp1Error.invalidMessageType }
      var object: [String: Any] = [
        Key.handle: response.handle,
        Key.statusCode: response.statusCode.ocp2Name,
      ]
      if let parameters = try parametersObject(response.parameters) {
        object[Key.parameters] = parameters
      }
      return object
    case let notification as Ocp1Notification2:
      guard messageType == .ocaNtf2 else { throw Ocp1Error.invalidMessageType }
      return try notificationObject(notification)
    case let keepAlive as Ocp1KeepAlive1:
      guard messageType == .ocaKeepAlive else { throw Ocp1Error.invalidMessageType }
      return [Key.heartbeatTimeout: UInt32(keepAlive.heartBeatTime) * 1000]
    case let keepAlive as Ocp1KeepAlive2:
      guard messageType == .ocaKeepAlive else { throw Ocp1Error.invalidMessageType }
      return [Key.heartbeatTimeout: keepAlive.heartBeatTime]
    case let reset as Ocp2DeviceReset:
      return [Key.resetKey: Ocp2JSON.base64(reset.resetKey)]
    default:
      throw Ocp1Error.invalidMessageType
    }
  }

  /// The `Parameters` object, or `nil` when there are none. OCP.1-encoded parameters
  /// cannot be represented and are an error rather than a silent blob.
  private static func parametersObject(_ parameters: Ocp1Parameters) throws -> [String: Any]? {
    switch parameters.format {
    case .ocp2:
      guard !parameters.parameterData.isEmpty else { return nil }
      return try Ocp2JSON.parseObject(parameters.parameterData)
    case .ocp1:
      guard parameters.isEmpty else { throw Ocp1Error.invalidMessageType }
      return nil
    }
  }

  private static func eventIdentificationObject(_ event: OcaEvent) -> [String: Any] {
    [
      Key.emitterONo: event.emitterONo,
      Key.eventID: _ocp2ElementID(event.eventID.defLevel, event.eventID.eventIndex),
    ]
  }

  private static func notificationObject(_ notification: Ocp1Notification2) throws
    -> [String: Any]
  {
    switch notification.notificationType {
    case .event:
      var event: [String: Any] = [
        Key.eventIdentification: eventIdentificationObject(notification.event),
      ]
      if !notification.data.isEmpty {
        guard notification.dataFormat == .ocp2 else { throw Ocp1Error.invalidMessageType }
        event[Key.eventData] = try Ocp2JSON.parse(notification.data)
      }
      return [Key.event: event]
    case .exception:
      let exception = try Ocp1Decoder().decode(
        Ocp1Notification2ExceptionData.self,
        from: notification.data
      )
      var object: [String: Any] = [
        Key.eventIdentification: eventIdentificationObject(notification.event),
        Key.exceptionType: exceptionTypeNames[exception.exceptionType]
          ?? Int(exception.exceptionType.rawValue),
        Key.tryAgain: exception.tryAgain,
      ]
      if !exception.exceptionData.isEmpty {
        object[Key.exceptionData] = Ocp2JSON.base64(exception.exceptionData.wrappedValue)
      }
      return [Key.exception: object]
    }
  }

  /// One PDU from pre-serialised messages, newline-terminated. The messages are
  /// spliced as bytes so a batch need not re-parse what it already serialised; the
  /// envelope has no string content of its own.
  package static func assemblePdu(
    type messageType: OcaMessageType,
    encodedMessages: [[UInt8]],
    deviceReset: Bool = false
  ) throws -> [UInt8] {
    let key = deviceReset ? Key.deviceReset : try payloadKey(for: messageType)
    var pdu = Array("{\"\(Key.protocolVersion)\":\(protocolVersion),\"\(key)\":".utf8)
    if messageType == .ocaKeepAlive || deviceReset {
      guard encodedMessages.count == 1 else { throw Ocp1Error.invalidMessageType }
      pdu += encodedMessages[0]
    } else {
      pdu.append(UInt8(ascii: "["))
      for (index, message) in encodedMessages.enumerated() {
        if index > 0 {
          pdu.append(UInt8(ascii: ","))
        }
        pdu += message
      }
      pdu.append(UInt8(ascii: "]"))
    }
    pdu += Array("}\n".utf8)
    return pdu
  }

  package static func encodePdu(
    _ messages: [Ocp1Message],
    type messageType: OcaMessageType
  ) throws -> Data {
    let deviceReset = messages.count == 1 && messages[0] is Ocp2DeviceReset
    let encoded = try messages.map { try encodeMessage($0, type: messageType) }
    return try Data(assemblePdu(
      type: messageType,
      encodedMessages: encoded,
      deviceReset: deviceReset
    ))
  }

  /// Envelope bytes beyond the messages: `{"ProtocolVersion":1,"<key>":[` … `]}\n`
  /// plus a comma between messages. Sized for the longest payload key.
  package static func pduOverhead(messageCount: Int) -> Int {
    30 + Key.notifications.count + max(messageCount - 1, 0)
  }

  // MARK: - decoding

  package static func decodePdu(_ data: Data) throws -> (OcaMessageType, [Ocp1Message]) {
    let object = try Ocp2JSON.parseObject(data)

    guard let version = object[Key.protocolVersion] else {
      throw Ocp1Error.status(.badFormat)
    }
    guard try Ocp2JSON.integer(Int.self, from: version) == protocolVersion else {
      throw Ocp1Error.invalidProtocolVersion
    }

    let payloadKeys = object.keys.filter { $0 != Key.protocolVersion }
    guard payloadKeys.count == 1, let payloadKey = payloadKeys.first,
          Key.payloads.contains(payloadKey), let payload = object[payloadKey]
    else {
      throw Ocp1Error.invalidMessageType
    }

    switch payloadKey {
    case Key.commands, Key.commandNRs:
      let type: OcaMessageType = payloadKey == Key.commands ? .ocaCmdRrq : .ocaCmd
      return try (type, array(payload).map { try decodeCommand($0) })
    case Key.responses:
      return try (.ocaRsp, array(payload).map { try decodeResponse($0) })
    case Key.notifications:
      return try (.ocaNtf2, array(payload).map { try decodeNotification($0) })
    case Key.keepAlive:
      let object = try expectObject(
        payload,
        keys: [Key.heartbeatTimeout],
        required: [Key.heartbeatTimeout]
      )
      let timeout = try Ocp2JSON.integer(OcaUint32.self, from: object[Key.heartbeatTimeout]!)
      return (.ocaKeepAlive, [Ocp1KeepAlive2(heartBeatTime: timeout)])
    case Key.deviceReset:
      let object = try expectObject(payload, keys: [Key.resetKey], required: [Key.resetKey])
      let key = try Ocp2JSON.data(from: object[Key.resetKey]!)
      return (.ocaCmd, [Ocp2DeviceReset(resetKey: key)])
    default:
      throw Ocp1Error.invalidMessageType
    }
  }

  private static func array(_ json: Any) throws -> [Any] {
    guard let array = json as? [Any] else { throw Ocp1Error.status(.badFormat) }
    return array
  }

  /// Rejects a member outside `keys` (AES70-4 example X03) or a missing `required`
  /// member (X02).
  private static func expectObject(
    _ json: Any,
    keys: Set<String>,
    required: Set<String>
  ) throws -> [String: Any] {
    guard let object = json as? [String: Any] else { throw Ocp1Error.status(.badFormat) }
    guard Set(object.keys).isSubset(of: keys), required.isSubset(of: object.keys) else {
      throw Ocp1Error.status(.badFormat)
    }
    return object
  }

  private static func parameters(_ json: Any?) throws -> Ocp1Parameters {
    guard let json, !(json is NSNull) else { return Ocp1Parameters(ocp2ParameterData: Data()) }
    guard let object = json as? [String: Any] else { throw Ocp1Error.status(.badFormat) }
    guard !object.isEmpty else { return Ocp1Parameters(ocp2ParameterData: Data()) }
    return try Ocp1Parameters(ocp2ParameterData: Ocp2JSON.serialize(object))
  }

  private static func decodeCommand(_ json: Any) throws -> Ocp1Command {
    let object = try expectObject(
      json,
      keys: [Key.handle, Key.targetONo, Key.methodID, Key.parameters],
      required: [Key.handle, Key.targetONo, Key.methodID]
    )
    let (defLevel, index) = try _ocp2ElementID(from: object[Key.methodID]!)
    return try Ocp1Command(
      handle: Ocp2JSON.integer(OcaUint32.self, from: object[Key.handle]!),
      targetONo: Ocp2JSON.integer(OcaONo.self, from: object[Key.targetONo]!),
      methodID: OcaMethodID(defLevel: defLevel, methodIndex: index),
      parameters: parameters(object[Key.parameters])
    )
  }

  private static func status(_ json: Any) throws -> OcaStatus {
    if let name = json as? String {
      guard let status = OcaStatus.allCases.first(where: { Ocp2Naming.matches($0.ocp2Name, name) })
      else {
        throw Ocp1Error.status(.badFormat)
      }
      return status
    }
    guard let status = try OcaStatus(rawValue: Ocp2JSON.integer(OcaUint8.self, from: json)) else {
      throw Ocp1Error.status(.badFormat)
    }
    return status
  }

  private static func decodeResponse(_ json: Any) throws -> Ocp1Response {
    let object = try expectObject(
      json,
      keys: [Key.handle, Key.statusCode, Key.parameters],
      required: [Key.handle, Key.statusCode]
    )
    return try Ocp1Response(
      handle: Ocp2JSON.integer(OcaUint32.self, from: object[Key.handle]!),
      statusCode: status(object[Key.statusCode]!),
      parameters: parameters(object[Key.parameters])
    )
  }

  /// The schema and examples name it `EventIdentification`; the prose says `Event`.
  private static func eventIdentification(_ object: [String: Any]) throws -> OcaEvent {
    guard let json = object[Key.eventIdentification] ?? object[Key.event],
          let identification = json as? [String: Any],
          let emitter = Ocp2Decoder.member(named: Key.emitterONo, in: identification),
          let eventID = Ocp2Decoder.member(named: Key.eventID, in: identification)
    else {
      throw Ocp1Error.status(.badFormat)
    }
    let (defLevel, index) = try _ocp2ElementID(from: eventID)
    return try OcaEvent(
      emitterONo: Ocp2JSON.integer(OcaONo.self, from: emitter),
      eventID: OcaEventID(defLevel: defLevel, eventIndex: index)
    )
  }

  private static func exceptionType(_ json: Any) throws -> Ocp1Notification2ExceptionType {
    if let name = json as? String {
      guard let type = exceptionTypeNames.first(where: { Ocp2Naming.matches($0.value, name) })?.key
      else {
        throw Ocp1Error.status(.badFormat)
      }
      return type
    }
    guard let type = try Ocp1Notification2ExceptionType(
      rawValue: Ocp2JSON.integer(OcaUint8.self, from: json)
    ) else {
      throw Ocp1Error.status(.badFormat)
    }
    return type
  }

  private static func decodeNotification(_ json: Any) throws -> Ocp1Notification2 {
    let wrapper = try expectObject(json, keys: [Key.event, Key.exception], required: [])
    guard wrapper.count == 1 else { throw Ocp1Error.status(.badFormat) }

    if let event = wrapper[Key.event] {
      let object = try expectObject(
        event,
        keys: [Key.eventIdentification, Key.event, Key.eventData],
        required: []
      )
      let eventData: Data = if let data = object[Key.eventData], !(data is NSNull) {
        try Ocp2JSON.serialize(data)
      } else {
        Data()
      }
      return try Ocp1Notification2(
        event: eventIdentification(object),
        notificationType: .event,
        data: eventData,
        dataFormat: .ocp2
      )
    }

    let object = try expectObject(
      wrapper[Key.exception]!,
      keys: [
        Key.eventIdentification,
        Key.event,
        Key.exceptionType,
        Key.tryAgain,
        Key.exceptionData,
      ],
      required: [Key.exceptionType, Key.tryAgain]
    )
    var exceptionData = Data()
    if let data = object[Key.exceptionData], !(data is NSNull) {
      if let blob = try? Ocp2JSON.data(from: data) {
        exceptionData = blob
      } else {
        exceptionData = try Ocp2JSON.serialize(data)
      }
    }
    let exception = try Ocp1Notification2ExceptionData(
      exceptionType: exceptionType(object[Key.exceptionType]!),
      tryAgain: Ocp2JSON.bool(from: object[Key.tryAgain]!),
      exceptionData: OcaBlob(exceptionData)
    )
    return try Ocp1Notification2(
      event: eventIdentification(object),
      notificationType: .exception,
      data: Ocp1Encoder().encode(exception),
      dataFormat: .ocp1
    )
  }
}

extension OcaStatus {
  /// `OcaStatus` spelled as in the AES70-4 JSON schema.
  var ocp2Name: String {
    switch self {
    case .ok: "OK"
    case .protocolVersionError: "ProtocolVersionError"
    case .deviceError: "DeviceError"
    case .locked: "Locked"
    case .badFormat: "BadFormat"
    case .badONo: "BadONo"
    case .parameterError: "ParameterError"
    case .parameterOutOfRange: "ParameterOutOfRange"
    case .notImplemented: "NotImplemented"
    case .invalidRequest: "InvalidRequest"
    case .processingFailed: "ProcessingFailed"
    case .badMethod: "BadMethod"
    case .partiallySucceeded: "PartiallySucceeded"
    case .timeout: "Timeout"
    case .bufferOverflow: "BufferOverflow"
    case .permissionDenied: "PermissionDenied"
    case .outOfMemory: "OutOfMemory"
    case .busy: "Busy"
    }
  }
}
#endif
