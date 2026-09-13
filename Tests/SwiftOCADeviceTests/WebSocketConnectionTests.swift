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

#if os(macOS) || os(iOS)

import FlyingFox
import FlyingSocks
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice
@preconcurrency import XCTest

// MARK: - helpers

/// Create a sockaddr_in for 127.0.0.1 on the given port
private func localhostAddress(port: UInt16) -> Data {
  var addr = sockaddr_in()
  addr.sin_family = sa_family_t(AF_INET)
  addr.sin_port = port.bigEndian
  addr.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian // 127.0.0.1
  #if canImport(Darwin)
  addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  #endif
  return withUnsafeBytes(of: addr) { Data($0) }
}

/// Create a WebSocket device endpoint on an OS-assigned port, start it,
/// wait until it is listening, then return the endpoint, its task, and actual port.
private func makeWSEndpoint(
  device: OcaDevice,
  controlProtocols: Set<OcaControlProtocol> = [.ocp1],
  timeout: Duration = .seconds(5)
) async throws -> (OcaFlyingFoxDeviceEndpoint, Task<(), Error>, UInt16) {
  let address = localhostAddress(port: 0)
  let endpoint = try await OcaFlyingFoxDeviceEndpoint(
    address: address,
    timeout: timeout,
    device: device,
    controlProtocols: controlProtocols
  )
  let endpointTask = Task { try await endpoint.run() }
  // Wait for the HTTP server to bind and start listening
  try await endpoint.httpServer.waitUntilListening(timeout: 5)
  guard let listeningAddress = await endpoint.httpServer.listeningAddress else {
    throw Ocp1Error.notConnected
  }
  let port: UInt16
  switch listeningAddress {
  case let .ip4(_, p):
    port = p
  case let .ip6(_, p):
    port = p
  default:
    throw Ocp1Error.notConnected
  }
  return (endpoint, endpointTask, port)
}

/// Create a WebSocket client connection to the given port
@OcaConnectionActor
private func makeWSConnection(
  port: UInt16
) -> OcaFlyingFoxConnection {
  OcaFlyingFoxConnection(host: "127.0.0.1", port: port)
}

// MARK: - tests

final class WebSocketConnectionTests: XCTestCase {
  /// Test basic connect/disconnect over WebSocket.
  func testWSConnectDisconnect() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let connection = await makeWSConnection(port: port)
    try await connection.connect()

    let connected = await connection.isConnected
    XCTAssertTrue(connected, "WebSocket connection should be connected")

    let deviceManagerONo = await connection.deviceManager.objectNumber
    XCTAssertEqual(deviceManagerONo, OcaDeviceManagerONo)

