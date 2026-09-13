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

/// A FlyingSocks endpoint on a domain socket must leave its socket file in place while it
/// runs, so that clients can reach it, and must start even if an earlier endpoint left a
/// socket file at its path.
final class FlyingSocksDomainSocketEndpointTests: XCTestCase {
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

#endif
