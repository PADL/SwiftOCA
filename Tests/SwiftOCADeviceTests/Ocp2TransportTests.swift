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

// MARK: - helpers

private func boundPort(of socket: Socket) throws -> UInt16 {
  switch try socket.sockname() {
  case let .ip4(_, port): return port
  case let .ip6(_, port): return port
  default: throw SocketError.unsupportedAddress
  }
}

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

private let ocp2Options = Ocp1ConnectionOptions(
  flags: .refreshDeviceTreeOnConnection,
  controlProtocol: .ocp2
)

// The platform's native socket backends: io_uring on Linux, FlyingSocks elsewhere.
#if canImport(IORing)
private typealias StreamDeviceEndpoint = Ocp1IORingStreamDeviceEndpoint
private typealias DatagramDeviceEndpoint = Ocp1IORingDatagramDeviceEndpoint
private typealias StreamConnection = Ocp1IORingStreamConnection
private typealias DatagramConnection = Ocp1IORingDatagramConnection

/// io_uring endpoints bind only once they run, so reserve a loopback port for them.
private func unusedPort(_ type: SocketType) throws -> UInt16 {
  let socket = try Socket(domain: AF_INET, type: type)
  defer { try? socket.close() }
  try socket.bind(to: .inet(ip4: "127.0.0.1", port: 0))
  return try boundPort(of: socket)
}

private func startStreamEndpoint(
  device: OcaDevice,
  timeout: Duration
) async throws -> (StreamDeviceEndpoint, Task<(), Error>, UInt16) {
  let port = try unusedPort(.stream)
  let endpoint = try await StreamDeviceEndpoint(
    address: localhostAddress(port: port),
    timeout: timeout,
    device: device,
    controlProtocol: .ocp2
  )
  return (endpoint, Task { try await endpoint.run() }, port)
}

private func startDatagramEndpoint(
  device: OcaDevice,
  timeout: Duration
) async throws -> (DatagramDeviceEndpoint, Task<(), Error>, UInt16) {
  let port = try unusedPort(.datagram)
  let endpoint = try await DatagramDeviceEndpoint(
    address: localhostAddress(port: port),
    timeout: timeout,
    device: device,
    controlProtocol: .ocp2
  )
  return (endpoint, Task { try await endpoint.run() }, port)
}
#else
private typealias StreamDeviceEndpoint = Ocp1FlyingSocksStreamDeviceEndpoint
private typealias DatagramDeviceEndpoint = Ocp1FlyingSocksDatagramDeviceEndpoint
private typealias StreamConnection = Ocp1FlyingSocksStreamConnection
private typealias DatagramConnection = Ocp1FlyingSocksDatagramConnection

private func startStreamEndpoint(
  device: OcaDevice,
  timeout: Duration
) async throws -> (StreamDeviceEndpoint, Task<(), Error>, UInt16) {
  let endpoint = try await StreamDeviceEndpoint(
    address: localhostAddress(port: 0),
    timeout: timeout,
    device: device,
    controlProtocol: .ocp2
  )
  let socket = try await endpoint.preparePoolAndSocket()
  let port = try boundPort(of: socket)
  return (endpoint, Task { try await endpoint._run(on: socket, pool: endpoint.pool) }, port)
}

private func startDatagramEndpoint(
  device: OcaDevice,
  timeout: Duration
) async throws -> (DatagramDeviceEndpoint, Task<(), Error>, UInt16) {
  let endpoint = try await DatagramDeviceEndpoint(
    address: localhostAddress(port: 0),
    timeout: timeout,
    device: device,
    controlProtocol: .ocp2
  )
  let socket = try await endpoint.preparePoolAndSocket()
  let port = try boundPort(of: socket)
  return (endpoint, Task { try await endpoint._run(on: socket, pool: endpoint.pool) }, port)
}
#endif

@OcaConnection
private func makeStreamConnection(
  port: UInt16,
  options: Ocp1ConnectionOptions = ocp2Options
) throws -> StreamConnection {
  try StreamConnection(deviceAddress: localhostAddress(port: port), options: options)
}

@OcaConnection
private func makeCFSocketTCPConnection(port: UInt16) throws -> Ocp1CFSocketTCPConnection {
  try Ocp1CFSocketTCPConnection(deviceAddress: localhostAddress(port: port), options: ocp2Options)
}

#if canImport(Network)
@OcaConnection
private func makeNWTCPConnection(port: UInt16) throws -> Ocp1NWTCPConnection {
  try Ocp1NWTCPConnection(deviceAddress: localhostAddress(port: port), options: ocp2Options)
}
#endif

/// A device with a gain object, listening for OCP.2 over TCP.
private struct TCPFixture {
  let device: OcaDevice
  let endpoint: StreamDeviceEndpoint
  let port: UInt16
  let gain: SwiftOCADevice.OcaGain
  let endpointTask: Task<(), Error>