    try await connection.disconnect()
  }

  /// Test reading and writing the device manager's device name over WebSocket.
  func testWSReadWriteDeviceName() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let expectedName = "WebSocketTestDevice"
    let deviceManager = await device.deviceManager!
    Task { @OcaDevice in deviceManager.deviceName = expectedName }

    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let connection = await makeWSConnection(port: port)
    try await connection.connect()

    let deviceName = try await connection.deviceManager.$deviceName._getValue(
      connection.deviceManager
    )
    XCTAssertEqual(deviceName, expectedName, "Device name should match what was set on the device")

    try await connection.disconnect()
  }

  /// Test round-trip: resolve root block members over WebSocket.
  func testWSRoundTrip() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let connection = await makeWSConnection(port: port)
    try await connection.connect()

    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "rootBlock should have members")

    try await connection.disconnect()
  }

  /// Verify WebSocket connection has no OCP.1 heartbeat (relies on WS ping/pong).
  func testWSNoHeartbeat() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let connection = await makeWSConnection(port: port)
    try await connection.connect()

    let heartbeat = await connection.heartbeatTime
    XCTAssertEqual(heartbeat, .zero, "WebSocket connection should have zero heartbeat")

    // Connection should remain alive without keepalives
    try await Task.sleep(for: .seconds(2))
    let connected = await connection.isConnected
    XCTAssertTrue(connected, "WebSocket connection dropped unexpectedly without keepalive")

    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "rootBlock should still have members after wait")

    try await connection.disconnect()
  }

  /// Test that disconnecting a WebSocket client cleans up the server-side controller.
  func testWSControllerCleanup() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (endpoint, endpointTask, port) = try await makeWSEndpoint(
      device: device,
      timeout: .seconds(3)
    )
    defer { endpointTask.cancel() }

    let connection = await makeWSConnection(port: port)
    try await connection.connect()

    let controllers = await endpoint.controllers
    XCTAssertEqual(controllers.count, 1, "Expected exactly one controller")

    try await connection.disconnect()

    // Give the server time to detect disconnection and clean up
    try await Task.sleep(for: .seconds(1))
    let controllersAfterDisconnect = await endpoint.controllers
    XCTAssertEqual(
      controllersAfterDisconnect.count, 0,
      "Server controller was not cleaned up after WebSocket client disconnected"
    )
  }

  /// A route appended to the endpoint serves plain requests, including on the control
  /// protocol's path, while WebSocket upgrades still reach the control protocol.
  func testWSAppendedRouteSharesPath() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let (endpoint, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    await endpoint.appendRoute(HTTPRoute("GET /*")) { _ in
      HTTPResponse(statusCode: .ok, body: Data("static".utf8))
    }

    for path in ["/", "/index.html"] {
      let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
      let (data, response) = try await URLSession.shared.data(from: url)
      XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, path)
      XCTAssertEqual(String(decoding: data, as: UTF8.self), "static", path)
    }

    let connection = await makeWSConnection(port: port)
    try await connection.connect()
    let deviceManagerONo = await connection.deviceManager.objectNumber
    XCTAssertEqual(deviceManagerONo, OcaDeviceManagerONo)
    try await connection.disconnect()
  }
}

#if NonEmbeddedBuild

// MARK: - AES70-3 8.4.3.4

private let deviceName = "AES70-3 WebSocket device"

private func makeNamedDevice() async throws -> OcaDevice {
  let device = OcaDevice()
  try await device.initializeDefaultObjects()
  let deviceManager = await device.deviceManager!
  await { @OcaDevice in deviceManager.deviceName = deviceName }()
  return device
}

/// A GetDeviceName command on the device manager, as one OCP.1 PDU.
private func getDeviceNamePdu(handle: OcaUint32) throws -> Data {
  try OcaControlProtocol.ocp1.encodePdu(
    [Ocp1Command(handle: handle, targetONo: OcaDeviceManagerONo, methodID: OcaMethodID("3.4"))],
    type: .ocaCmdRrq
  )
}

