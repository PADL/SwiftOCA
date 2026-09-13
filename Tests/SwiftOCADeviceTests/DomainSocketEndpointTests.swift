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

@OcaConnection
private func makeDomainSocketConnection(
  path: String
) async throws -> Ocp1FlyingSocksStreamConnection {
  try Ocp1FlyingSocksStreamConnection(
    path: path,
    options: Ocp1ConnectionOptions(flags: .refreshDeviceTreeOnConnection)
  )
}

/// `sun_path` is 104 bytes on Darwin, too short for the per-user temporary directory
private func makeSocketPath() -> String {
  "/tmp/swiftoca-\(UUID().uuidString.prefix(8)).sock"
}

private func isSocket(at path: String) -> Bool {
  var st = stat()
  return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFSOCK
}

/// Leaves a socket file at `path`, as an endpoint that exited without unlinking does.
private func makeStaleSocket(at path: String, type: SocketType) throws {
  let socket = try Socket(domain: AF_UNIX, type: type)
  try socket.bind(to: sockaddr_un.unix(path: path))
  try socket.close()
  XCTAssertTrue(isSocket(at: path))
}

/// A FlyingSocks endpoint on a domain socket must leave its socket file in place while it
/// runs, so that clients can reach it, and must start even if an earlier endpoint left a
/// socket file at its path.
final class FlyingSocksDomainSocketEndpointTests: XCTestCase {
  /// Waits for the endpoint to bind, then for longer than it took `run()` to unlink the
  /// socket file when it did so after binding, and checks the file is still there.
  private func assertSocketFileRemains(at path: String) async throws {
    for _ in 0..<100 where !isSocket(at: path) {
      try await Task.sleep(for: .milliseconds(20))
    }
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertTrue(isSocket(at: path), "no socket file at \(path) while the endpoint runs")
  }

  private func assertStreamEndpointAcceptsConnections(staleSocket: Bool) async throws {
    let path = makeSocketPath()
    defer { unlink(path) }
    if staleSocket { try makeStaleSocket(at: path, type: .stream) }

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await Ocp1FlyingSocksStreamDeviceEndpoint(path: path, device: device)
    let endpointTask = Task { try await endpoint.run() }
    defer { endpointTask.cancel() }

    try await assertSocketFileRemains(at: path)

    let connection = try await makeDomainSocketConnection(path: path)
    try await connection.connect()
    let members = try await connection.rootBlock.resolveActionObjects()
    XCTAssertFalse(members.isEmpty, "rootBlock should have members")
    try await connection.disconnect()
  }

  private func assertDatagramEndpointIsReachable(staleSocket: Bool) async throws {
    let path = makeSocketPath()
    defer { unlink(path) }
    if staleSocket { try makeStaleSocket(at: path, type: .datagram) }

    let device = OcaDevice()
    let endpoint = try await Ocp1FlyingSocksDatagramDeviceEndpoint(
      address: FlyingSocks.AnySocketAddress(sockaddr_un.unix(path: path)).data,
      device: device
    )
    let endpointTask = Task { try await endpoint.run() }
    defer { endpointTask.cancel() }

    try await assertSocketFileRemains(at: path)

    // connecting a datagram socket fails with ENOENT if the file is gone, and with
    // ECONNREFUSED if nothing is bound to it
    let client = try Socket(domain: AF_UNIX, type: .datagram)
    defer { try? client.close() }
    try client.connect(to: sockaddr_un.unix(path: path))
  }

  func testStreamEndpointAcceptsConnectionsOnItsSocketFile() async throws {
    try await assertStreamEndpointAcceptsConnections(staleSocket: false)
  }

  func testStreamEndpointReplacesStaleSocketFile() async throws {
    try await assertStreamEndpointAcceptsConnections(staleSocket: true)
  }

  func testDatagramEndpointKeepsItsSocketFile() async throws {
    try await assertDatagramEndpointIsReachable(staleSocket: false)
  }

  func testDatagramEndpointReplacesStaleSocketFile() async throws {
    try await assertDatagramEndpointIsReachable(staleSocket: true)
  }
}

/// Frames `payload` as a binary WebSocket message, masked as a client must send it.
private func makeMaskedBinaryFrame(_ payload: [UInt8]) -> [UInt8] {
  var frame: [UInt8] = [0x82]
  if payload.count < 126 {
    frame.append(0x80 | UInt8(payload.count))
  } else {
    frame += [0x80 | 126, UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)]
  }
  let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
  frame += mask
  frame += payload.enumerated().map { $1 ^ mask[$0 % 4] }
  return frame
}

/// Reads one unmasked WebSocket frame, as a server sends it.
private func readFrame(from socket: AsyncSocket) async throws -> (opcode: UInt8, payload: [UInt8]) {
  let header = try await socket.read(bytes: 2)
  var length = Int(header[1] & 0x7F)
  if length == 126 {
    length = try await socket.read(bytes: 2).reduce(0) { $0 << 8 | Int($1) }
  } else if length == 127 {
    length = try await socket.read(bytes: 8).reduce(0) { $0 << 8 | Int($1) }
  }
  let payload = length > 0 ? try await socket.read(bytes: length) : []
  return (header[0] & 0x0F, payload)
}