  static let gainONo: OcaONo = 0x0001_0100

  init(timeout: Duration = .seconds(5)) async throws {
    device = OcaDevice()
    try await device.initializeDefaultObjects()
    gain = try await SwiftOCADevice.OcaGain(
      objectNumber: Self.gainONo,
      role: "Master Gain",
      deviceDelegate: device,
      addToRootBlock: true
    )
    let (endpoint, endpointTask, port) = try await startStreamEndpoint(device: device, timeout: timeout)
    self.endpoint = endpoint
    self.endpointTask = endpointTask
    self.port = port
    try await Task.sleep(for: .milliseconds(100))
  }

  func tearDown() {
    endpointTask.cancel()
  }
}

/// Exercises a connected OCP.2 controller: property read, write, and a search.
private func exerciseConnection(_ connection: Ocp1Connection, fixture: TCPFixture) async throws {
  XCTAssertEqual(connection.controlProtocol, .ocp2)
  XCTAssertTrue(connection.connectionPrefix.hasPrefix(OcaJsonTcpConnectionPrefix))
  let deviceManagerONo = await connection.deviceManager.objectNumber
  XCTAssertEqual(deviceManagerONo, OcaDeviceManagerONo)

  let clientGain: SwiftOCA.OcaGain = try await connection.resolve(
    object: OcaObjectIdentification(
      oNo: TCPFixture.gainONo,
      classIdentification: SwiftOCA.OcaGain.classIdentification
    )
  )
  await { @OcaDevice in fixture.gain.gain = OcaBoundedPropertyValue(value: -6, in: -100...12) }()
  let gain = try await clientGain.$gain._getValue(clientGain, flags: [])
  XCTAssertEqual(gain.value, -6)
  XCTAssertEqual(gain.minValue, -100)

  try await clientGain.$gain._setValue(clientGain, OcaBoundedPropertyValue<OcaDB>(value: -3.5, in: -100...12))
  let deviceValue = await { @OcaDevice in fixture.gain.gain.value }()
  XCTAssertEqual(deviceValue, -3.5)

  let results = try await connection.rootBlock.find(
    actionObjectsByRole: "Master Gain",
    nameComparisonType: .exact,
    resultFlags: [.oNo, .role]
  )
  XCTAssertEqual(results.map(\.oNo), [TCPFixture.gainONo])
}

// MARK: - UDP

/// AES70-4 10.4.3 makes UDP a Control Session Transport Type in its own right, with
/// `_ocajson._udp` as the service type. A session opens on the first KeepAlive — the
/// device ignores anything before it — which `connect()` sends for datagram transports.
private struct UDPFixture {
  let device: OcaDevice
  let endpoint: DatagramDeviceEndpoint
  let port: UInt16
  let gain: SwiftOCADevice.OcaGain
  let endpointTask: Task<(), Error>

  static let gainONo: OcaONo = 0x0001_0100

  init(timeout: Duration = .seconds(5)) async throws {
    device = OcaDevice()
    try await device.initializeDefaultObjects()
    gain = try await SwiftOCADevice.OcaGain(
      objectNumber: Self.gainONo,
      role: "Master Gain",
      deviceDelegate: device,
      addToRootBlock: true
    )
    let (endpoint, endpointTask, port) = try await startDatagramEndpoint(device: device, timeout: timeout)
    self.endpoint = endpoint
    self.endpointTask = endpointTask
    self.port = port
    try await Task.sleep(for: .milliseconds(100))
  }

  func tearDown() {
    endpointTask.cancel()
  }
}

final class Ocp2UDPTests: XCTestCase {
  func testDatagramEndpointAdvertisesJsonServiceType() async throws {
    let fixture = try await UDPFixture()
    defer { fixture.tearDown() }
    XCTAssertEqual(fixture.endpoint.serviceType, .udpJson)
  }

  func testRoundTripOverDatagram() async throws {
    let fixture = try await UDPFixture()
    defer { fixture.tearDown() }

    let connection = try await DatagramConnection(
      deviceAddress: localhostAddress(port: fixture.port),
      options: ocp2Options
    )
    try await connection.connect()
    defer { Task { try? await connection.disconnect() } }

    XCTAssertEqual(connection.controlProtocol, .ocp2)
    XCTAssertTrue(connection.connectionPrefix.hasPrefix(OcaJsonUdpConnectionPrefix))

    let clientGain: SwiftOCA.OcaGain = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: UDPFixture.gainONo,
        classIdentification: SwiftOCA.OcaGain.classIdentification
      )
    )
    await { @OcaDevice in fixture.gain.gain = OcaBoundedPropertyValue(value: -6, in: -100...12) }()
    let gain = try await clientGain.$gain._getValue(clientGain, flags: [])
    XCTAssertEqual(gain.value, -6)

    try await clientGain.$gain._setValue(
      clientGain,
      OcaBoundedPropertyValue<OcaDB>(value: -3.5, in: -100...12)
    )
    let deviceValue = await { @OcaDevice in fixture.gain.gain.value }()
    XCTAssertEqual(deviceValue, -3.5)

    let controllers = await fixture.endpoint.controllers
    XCTAssertEqual((controllers.first as? any Ocp1ControllerInternal)?.connectionPrefix, OcaJsonUdpConnectionPrefix)
  }
}