private extension RawWebSocket {
  /// Reads binary frames as one byte stream, as AES70-3 8.4.3.4.4 requires of a
  /// controller too, until a response has arrived for each of `handles`.
  func ocp1Responses(for handles: Set<OcaUint32>) async throws -> [OcaUint32: Ocp1Response] {
    let reader = OcaControlProtocol.ocp1.makeReader(
      isMessageOriented: false,
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

  /// Sends a GetDeviceName in one binary frame and checks the answer.
  func assertOcp1RoundTrip(file: StaticString = #filePath, line: UInt = #line) async throws {
    try await send(opcode: 0x2, getDeviceNamePdu(handle: 1))
    try await assertDeviceName(ocp1Responses(for: [1])[1], file: file, line: line)
  }
}

private func assertDeviceName(
  _ response: Ocp1Response?,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  let response = try XCTUnwrap(response, file: file, line: line)
  XCTAssertEqual(response.statusCode, .ok, file: file, line: line)
  let name = try Ocp1Decoder().decode(OcaString.self, from: response.parameters.parameterData)
  XCTAssertEqual(name, deviceName, file: file, line: line)
}

/// Records the subprotocols each WebSocket upgrade offered.
private actor OfferedSubprotocols {
  var values = [String?]()
  func append(_ value: String?) { values.append(value) }
}

extension WebSocketConnectionTests {
  /// AES70-3 8.4.3.4.2: a controller offers `AES70-OCP.1`, which the device echoes, as a
  /// browser fails a connection whose offered subprotocols the server does not select.
  func testWSOcp1SubprotocolIsEchoed() async throws {
    let device = try await makeNamedDevice()
    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    XCTAssertEqual(webSocket.negotiatedProtocol, "AES70-OCP.1")
    try await webSocket.assertOcp1RoundTrip()
    await webSocket.close()
  }

  /// A controller that predates AES70-3 8.4.3.4.2 offers no subprotocol, and still gets
  /// OCP.1, with none echoed.
  func testWSNoSubprotocolSpeaksOcp1() async throws {
    let device = try await makeNamedDevice()
    let (_, endpointTask, port) = try await makeWSEndpoint(
      device: device,
      controlProtocols: [.ocp1, .ocp2]
    )
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port, protocols: [])
    XCTAssertNil(webSocket.negotiatedProtocol)
    try await webSocket.assertOcp1RoundTrip()
    await webSocket.close()
  }

  /// On a path serving both, the subprotocol picks the protocol, in the client's order of
  /// preference when it offers both.
  func testWSSubprotocolSelectsProtocol() async throws {
    let device = try await makeNamedDevice()
    let (_, endpointTask, port) = try await makeWSEndpoint(
      device: device,
      controlProtocols: [.ocp1, .ocp2]
    )
    defer { endpointTask.cancel() }

    for protocols in [["AES70-OCP.1"], ["AES70-OCP.1", "AES70-OCP.2"]] {
      let webSocket = try await RawWebSocket(port: port, protocols: protocols)
      XCTAssertEqual(webSocket.negotiatedProtocol, "AES70-OCP.1", "\(protocols)")
      try await webSocket.assertOcp1RoundTrip()
      await webSocket.close()
    }

    for protocols in [["AES70-OCP.2"], ["AES70-OCP.2", "AES70-OCP.1"]] {
      let webSocket = try await RawWebSocket(port: port, protocols: protocols)
      XCTAssertEqual(webSocket.negotiatedProtocol, "AES70-OCP.2", "\(protocols)")
      try await webSocket.send(
        opcode: 0x1,
        Data(
          "{\"ProtocolVersion\":1,\"Commands\":[{\"Handle\":1,\"TargetONo\":1,\"MethodID\":[1,1]}]}\n"
            .utf8
        )
      )
      let (opcode, payload) = try await webSocket.receive()
      XCTAssertEqual(opcode, 0x1, "expected a text frame for \(protocols)")
      XCTAssertEqual(payload.first, UInt8(ascii: "{"), "expected an OCP.2 PDU for \(protocols)")
      await webSocket.close()
    }
  }

  /// AES70-3 8.4.3.4.4: a text frame closes the connection with UNEXPECTED (1011).
  func testWSOcp1TextFrameCloses1011() async throws {
    let device = try await makeNamedDevice()
    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    try await webSocket.send(opcode: 0x1, Data("hello".utf8))
    let closeCode = try await webSocket.closeCode()
    XCTAssertEqual(closeCode, 1011)
    await webSocket.close()
  }

  /// AES70-3 8.4.3.4.4: a malformed OCP.1 message closes the connection with BAD_DATA
  /// (1007), whether its framing or its content is bad.
  func testWSMalformedOcp1PduCloses1007() async throws {
    let device = try await makeNamedDevice()
    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let malformed: [(String, [UInt8])] = [
      ("bad sync byte", [0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x09, 0x04, 0x00, 0x00]),
      ("PDU size too small", [0x3B, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x04, 0x00, 0x00]),
      ("PDU size too large", [0x3B, 0x00, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0x04, 0x00, 0x00]),
      // one command, whose size is shorter than its own size field
      (
        "undecodable command",
        [0x3B, 0x00, 0x01, 0x00, 0x00, 0x00, 0x0D, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02]
      ),
    ]
    for (name, pdu) in malformed {
      let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
      try await webSocket.send(opcode: 0x2, Data(pdu))
      let closeCode = try await webSocket.closeCode()
      XCTAssertEqual(closeCode, 1007, name)
      await webSocket.close()
    }
  }

  /// AES70-3 8.4.3.4.4: binary frames are a byte stream, so one frame may hold two PDUs.
  func testWSTwoOcp1PdusInOneFrame() async throws {
    let device = try await makeNamedDevice()
    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    try await webSocket.send(opcode: 0x2, getDeviceNamePdu(handle: 1) + getDeviceNamePdu(handle: 2))
    let responses = try await webSocket.ocp1Responses(for: [1, 2])
    try assertDeviceName(responses[1])
    try assertDeviceName(responses[2])
    await webSocket.close()
  }

  /// AES70-3 8.4.3.4.4: binary frames are a byte stream, so a PDU may span frames,
  /// including an empty one, and a frame may end one PDU and begin the next.
  func testWSOcp1PduSplitAcrossFrames() async throws {
    let device = try await makeNamedDevice()
    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    let first = try getDeviceNamePdu(handle: 1)
    let second = try getDeviceNamePdu(handle: 2)
    // splits inside the first header, inside its body, and inside the second header
    for frame in [
      first.prefix(4),
      first[4..<12],
      Data(),
      first[12...] + second.prefix(3),
      second.dropFirst(3),
    ] {
      try await webSocket.send(opcode: 0x2, Data(frame))
    }
    let responses = try await webSocket.ocp1Responses(for: [1, 2])
    try assertDeviceName(responses[1])
    try assertDeviceName(responses[2])
    await webSocket.close()
  }

  /// SwiftOCA's client offers `AES70-OCP.1`, and still connects to a device that predates
  /// AES70-3 8.4.3.4.2 and so does not echo it: URLSessionWebSocketTask, like RFC 6455
  /// 4.1, fails a handshake only for a subprotocol it did not offer.
  func testWSClientOffersOcp1AndToleratesNoEcho() async throws {
    let device = try await makeNamedDevice()
    let (endpoint, endpointTask, _) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    // an OCP.1 route as it was before the subprotocol was echoed
    let offered = OfferedSubprotocols()
    let server = try HTTPServer(address: .inet(ip4: "127.0.0.1", port: 0), timeout: 5)
    await server.appendRoute("GET /") { request in
      await offered.append(request.headers[OcaFlyingFoxDeviceEndpoint.webSocketProtocolHeader])
      return try await WebSocketHTTPHandler
        .webSocket(OcaFlyingFoxDeviceEndpoint.Handler(endpoint, controlProtocol: .ocp1, peer: nil))
        .handleRequest(request)
    }
    let serverTask = Task { try await server.run() }
    defer { serverTask.cancel() }
    try await server.waitUntilListening(timeout: 5)
    guard case let .ip4(_, port) = await server.listeningAddress else {
      throw Ocp1Error.notConnected
    }

    let webSocket = try await RawWebSocket(port: port, protocols: ["AES70-OCP.1"])
    XCTAssertNil(webSocket.negotiatedProtocol, "the legacy route should not echo")
    await webSocket.close()

    let connection = await makeWSConnection(port: port)
    try await connection.connect()
    let name = try await connection.deviceManager.$deviceName._getValue(connection.deviceManager)
    XCTAssertEqual(name, deviceName)
    try await connection.disconnect()

    let values = await offered.values
    XCTAssertEqual(values.last, "AES70-OCP.1")
  }

  /// AES70-3 8.4.3.4.4: a controller too closes the connection with UNEXPECTED (1011) when
  /// it receives a text frame.
  func testWSClientClosesOcp1TextFrame1011() async throws {
    let device = try await makeNamedDevice()
    let (endpoint, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }
    let (injector, url) = await makeFrameInjector(endpoint, port: port, controlProtocol: .ocp1)

    let connection = await OcaFlyingFoxConnection(url: url)
    try await connection.connect()
    injector.inject(WSFrame(fin: true, opcode: .text, mask: nil, payload: Data("hello".utf8)))
    let closeCode = await injector.firstCloseCode()
    XCTAssertEqual(closeCode, 1011)
    try? await connection.disconnect()
  }

  /// AES70-4 10.4.3.4.4: text frames are a byte stream, so an empty one adds nothing, and the
  /// client does not take it for the end of the connection.
  func testWSClientSkipsEmptyOcp2TextFrame() async throws {
    let device = try await makeNamedDevice()
    let (endpoint, endpointTask, port) = try await makeWSEndpoint(
      device: device,
      controlProtocols: [.ocp2]
    )
    defer { endpointTask.cancel() }
    let (injector, url) = await makeFrameInjector(endpoint, port: port, controlProtocol: .ocp2)

    let connection = await OcaFlyingFoxConnection(
      url: url,
      options: OcaConnectionOptions(controlProtocol: .ocp2)
    )
    try await connection.connect()
    injector.inject(WSFrame(fin: true, opcode: .text, mask: nil, payload: Data()))
    _ = try await connection.getClassIdentification(objectNumber: OcaRootBlockONo)
    let isConnected = await connection.isConnected
    XCTAssertTrue(isConnected)
    try await connection.disconnect()
    let closeCode = await injector.firstCloseCode()
    XCTAssertEqual(closeCode, 1000, "the client should close only when disconnected")
  }
}

/// Stands between a client and the endpoint's handler, to send the client frames a device
/// would not, including an empty one, which a `WSMessage` cannot express, and to see the
/// close codes the client sends back.
private final class FrameInjector: WSHandler, @unchecked Sendable {
  private let handler: MessageFrameWSHandler
  private let lock = NSLock()
  private var framesOut: AsyncStream<WSFrame>.Continuation?
  private let closeCodes: AsyncStream<UInt16>
  private let closeCodesIn: AsyncStream<UInt16>.Continuation