/// A WebSocket endpoint on a domain socket must start even if an earlier endpoint left a
/// socket file at its path, must not remove anything else there, and must remove its socket
/// file when it stops.
final class FlyingFoxDomainSocketEndpointTests: XCTestCase {
  private func makeEndpoint(
    path: String,
    device: OcaDevice
  ) async throws -> Ocp1FlyingFoxDeviceEndpoint {
    try await Ocp1FlyingFoxDeviceEndpoint(
      address: FlyingSocks.AnySocketAddress(sockaddr_un.unix(path: path)).data,
      device: device
    )
  }

  /// `Ocp1FlyingFoxConnection` uses `URLSession`, which cannot reach a domain socket, so
  /// this upgrades a raw connection and gets the root block's class identification.
  private func assertOcp1RoundTrip(path: String) async throws {
    let socket = try await AsyncSocket.connected(to: sockaddr_un.unix(path: path))
    defer { try? socket.close() }

    let upgrade = "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
      + "Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
      + "Sec-WebSocket-Version: 13\r\n\r\n"
    try await socket.write(Data(upgrade.utf8))
    var head = [UInt8]()
    while !head.suffix(4).elementsEqual("\r\n\r\n".utf8) {
      try await head.append(socket.read())
    }
    let statusLine = String(decoding: head, as: UTF8.self).prefix { $0 != "\r" }
    XCTAssertTrue(statusLine.hasPrefix("HTTP/1.1 101"), String(statusLine))

    let command = Ocp1Command(handle: 1, targetONo: OcaRootBlockONo, methodID: OcaMethodID("1.1"))
    let pdu: Data = try Ocp1Connection.encodeOcp1MessagePdu([command], type: .ocaCmdRrq)
    try await socket.write(Data(makeMaskedBinaryFrame(Array(pdu))))

    while true {
      let (opcode, payload) = try await readFrame(from: socket)
      guard opcode == 0x2 else { continue }
      let (messageType, messages) = try Ocp1Connection.decodeOcp1MessagePdu(from: Data(payload))
      guard messageType == .ocaRsp, let response = messages.first as? Ocp1Response
      else { continue }
      XCTAssertEqual(response.handle, 1)
      XCTAssertEqual(response.statusCode, .ok)
      return
    }
  }

  private func assertEndpointAcceptsConnections(staleSocket: Bool) async throws {
    let path = makeSocketPath()
    defer { unlink(path) }
    if staleSocket { try makeStaleSocket(at: path, type: .stream) }

    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let endpoint = try await makeEndpoint(path: path, device: device)
    let endpointTask = Task { try await endpoint.run() }
    defer { endpointTask.cancel() }

    try await endpoint.httpServer.waitUntilListening(timeout: 5)
    XCTAssertTrue(isSocket(at: path), "no socket file at \(path) while the endpoint runs")
    try await assertOcp1RoundTrip(path: path)
  }

  func testEndpointAcceptsConnectionsOnItsSocketFile() async throws {
    try await assertEndpointAcceptsConnections(staleSocket: false)
  }

  func testEndpointReplacesStaleSocketFile() async throws {
    try await assertEndpointAcceptsConnections(staleSocket: true)
  }

  /// A path naming a regular file by mistake must not cost the file; bind fails instead.
  func testEndpointKeepsRegularFileAtItsPath() async throws {
    let path = makeSocketPath()
    defer { unlink(path) }
    let contents = Data("not a socket".utf8)
    XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: contents))

    let endpoint = try await makeEndpoint(path: path, device: OcaDevice())
    let endpointTask = Task { try await endpoint.run() }
    // bind fails at once, so the server never listens; waiting rather than awaiting `run()`
    // keeps a server that did bind from hanging the test
    do {
      try await endpoint.httpServer.waitUntilListening(timeout: 1)
      XCTFail("the endpoint should not bind over a regular file")
    } catch {}
    endpointTask.cancel()
    _ = await endpointTask.result
    XCTAssertEqual(FileManager.default.contents(atPath: path), contents)
  }

  func testEndpointRemovesItsSocketFileWhenCancelled() async throws {
    let path = makeSocketPath()
    defer { unlink(path) }

    let endpoint = try await makeEndpoint(path: path, device: OcaDevice())
    let endpointTask = Task { try await endpoint.run() }
    try await endpoint.httpServer.waitUntilListening(timeout: 5)
    XCTAssertTrue(isSocket(at: path))

    endpointTask.cancel()
    _ = await endpointTask.result
    var st = stat()
    XCTAssertNotEqual(lstat(path, &st), 0, "a file is left at \(path) after the endpoint stopped")
  }
}

#endif