// MARK: - TCP

final class Ocp2TCPTests: XCTestCase {
  func testStreamClient() async throws {
    let fixture = try await TCPFixture()
    defer { fixture.tearDown() }

    let connection = try await makeStreamConnection(port: fixture.port)
    try await connection.connect()
    try await exerciseConnection(connection, fixture: fixture)
    try await connection.disconnect()
  }

  func testCFSocketClient() async throws {
    let fixture = try await TCPFixture()
    defer { fixture.tearDown() }

    let connection = try await makeCFSocketTCPConnection(port: fixture.port)
    try await connection.connect()
    try await exerciseConnection(connection, fixture: fixture)
    try await connection.disconnect()
  }

  #if canImport(Network)
  func testNWClient() async throws {
    let fixture = try await TCPFixture()
    defer { fixture.tearDown() }

    let connection = try await makeNWTCPConnection(port: fixture.port)
    try await connection.connect()
    try await exerciseConnection(connection, fixture: fixture)
    try await connection.disconnect()
  }
  #endif

  func testBatchedCommands() async throws {
    let fixture = try await TCPFixture()
    defer { fixture.tearDown() }

    let options = Ocp1ConnectionOptions(
      flags: .refreshDeviceTreeOnConnection,
      batchingOptions: try .init(batchSize: 4096, batchThreshold: .milliseconds(50)),
      controlProtocol: .ocp2
    )
    let connection = try await makeStreamConnection(port: fixture.port, options: options)
    try await connection.connect()

    // several concurrent requests share a batch: one `Commands` array on the wire
    let identifications = try await withThrowingTaskGroup(of: OcaClassIdentification.self) { group in
      for objectNumber in [OcaDeviceManagerONo, OcaSubscriptionManagerONo, OcaRootBlockONo] {
        group.addTask { try await connection.getClassIdentification(objectNumber: objectNumber) }
      }
      return try await group.reduce(into: [OcaClassIdentification]()) { $0.append($1) }
    }
    XCTAssertEqual(identifications.count, 3)

    try await connection.disconnect()
  }

  func testPropertyChangeNotificationOverTCP() async throws {
    let fixture = try await TCPFixture()
    defer { fixture.tearDown() }

    let connection = try await makeStreamConnection(port: fixture.port)
    try await connection.connect()

    let clientGain: SwiftOCA.OcaGain = try await connection.resolve(
      object: OcaObjectIdentification(
        oNo: TCPFixture.gainONo,
        classIdentification: SwiftOCA.OcaGain.classIdentification
      )
    )
    await clientGain.$gain.subscribe(clientGain)
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline, (try? await clientGain.isSubscribed) != true {
      try await Task.sleep(for: .milliseconds(25))
    }

    await { @OcaDevice in fixture.gain.gain = OcaBoundedPropertyValue(value: 1.25, in: -100...12) }()
    var observed = false
    while ContinuousClock.now < deadline, !observed {
      if case let .success(value) = clientGain.$gain.currentValue, value.value == 1.25 {
        observed = true
      } else {
        try await Task.sleep(for: .milliseconds(25))
      }
    }
    XCTAssertTrue(observed, "gain change not observed over OCP.2/TCP")

    try await connection.disconnect()
  }

