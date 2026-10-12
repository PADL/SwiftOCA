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

#if (os(macOS) || os(iOS) || os(Linux)) && NonEmbeddedBuild

import FlyingFox
import FlyingSocks
import Foundation
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

private func localhostAddress(port: UInt16) -> Data {
  var addr = sockaddr_in()
  addr.sin_family = sa_family_t(AF_INET)
  addr.sin_port = port.bigEndian
  addr.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
  #if canImport(Darwin)
  addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  #endif
  return withUnsafeBytes(of: addr) { Data($0) }
}

/// An OCP.1 WebSocket endpoint on an OS-assigned port, listening.
private func makeWSEndpoint(
  device: OcaDevice,
  timeout: Duration = .seconds(5)
) async throws -> (OcaFlyingFoxDeviceEndpoint, Task<(), Error>, UInt16) {
  let endpoint = try await OcaFlyingFoxDeviceEndpoint(
    address: localhostAddress(port: 0),
    timeout: timeout,
    device: device,
    controlProtocols: [.ocp1]
  )
  let endpointTask = Task { try await endpoint.run() }
  try await endpoint.waitUntilListening()
  let listeningPort = await endpoint.listeningPort
  let port = try XCTUnwrap(listeningPort)
  return (endpoint, endpointTask, port)
}

/// A GetDeviceName command on the device manager, as one OCP.1 PDU.
private func getDeviceNamePdu(handle: OcaUint32) throws -> Data {
  try OcaControlProtocol.ocp1.encodePdu(
    [Ocp1Command(handle: handle, targetONo: OcaDeviceManagerONo, methodID: OcaMethodID("3.4"))],
    type: .ocaCmdRrq
  )
}

private extension RawWebSocket {
  /// Reads binary frames as one byte stream until a response has arrived for each of
  /// `handles`, ignoring notifications.
  func ocp1Responses(for handles: Set<OcaUint32>) async throws -> [OcaUint32: Ocp1Response] {
    let reader = OcaControlProtocol.ocp1.makeReader(
      preservesPduBoundaries: false,
      maximumPduSize: OcaControlProtocol.defaultMaximumPduSize
    )
    var responses = [OcaUint32: Ocp1Response]()
    while !handles.isSubset(of: responses.keys) {
      let pdu = try await reader.nextPdu { _, _ in
        while true {
          let (opcode, payload) = try await receiveMessage()
          switch opcode {
          case 0x2 where !payload.isEmpty: return Data(payload)
          case 0x2, 0x9, 0xA: continue
          default: throw Ocp1Error.invalidMessageType
          }
        }
      }
      let (messageType, messages) = try OcaControlProtocol.ocp1.decodePdu(pdu)
      guard messageType == .ocaRsp else { continue }
      for case let response as Ocp1Response in messages {
        responses[response.handle] = response
      }
    }
    return responses
  }
}

/// The endpoint's one controller, once the upgrade has made it.
private func firstController(
  of endpoint: OcaFlyingFoxDeviceEndpoint
) async throws -> OcaController {
  let deadline = ContinuousClock.now + .seconds(5)
  while ContinuousClock.now < deadline {
    if let controller = await endpoint.controllers.first { return controller }
    try await Task.sleep(for: .milliseconds(10))
  }
  throw Ocp1Error.notConnected
}

private let event = OcaEvent(emitterONo: 4242, eventID: OcaEventID(defLevel: 1, eventIndex: 1))

/// Enough per notification to fill the loopback socket buffers within a few sends.
private let largeParameters = Data(count: 64 * 1024)

/// Raises `count` large notifications of the event, each ending in its index.
private func notify(_ device: OcaDevice, count: Int) async throws {
  for index in 0..<count {
    var parameters = largeParameters
    parameters[parameters.count - 1] = UInt8(index)
    try await device.notifySubscribers(event, parameters: parameters)
  }
}

/// Raises large notifications while `endpoint` has a controller, counting those that
/// returned and the longest any took, so that a test can see whether the sender was held up
/// on a peer that has stopped reading.
private actor Notifier {
  private(set) var sent = 0
  private(set) var longestWait = Duration.zero

  func run(_ device: OcaDevice, until endpoint: OcaFlyingFoxDeviceEndpoint) async {
    while await !endpoint.controllers.isEmpty {
      let started = ContinuousClock.now
      try? await device.notifySubscribers(event, parameters: largeParameters)
      longestWait = max(longestWait, ContinuousClock.now - started)
      sent += 1
    }
  }

  enum Outcome {
    /// the endpoint expired the controller while its peer was still connected
    case expired
    /// no notification has returned for a while: the sender is held up on the peer
    case stalled
  }

  /// Waits until `endpoint` has no controller, or no notification has returned for
  /// `quietFor`; throws after `deadline`.
  func waitUntilExpiredOrStalled(
    _ endpoint: OcaFlyingFoxDeviceEndpoint,
    quietFor: Duration,
    deadline: Duration
  ) async throws -> Outcome {
    let started = ContinuousClock.now
    var last = (sent: sent, at: started)
    while ContinuousClock.now - last.at < quietFor {
      guard ContinuousClock.now - started < deadline else { throw Ocp1Error.responseTimeout }
      if await endpoint.controllers.isEmpty { return .expired }
      try await Task.sleep(for: .milliseconds(20))
      if sent != last.sent { last = (sent, .now) }
    }
    return .stalled
  }
}