  init(_ endpoint: OcaFlyingFoxDeviceEndpoint, controlProtocol: OcaControlProtocol) {
    handler = MessageFrameWSHandler(
      handler: OcaFlyingFoxDeviceEndpoint.Handler(
        endpoint,
        controlProtocol: controlProtocol,
        peer: nil
      )
    )
    (closeCodes, closeCodesIn) = AsyncStream.makeStream()
  }

  /// Sends the client `frame`, after the frames the device has sent so far.
  func inject(_ frame: WSFrame) {
    lock.withLock { framesOut }?.yield(frame)
  }

  /// The first close code the client sends, or `nil` if it sends none within `timeout`.
  func firstCloseCode(timeout: Duration = .seconds(5)) async -> UInt16? {
    await withTaskGroup(of: UInt16?.self) { [closeCodes] group in
      group.addTask { await closeCodes.first { _ in true } }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return nil
      }
      defer { group.cancelAll() }
      return await group.next() ?? nil
    }
  }

  func makeFrames(for client: AsyncThrowingStream<WSFrame, any Error>) async throws
    -> AsyncStream<WSFrame>
  {
    let closeCodesIn = closeCodesIn
    let observed = AsyncThrowingStream<WSFrame, any Error> { continuation in
      let task = Task {
        do {
          for try await frame in client {
            if frame.opcode == .close, frame.payload.count >= 2 {
              closeCodesIn.yield(frame.payload.prefix(2).reduce(0) { $0 << 8 | UInt16($1) })
            }
            continuation.yield(frame)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
    let deviceFrames = try await handler.makeFrames(for: observed)
    let (frames, framesOut) = AsyncStream.makeStream(of: WSFrame.self)
    lock.withLock { self.framesOut = framesOut }
    let task = Task {
      for await frame in deviceFrames {
        framesOut.yield(frame)
      }
      framesOut.finish()
    }
    framesOut.onTermination = { @Sendable _ in task.cancel() }
    return frames
  }
}

/// Serves `endpoint`'s `controlProtocol` through a `FrameInjector` at `/inject`, a route on
/// the endpoint's own server, and returns the URL to connect to. A second `HTTPServer` would
/// do, but in a full test run one started after another's has left later WebSocket upgrades
/// unanswered.
private func makeFrameInjector(
  _ endpoint: OcaFlyingFoxDeviceEndpoint,
  port: UInt16,
  controlProtocol: OcaControlProtocol
) async -> (FrameInjector, URL) {
  let injector = FrameInjector(endpoint, controlProtocol: controlProtocol)
  await endpoint.appendRoute(HTTPRoute("GET /inject"), to: WebSocketHTTPHandler(handler: injector))
  return (injector, URL(string: "ws://127.0.0.1:\(port)/inject")!)
}

#endif

#endif