  /// A hand-written OCP.2 session, as another implementation would produce it.
  func testRawJSONSession() async throws {
    let fixture = try await TCPFixture(timeout: .seconds(2))
    defer { fixture.tearDown() }

    let socket = try await AsyncSocket.connected(to: .inet(ip4: "127.0.0.1", port: fixture.port))
    defer { try? socket.close() }

    func exchange(_ text: String) async throws -> [String: Any] {
      try await socket.write(Data(text.utf8))
      var line = Data()
      while !line.contains(UInt8(ascii: "\n")) {
        line += try await socket.read(atMost: 4096)
      }
      return try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
    }

    // AES70-4 example A05, aimed at our gain
    let setGain = try await exchange("""
    {"ProtocolVersion":1,"Commands":[{"Handle":49,"TargetONo":\(TCPFixture.gainONo),"MethodID":[4,2,"SetGain"],"Parameters":{"Gain":-3.5}}]}

    """)
    let responses = try XCTUnwrap(setGain["Responses"] as? [[String: Any]])
    XCTAssertEqual(responses.count, 1)
    XCTAssertEqual(responses[0]["Handle"] as? Int, 49)
    XCTAssertEqual(responses[0]["StatusCode"] as? String, "OK")
    let deviceValue = await { @OcaDevice in fixture.gain.gain.value }()
    XCTAssertEqual(deviceValue, -3.5)

    // GetGain: Gain, minGain, maxGain
    let getGain = try await exchange("""
    {"ProtocolVersion":1,"Commands":[{"Handle":50,"TargetONo":\(TCPFixture.gainONo),"MethodID":[4,1]}]}

    """)
    let getResponse = try XCTUnwrap((getGain["Responses"] as? [[String: Any]])?.first)
    let parameters = try XCTUnwrap(getResponse["Parameters"] as? [String: Any])
    XCTAssertEqual(parameters["Gain"] as? Double, -3.5)
    XCTAssertNotNil(parameters["MinGain"])
    XCTAssertNotNil(parameters["MaxGain"])

    // AES70-4 example A01 against the root block
    let find = try await exchange("""
    {"ProtocolVersion":1,"Commands":[{"Handle":47,"TargetONo":\(OcaRootBlockONo),"MethodID":[3,17,"FindActionObjectsByRole"],"Parameters":{"SearchName":"Master Gain","NameComparisonType":"Exact","SearchClassID":[1,1,1,5],"ResultFlags":1}}]}

    """)
    let findResponse = try XCTUnwrap((find["Responses"] as? [[String: Any]])?.first)
    XCTAssertEqual(findResponse["StatusCode"] as? String, "OK")
    let result = try XCTUnwrap((findResponse["Parameters"] as? [String: Any])?["Result"] as? [[String: Any]])
    XCTAssertEqual(result.first?["ONo"] as? Int, Int(TCPFixture.gainONo))

    // an unknown object is a status, not a dropped connection
    let badONo = try await exchange("""
    {"ProtocolVersion":1,"Commands":[{"Handle":51,"TargetONo":123456789,"MethodID":[1,1]}]}

    """)
    XCTAssertEqual((badONo["Responses"] as? [[String: Any]])?.first?["StatusCode"] as? String, "BadONo")
  }

  func testKeepAliveExpiry() async throws {
    let fixture = try await TCPFixture(timeout: .seconds(2))
    defer { fixture.tearDown() }

    let socket = try await AsyncSocket.connected(to: .inet(ip4: "127.0.0.1", port: fixture.port))
    defer { try? socket.close() }

    try await socket.write(Data("{\"ProtocolVersion\":1,\"KeepAlive\":{\"HeartbeatTimeout\":200}}\n".utf8))
    let deadline = ContinuousClock.now + .seconds(2)
    var controllers = await fixture.endpoint.controllers
    while ContinuousClock.now < deadline, controllers.isEmpty {
      try await Task.sleep(for: .milliseconds(25))
      controllers = await fixture.endpoint.controllers
    }
    XCTAssertEqual(controllers.count, 1)
    let controllerProtocol = controllers.first?.controlProtocol
    XCTAssertEqual(controllerProtocol, .ocp2)
    XCTAssertEqual((controllers.first as? any Ocp1ControllerInternal)?.connectionPrefix, OcaJsonTcpConnectionPrefix)

    // the device sends its own keep-alives at the negotiated interval
    var received = Data()
    let keepAliveDeadline = ContinuousClock.now + .seconds(1)
    while ContinuousClock.now < keepAliveDeadline, !received.contains(UInt8(ascii: "\n")) {
      received += try await socket.read(atMost: 4096)
    }
    let keepAlive = try XCTUnwrap(JSONSerialization.jsonObject(with: received.prefix(while: { $0 != UInt8(ascii: "\n") })) as? [String: Any])
    XCTAssertEqual((keepAlive["KeepAlive"] as? [String: Any])?["HeartbeatTimeout"] as? Int, 200)

    // then we go silent: three missed heartbeats and the controller is expired
    let expiryDeadline = ContinuousClock.now + .seconds(3)
    while ContinuousClock.now < expiryDeadline, await !fixture.endpoint.controllers.isEmpty {
      try await Task.sleep(for: .milliseconds(50))
    }
    let remaining = await fixture.endpoint.controllers
    XCTAssertTrue(remaining.isEmpty, "silent OCP.2 controller was not expired")
  }