/// Waits until `endpoint` has `count` controllers, or throws after five seconds.
private func waitForControllers(
  of endpoint: OcaFlyingFoxDeviceEndpoint,
  count: Int
) async throws {
  let deadline = ContinuousClock.now + .seconds(5)
  while await endpoint.controllers.count != count {
    guard ContinuousClock.now < deadline else { throw Ocp1Error.responseTimeout }
    try await Task.sleep(for: .milliseconds(10))
  }
}

final class WebSocketBoundsTests: XCTestCase {
  private func subscribe(_ controller: OcaController, on device: OcaDevice) async throws {
    let manager = await device.subscriptionManager
    let subscriptionManager = try XCTUnwrap(manager)
    try await subscriptionManager.addSubscription(.subscription2(OcaSubscription2(
      event: event,
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )), for: controller)
  }

  /// A subscribed peer that stops reading is held in its socket, not in memory, and is
  /// expired by the write backlog budget (`OcaMaximumWriteBacklogBytes`, #181) while still
  /// connected, with no notification having waited on it. Until #181 lands the sender
  /// stalls on the full socket instead; then the peer's connection going must free it at
  /// once and remove the controller. Drop the `.stalled` arm on the rebase onto #181.
  func testPeerThatStopsReadingIsExpiredByTheBacklogBudget() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (endpoint, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    try await subscribe(firstController(of: endpoint), on: device)

    let notifier = Notifier()
    let sending = Task { await notifier.run(device, until: endpoint) }
    let outcome = try await notifier.waitUntilExpiredOrStalled(
      endpoint,
      quietFor: .milliseconds(500),
      deadline: .seconds(20)
    )
    let sent = await notifier.sent
    XCTAssertGreaterThan(sent, 0, "the socket should have taken the first frames")
    // the socket holds a few frames and the budget a few more: never thousands
    XCTAssertLessThan(sent, 100, "notifications were buffered beyond the socket and budget")

    switch outcome {
    case .expired:
      await sending.value
      let longestWait = await notifier.longestWait
      XCTAssertLessThan(longestWait, .seconds(1), "a notification waited \(longestWait) on the peer")
    case .stalled:
      let closed = ContinuousClock.now
      try webSocket.socket.close()
      await sending.value
      let released = ContinuousClock.now - closed
      XCTAssertLessThan(released, .seconds(2), "the sender waited \(released) after the peer went")
    }
    try await waitForControllers(of: endpoint, count: 0)
    try? webSocket.socket.close()
  }

  /// A peer that pings without reading stalls only its own reader: another peer is served
  /// meanwhile, and the controller is removed once the pinging peer's connection goes.
  func testPingFloodFromANonReadingPeerStallsOnlyItself() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (endpoint, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let flooder = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    let other = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    try await waitForControllers(of: endpoint, count: 2)
    let flood = Task {
      for _ in 0..<5000 {
        try await flooder.send(opcode: 0x9, Data(count: 125))
      }
    }
    try await Task.sleep(for: .milliseconds(300))

    try await other.send(opcode: 0x2, getDeviceNamePdu(handle: 1))
    let responses = try await other.ocp1Responses(for: [1])
    XCTAssertEqual(responses[1]?.statusCode, .ok)
    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 2, "the pinging peer should not have been expired")

