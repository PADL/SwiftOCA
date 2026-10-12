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

/// Raises `count` notifications of the event, each carrying its index.
private func notify(_ device: OcaDevice, count: Int) async throws {
  for index in 0..<count {
    try await device.notifySubscribers(event, parameters: Data([UInt8(index)]))
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

  /// A subscribed peer that stops reading is held up in its socket, not in memory: once
  /// the socket is full, a notification waits no longer than the endpoint's timeout, and the
  /// controller is then expired.
  func testPeerThatStopsReadingIsExpired() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let timeout = Duration.milliseconds(500)
    let (endpoint, endpointTask, port) = try await makeWSEndpoint(device: device, timeout: timeout)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    try await subscribe(firstController(of: endpoint), on: device)

    // enough per notification to fill the loopback buffers in a few hundred sends
    let parameters = Data(count: 64 * 1024)
    let deadline = ContinuousClock.now + .seconds(60)
    var sent = 0
    while await !endpoint.controllers.isEmpty, ContinuousClock.now < deadline {
      let started = ContinuousClock.now
      try? await device.notifySubscribers(event, parameters: parameters)
      let waited = ContinuousClock.now - started
      XCTAssertLessThan(waited, timeout * 4, "notification \(sent) waited \(waited) on the peer")
      sent += 1
    }
    let controllers = await endpoint.controllers
    XCTAssertTrue(controllers.isEmpty, "a peer that stopped reading was not expired after \(sent) sends")
    XCTAssertGreaterThan(sent, 1, "the first notification should have been taken")
    await webSocket.close()
  }

  /// Notifications are not dropped for a peer that falls behind within the timeout: every
  /// one arrives, in order, once it reads again.
  func testPeerThatFallsBehindMissesNothing() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (endpoint, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    try await subscribe(firstController(of: endpoint), on: device)

    let count = 100
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

    let pdu = try getDeviceNamePdu(handle: 7)
    try await webSocket.send(opcode: 0x2, fin: false, pdu.prefix(5))
    try await webSocket.send(opcode: 0x0, fin: false, Data())
    try await webSocket.send(opcode: 0x0, pdu.dropFirst(5))
    let responses = try await webSocket.ocp1Responses(for: [7])
    XCTAssertEqual(responses[7]?.statusCode, .ok)
    await webSocket.close()
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