  func testOcp1ClientIsRejectedByOcp2Endpoint() async throws {
    let fixture = try await TCPFixture(timeout: .seconds(2))
    defer { fixture.tearDown() }

    let connection = try await makeStreamConnection(
      port: fixture.port,
      options: Ocp1ConnectionOptions(flags: [], connectionTimeout: .seconds(2), responseTimeout: .seconds(1))
    )
    try await connection.connect()
    do {
      _ = try await connection.getClassIdentification(objectNumber: OcaRootBlockONo)
      XCTFail("an OCP.1 command was answered by an OCP.2 endpoint")
    } catch {}
    try? await connection.disconnect()
  }
}

// MARK: - WebSocket

private func makeWSEndpoint(
  device: OcaDevice,
  controlProtocols: Set<OcaControlProtocol> = [.ocp2],
  paths: [OcaControlProtocol: String] = [:],
  timeout: Duration = .seconds(5)
) async throws -> (Ocp1FlyingFoxDeviceEndpoint, Task<(), Error>, UInt16) {
  let endpoint = try await Ocp1FlyingFoxDeviceEndpoint(
    address: localhostAddress(port: 0),
    timeout: timeout,
    device: device,
    controlProtocols: controlProtocols,
    paths: paths
  )
  let endpointTask = Task { try await endpoint.run() }
  try await endpoint.httpServer.waitUntilListening(timeout: 5)
  guard let listeningAddress = await endpoint.httpServer.listeningAddress else {
    throw Ocp1Error.notConnected
  }
  let port: UInt16
  switch listeningAddress {
  case let .ip4(_, p): port = p
  case let .ip6(_, p): port = p
  default: throw Ocp1Error.notConnected
  }
  return (endpoint, endpointTask, port)
}

/// A minimal RFC 6455 client, so the handshake and close codes can be checked on
/// Linux, where URLSession's WebSocket support depends on how libcurl was built.
private struct RawWebSocket {
  let socket: AsyncSocket
  let negotiatedProtocol: String?

  init(port: UInt16, path: String = "/", protocols: [String] = ["AES70-OCP.2"]) async throws {
    socket = try await AsyncSocket.connected(to: .inet(ip4: "127.0.0.1", port: port))
    let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
    let requestLines = [
      "GET \(path) HTTP/1.1",
      "Host: 127.0.0.1:\(port)",
      "Upgrade: websocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Key: \(key)",
      "Sec-WebSocket-Version: 13",
    ] + (protocols.isEmpty ? [] : ["Sec-WebSocket-Protocol: \(protocols.joined(separator: ", "))"])
      + ["", ""]
    let request = requestLines.joined(separator: "\r\n")
    try await socket.write(Data(request.utf8))

    // read byte-wise so no frame data is consumed with the headers
    var response = [UInt8]()
    while !response.suffix(4).elementsEqual("\r\n\r\n".utf8) {
      try response.append(await socket.read())
    }
    let lines = String(decoding: response, as: UTF8.self).components(separatedBy: "\r\n")
    guard lines.first?.hasPrefix("HTTP/1.1 101") == true else {
      throw Ocp1Error.notConnected
    }
    negotiatedProtocol = lines.dropFirst().compactMap { line -> String? in
      let field = line.split(separator: ":", maxSplits: 1)
      guard field.count == 2,
            field[0].lowercased() == "sec-websocket-protocol" else { return nil }
      return field[1].trimmingCharacters(in: .whitespaces)
    }.first
  }

  func send(opcode: UInt8, _ payload: Data) async throws {
    var frame = Data([0x80 | opcode])
    switch payload.count {
    case ..<126:
      frame.append(0x80 | UInt8(payload.count))
    case ...0xFFFF:
      frame.append(0x80 | 126)
      frame.append(contentsOf: [UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)])
    default:
      frame.append(0x80 | 127)
      frame.append(contentsOf: stride(from: 56, through: 0, by: -8).map { UInt8((payload.count >> $0) & 0xFF) })
    }
    // clients must mask every frame they send
    let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
    frame.append(contentsOf: mask)
    frame.append(contentsOf: payload.enumerated().map { $1 ^ mask[$0 % 4] })
    try await socket.write(frame)
  }

  func receive() async throws -> (opcode: UInt8, payload: [UInt8]) {
    let (_, opcode, payload) = try await receiveFrame()
    return (opcode, payload)
  }

  /// Reads one message, reassembling it from continuation frames.
  func receiveMessage() async throws -> (opcode: UInt8, payload: [UInt8]) {
    var (fin, opcode, payload) = try await receiveFrame()
    while !fin {
      let (nextFin, _, fragment) = try await receiveFrame()
      payload += fragment
      fin = nextFin
    }
    return (opcode, payload)
  }

  private func receiveFrame() async throws -> (fin: Bool, opcode: UInt8, payload: [UInt8]) {
    let header = try await socket.read(bytes: 2)
    var length = Int(header[1] & 0x7F)
    if length == 126 {
      length = try await socket.read(bytes: 2).reduce(0) { $0 << 8 | Int($1) }
    } else if length == 127 {
      length = try await socket.read(bytes: 8).reduce(0) { $0 << 8 | Int($1) }
    }
    let mask = header[1] & 0x80 != 0 ? try await socket.read(bytes: 4) : nil
    var payload = length > 0 ? try await socket.read(bytes: length) : []
    if let mask { payload = payload.enumerated().map { $1 ^ mask[$0 % 4] } }
    return (header[0] & 0x80 != 0, header[0] & 0x0F, payload)
  }

  /// Reads until the device's close frame and returns its status code.
  func closeCode() async throws -> UInt16? {
    while true {
      let (opcode, payload) = try await receive()
      guard opcode == 0x8 else { continue }
      return payload.count >= 2 ? UInt16(payload[0]) << 8 | UInt16(payload[1]) : nil
    }
  }

  func close() async {
    try? await send(opcode: 0x8, Data([0x03, 0xE8]))
    try? socket.close()
  }
}