    flood.cancel()
    try flooder.socket.close()
    try await waitForControllers(of: endpoint, count: 1)
    await other.close()
  }

  /// Notifications are not dropped for a peer that falls behind: every one arrives, in
  /// order, once it reads again, though together they are more than its socket holds (and
  /// less than the write backlog budget, which would expire it).
  func testPeerThatFallsBehindMissesNothing() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (endpoint, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    try await subscribe(firstController(of: endpoint), on: device)

    let count = 10
    let notifier = Task { try await notify(device, count: count) }
    try await Task.sleep(for: .milliseconds(200))

    var received = [UInt8]()
    let reader = OcaControlProtocol.ocp1.makeReader(
      preservesPduBoundaries: false,
      maximumPduSize: OcaControlProtocol.defaultMaximumPduSize
    )
    while received.count < count {
      let pdu = try await reader.nextPdu { _, _ in
        let (opcode, payload) = try await webSocket.receiveMessage()
        XCTAssertEqual(opcode, 0x2)
        return Data(payload)
      }
      let (messageType, messages) = try OcaControlProtocol.ocp1.decodePdu(pdu)
      XCTAssertEqual(messageType, .ocaNtf2)
      for case let notification as Ocp1Notification2 in messages {
        XCTAssertEqual(notification.data.count, largeParameters.count)
        received.append(try XCTUnwrap(notification.data.last))
      }
    }
    try await notifier.value
    XCTAssertEqual(received, (0..<count).map { UInt8($0) })
    await webSocket.close()
  }

  /// Commands are read only as fast as they are handled, so a peer that sends many at once
  /// and only then reads still gets every response.
  func testPipelinedCommandsAreAllAnswered() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    let handles = Set<OcaUint32>(1...200)
    for handle in handles.sorted() {
      try await webSocket.send(opcode: 0x2, getDeviceNamePdu(handle: handle))
    }
    let responses = try await webSocket.ocp1Responses(for: handles)
    XCTAssertEqual(responses.count, handles.count)
    XCTAssertTrue(responses.values.allSatisfy { $0.statusCode == .ok })
    await webSocket.close()
  }

  /// The device answers a ping with a pong carrying the same payload, and reads a message
  /// fragmented over continuation frames as part of the byte stream.
  func testPingsAreAnsweredAndFragmentsRead() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    try await webSocket.send(opcode: 0x9, Data("ping".utf8))
    let (opcode, payload) = try await webSocket.receive()
    XCTAssertEqual(opcode, 0xA)
    XCTAssertEqual(String(decoding: payload, as: UTF8.self), "ping")

    // RFC 6455 5.4: a control frame may arrive in the middle of a fragmented message
    let pdu = try getDeviceNamePdu(handle: 7)
    try await webSocket.send(opcode: 0x2, fin: false, pdu.prefix(5))
    try await webSocket.send(opcode: 0x9, Data("mid".utf8))
    try await webSocket.send(opcode: 0x0, fin: false, Data())
    try await webSocket.send(opcode: 0x0, pdu.dropFirst(5))
    let (midOpcode, midPayload) = try await webSocket.receive()
    XCTAssertEqual(midOpcode, 0xA)
    XCTAssertEqual(String(decoding: midPayload, as: UTF8.self), "mid")
    let responses = try await webSocket.ocp1Responses(for: [7])
    XCTAssertEqual(responses[7]?.statusCode, .ok)
    await webSocket.close()
  }

  /// RFC 6455 5.5 and 5.5.1: a peer's close frame is answered with its own code, or with
  /// 1002 when it is malformed: over 125 bytes, one byte, a code only an endpoint may
  /// report to itself, or a reason that is not UTF-8. Control frames are not fragmented.
  func testCloseFramesAreAnsweredPerRFC6455() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let cases: [(name: String, fin: Bool, payload: Data, expected: UInt16?)] = [
      ("normal closure", true, Data([0x03, 0xE8]), 1000),
      ("going away with a reason", true, Data([0x03, 0xE9]) + Data("bye".utf8), 1001),
      ("no code", true, Data(), nil),
      ("over 125 bytes", true, Data([0x03, 0xE8]) + Data(count: 124), 1002),
      ("one byte", true, Data([0x03]), 1002),
      ("1005 reserved", true, Data([0x03, 0xED]), 1002),
      ("1004 reserved", true, Data([0x03, 0xEC]), 1002),
      ("999 below the defined codes", true, Data([0x03, 0xE7]), 1002),
      ("2000 unassigned", true, Data([0x07, 0xD0]), 1002),
      ("4000 application", true, Data([0x0F, 0xA0]), 4000),
      ("invalid UTF-8 reason", true, Data([0x03, 0xE8, 0xFF]), 1002),
      ("fragmented control frame", false, Data([0x03, 0xE8]), 1002),
    ]
    for (name, fin, payload, expected) in cases {
      let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
      try await webSocket.send(opcode: 0x8, fin: fin, payload)
      let closeCode = try await webSocket.closeCode()
      XCTAssertEqual(closeCode, expected, name)
      try webSocket.socket.close()
    }
  }

  /// RFC 6455 5.4: a continuation frame outside a fragmented message closes with 1002.
  func testStrayContinuationFrameCloses1002() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (endpoint, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    _ = try await firstController(of: endpoint)
    try await webSocket.send(opcode: 0x0, Data([1, 2, 3]))
    let closeCode = try await webSocket.closeCode()
    XCTAssertEqual(closeCode, 1002)
    await webSocket.close()

    let deadline = ContinuousClock.now + .seconds(5)
    while await !endpoint.controllers.isEmpty, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    let controllers = await endpoint.controllers
    XCTAssertTrue(controllers.isEmpty, "the controller outlived its connection")
  }
}

#endif