final class Ocp2WebSocketTests: XCTestCase {
  // Ocp1FlyingFoxConnection is built on URLSessionWebSocketTask, so it is Apple-only
  #if os(macOS) || os(iOS)
  func testClientRoundTrip() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let expectedName = "OCP.2 WebSocket device"
    let deviceManager = await device.deviceManager!
    await { @OcaDevice in deviceManager.deviceName = expectedName }()

    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let connection = await Ocp1FlyingFoxConnection(host: "127.0.0.1", port: port, options: ocp2Options)
    try await connection.connect()
    XCTAssertEqual(connection.controlProtocol, .ocp2)
    XCTAssertTrue(connection.connectionPrefix.hasPrefix(OcaJsonWebSocketTcpConnectionPrefix))

    let deviceName = try await connection.deviceManager.$deviceName._getValue(connection.deviceManager)
    XCTAssertEqual(deviceName, expectedName)
    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty)

    try await connection.disconnect()
  }

  /// SwiftOCA's own OCP.1 and OCP.2 WebSocket clients, connected to one endpoint at once.
  func testBothClientsOnOnePort() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let expectedName = "OCP.1 and OCP.2 WebSocket device"
    let deviceManager = await device.deviceManager!
    await { @OcaDevice in deviceManager.deviceName = expectedName }()

    let (_, endpointTask, port) = try await makeWSEndpoint(
      device: device,
      controlProtocols: [.ocp1, .ocp2]
    )
    defer { endpointTask.cancel() }

    let ocp1 = await Ocp1FlyingFoxConnection(host: "127.0.0.1", port: port)
    let ocp2 = await Ocp1FlyingFoxConnection(host: "127.0.0.1", port: port, options: ocp2Options)
    try await ocp1.connect()
    try await ocp2.connect()
    XCTAssertEqual(ocp1.controlProtocol, .ocp1)
    XCTAssertEqual(ocp2.controlProtocol, .ocp2)

    for connection in [ocp1, ocp2] {
      let deviceName = try await connection.deviceManager.$deviceName._getValue(connection.deviceManager)
      XCTAssertEqual(deviceName, expectedName, "\(connection.controlProtocol)")
    }

    try await ocp1.disconnect()
    try await ocp2.disconnect()
  }
  #endif

  func testSubprotocolIsNegotiatedAndPathAdvertised() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (endpoint, endpointTask, port) = try await makeWSEndpoint(device: device, paths: [.ocp2: "/aes70"])
    defer { endpointTask.cancel() }

    XCTAssertEqual(endpoint.txtRecordAdditions.map { "\($0)=\($1)" }, ["path=/aes70"])
    #if canImport(dnssd)
    // AES70-4: txtvers, then protovers, then the optional path
    let deviceManager = await device.deviceManager!
    let txtRecords = await deviceManager.txtRecords(adding: endpoint.txtRecordAdditions)
    XCTAssertEqual(txtRecords.prefix(3).map(\.0), ["txtvers", "protovers", "path"])
    #endif
    XCTAssertEqual(endpoint.serviceType, .tcpWebSocketJson)

    let webSocket = try await RawWebSocket(port: port, path: "/aes70")
    XCTAssertEqual(webSocket.negotiatedProtocol, "AES70-OCP.2")

    // a text-framed OCP.2 exchange
    try await webSocket.send(
      opcode: 0x1,
      Data("{\"ProtocolVersion\":1,\"Commands\":[{\"Handle\":1,\"TargetONo\":1,\"MethodID\":[1,1]}]}\n".utf8)
    )
    let (opcode, payload) = try await webSocket.receive()
    XCTAssertEqual(opcode, 0x1, "expected a text frame")
    let text = String(decoding: payload, as: UTF8.self)
    XCTAssertTrue(text.hasSuffix("\n"))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    let response = try XCTUnwrap((object["Responses"] as? [[String: Any]])?.first)
    XCTAssertEqual(response["StatusCode"] as? String, "OK")
    XCTAssertNotNil((response["Parameters"] as? [String: Any])?["ClassIdentification"])

    await webSocket.close()
  }

  func testBinaryFrameCloses1003() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port)
    try await webSocket.send(opcode: 0x2, Data([0x3B, 0, 1, 0, 0, 0, 9, 4, 0, 0]))
    let closeCode = try await webSocket.closeCode()
    XCTAssertEqual(closeCode, 1003)
    await webSocket.close()
  }

  func testMalformedMessageCloses1007() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port)
    try await webSocket.send(opcode: 0x1, Data("{\"ProtocolVersion\":2,\"KeepAlive\":{\"HeartbeatTimeout\":1}}\n".utf8))
    let closeCode = try await webSocket.closeCode()
    XCTAssertEqual(closeCode, 1007)
    await webSocket.close()
  }

  /// OCP.1 and OCP.2 on one port and path: the offered subprotocol picks the protocol.
  func testOneEndpointServesBothProtocols() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (endpoint, endpointTask, port) = try await makeWSEndpoint(
      device: device,
      controlProtocols: [.ocp1, .ocp2]
    )
    defer { endpointTask.cancel() }

    XCTAssertEqual(endpoint.advertisedServices.map(\.serviceType), [.tcpWebSocket, .tcpWebSocketJson])
    XCTAssertTrue(endpoint.advertisedServices.allSatisfy(\.txtRecordAdditions.isEmpty))

    let ocp2 = try await RawWebSocket(port: port)
    XCTAssertEqual(ocp2.negotiatedProtocol, "AES70-OCP.2")
    try await assertOcp2RoundTrip(ocp2)
    await ocp2.close()

    // no subprotocol offered: OCP.1, which answers a binary KeepAlive with its own
    let ocp1 = try await RawWebSocket(port: port, protocols: [])
    XCTAssertNil(ocp1.negotiatedProtocol)
    try await ocp1.send(opcode: 0x2, Self.ocp1KeepAlive)
    let (opcode, payload) = try await ocp1.receive()
    XCTAssertEqual(opcode, 0x2, "expected a binary frame")
    XCTAssertEqual(payload.first, 0x3B, "expected an OCP.1 PDU")
    await ocp1.close()
  }

  /// Each protocol on its own path, advertised with its own `path` TXT record.
  func testProtocolsOnTheirOwnPaths() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let (endpoint, endpointTask, port) = try await makeWSEndpoint(
      device: device,
      controlProtocols: [.ocp1, .ocp2],
      paths: [.ocp2: "aes70"]
    )
    defer { endpointTask.cancel() }

    XCTAssertEqual(endpoint.paths, [.ocp1: "/", .ocp2: "/aes70"])
    XCTAssertEqual(
      endpoint.advertisedServices.map { $0.txtRecordAdditions.map { "\($0)=\($1)" } },
      [[], ["path=/aes70"]]
    )

    let ocp2 = try await RawWebSocket(port: port, path: "/aes70")
    XCTAssertEqual(ocp2.negotiatedProtocol, "AES70-OCP.2")
    try await assertOcp2RoundTrip(ocp2)
    await ocp2.close()

    // "/" serves only OCP.1, so an OCP.2 offer there is not taken up
    let ocp1 = try await RawWebSocket(port: port, path: "/")
    XCTAssertNil(ocp1.negotiatedProtocol)
    await ocp1.close()
  }

  func testAnEndpointNeedsAControlProtocol() async throws {
    do {
      _ = try await makeWSEndpoint(device: OcaDevice(), controlProtocols: [])
      XCTFail("an endpoint serving no control protocol was created")
    } catch Ocp1Error.unsupportedControlProtocol {}
  }

  /// A KeepAlive PDU with a one-second heartbeat.
  private static let ocp1KeepAlive = Data([0x3B, 0x00, 0x01, 0x00, 0x00, 0x00, 0x0B, 0x04, 0x00, 0x01, 0x00, 0x01])

  /// A GetClassIdentification on the device manager, answered in a text frame.
  private func assertOcp2RoundTrip(
    _ webSocket: RawWebSocket,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    try await webSocket.send(
      opcode: 0x1,
      Data("{\"ProtocolVersion\":1,\"Commands\":[{\"Handle\":1,\"TargetONo\":1,\"MethodID\":[1,1]}]}\n".utf8)
    )
    let (opcode, payload) = try await webSocket.receive()
    XCTAssertEqual(opcode, 0x1, "expected a text frame", file: file, line: line)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(payload)) as? [String: Any],
      file: file,
      line: line
    )
    let response = try XCTUnwrap((object["Responses"] as? [[String: Any]])?.first, file: file, line: line)
    XCTAssertEqual(response["StatusCode"] as? String, "OK", file: file, line: line)
  }
}

// MARK: - large hierarchies

/// `blocks` blocks under the root, each holding `perBlock` gains.
@OcaDevice
private func buildWideHierarchy(_ device: OcaDevice, blocks: Int, perBlock: Int) async throws {
  var oNo: OcaONo = 0x0010_0000
  for b in 0..<blocks {
    let block = try await SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>(
      objectNumber: oNo, role: "Block \(b)", deviceDelegate: device, addToRootBlock: true
    )
    oNo += 1
    for g in 0..<perBlock {
      let gain = try await SwiftOCADevice.OcaGain(
        objectNumber: oNo, role: "Gain \(g)", deviceDelegate: device, addToRootBlock: false
      )
      try await block.add(actionObject: gain)
      oNo += 1
    }
  }
}

/// A chain of `depth` nested blocks under the root.
@OcaDevice
private func buildDeepHierarchy(_ device: OcaDevice, depth: Int) async throws {
  var oNo: OcaONo = 0x0020_0000
  var parent: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>?
  for d in 0..<depth {
    let block = try await SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>(
      objectNumber: oNo, role: "Level \(d)", deviceDelegate: device, addToRootBlock: parent == nil
    )
    try await parent?.add(actionObject: block)
    parent = block
    oNo += 1
  }
}

/// Every object number reachable from the device's root block.
@OcaDevice
private func recursiveMemberONos(of device: OcaDevice) async -> Set<OcaONo> {
  Set(await device.rootBlock!.mapRecursive { member, _ in member.objectNumber })
}

private let getMembersRecursiveOnRoot = Data(
  "{\"ProtocolVersion\":1,\"Commands\":[{\"Handle\":1,\"TargetONo\":\(OcaRootBlockONo),\"MethodID\":[3,6]}]}\n"
    .utf8
)

/// A GetMembersRecursive answer is the largest PDU a device sends. Ten thousand members
/// put the JSON response well past the reader's 64 KiB chunk and any single WebSocket
/// frame; a thousand nested blocks recurse on both device and controller.
final class Ocp2LargeHierarchyTests: XCTestCase {
  private static let wideBlocks = 10
  private static let gainsPerBlock = 999
  private static let depth = 1000

  // the walk under test is the explicit one, not the tree refresh on connect
  private static let options = Ocp1ConnectionOptions(flags: [], controlProtocol: .ocp2)

  private func assertRecursiveMembers(
    of fixture: TCPFixture,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    let expected = await recursiveMemberONos(of: fixture.device)
    let connection = try await makeStreamConnection(port: fixture.port, options: Self.options)
    try await connection.connect()

    let members: OcaList<OcaBlockMember> = try await connection.rootBlock.getActionObjectsRecursive()
    XCTAssertEqual(Set(members.map(\.memberObjectIdentification.oNo)), expected, file: file, line: line)
    let resolved = try await connection.rootBlock.resolveActionObjectsRecursive()
    XCTAssertEqual(resolved.count, expected.count, file: file, line: line)

    try await connection.disconnect()
  }

  func testWideHierarchyOverTCP() async throws {
    let fixture = try await TCPFixture()
    defer { fixture.tearDown() }
    try await buildWideHierarchy(fixture.device, blocks: Self.wideBlocks, perBlock: Self.gainsPerBlock)
    try await assertRecursiveMembers(of: fixture)
  }

  func testDeepHierarchyOverTCP() async throws {
    let fixture = try await TCPFixture()
    defer { fixture.tearDown() }
    try await buildDeepHierarchy(fixture.device, depth: Self.depth)
    try await assertRecursiveMembers(of: fixture)
  }

  func testWideHierarchyOverWebSocket() async throws {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    try await buildWideHierarchy(device, blocks: Self.wideBlocks, perBlock: Self.gainsPerBlock)
    let expected = await recursiveMemberONos(of: device)
    let (_, endpointTask, port) = try await makeWSEndpoint(device: device)
    defer { endpointTask.cancel() }

    let webSocket = try await RawWebSocket(port: port)
    try await webSocket.send(opcode: 0x1, getMembersRecursiveOnRoot)
    let (opcode, payload) = try await webSocket.receiveMessage()
    await webSocket.close()

    XCTAssertEqual(opcode, 0x1, "expected a text frame")
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload)) as? [String: Any])
    let response = try XCTUnwrap((object["Responses"] as? [[String: Any]])?.first)
    XCTAssertEqual(response["StatusCode"] as? String, "OK")
    let objects = try XCTUnwrap((response["Parameters"] as? [String: Any])?["Objects"] as? [Any])
    XCTAssertEqual(objects.count, expected.count)
  }
}

#endif
