//
// Copyright (c) 2023 PADL Software Pty Ltd
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

@preconcurrency
import FlyingSocks
import Foundation
import SystemPackage

fileprivate extension SocketError {
  var mappedError: Error {
    switch self {
    case let .failed(_, errno, _):
      if errno == EBADF || errno == ESHUTDOWN || errno == EPIPE {
        Ocp1Error.notConnected
      } else {
        Errno(rawValue: errno)
      }
    case .blocked:
      self
    case .disconnected:
      Ocp1Error.notConnected
    case .unsupportedAddress:
      self
    }
  }
}

#if os(Linux)
// FIXME: why?
extension sockaddr_in: SocketAddress {}
extension sockaddr_in6: SocketAddress {}
extension sockaddr_un: SocketAddress {}
#endif

private extension Data {
  var socketAddress: any SocketAddress {
    try! withUnsafeBytes { unbound -> (any SocketAddress) in
      try unbound
        .withMemoryRebound(
          to: sockaddr_storage
            .self
        ) { storage -> (any SocketAddress) in
          let ss = storage.baseAddress!.pointee
          switch ss.ss_family {
          case sa_family_t(AF_INET):
            return try sockaddr_in.make(from: ss)
          case sa_family_t(AF_INET6):
            return try sockaddr_in6.make(from: ss)
          case sa_family_t(AF_LOCAL):
            return try sockaddr_un.make(from: ss)
          default:
            fatalError("unsupported address family")
          }
        }
    }
  }
}

private actor AsyncSocketPoolMonitor {
  static let shared = AsyncSocketPoolMonitor()

  private let pool: some AsyncSocketPool = SocketPool.make()
  private var isRunning = false
  private var task: Task<(), Error>?

  func get() async throws -> some AsyncSocketPool {
    guard !isRunning else { return pool }
    defer { isRunning = true }
    try await pool.prepare()
    task = Task {
      try await pool.run()
    }
    return pool
  }

  deinit {
    if let task {
      task.cancel()
    }
  }
}

public class Ocp1FlyingSocksConnection: Ocp1Connection {
  fileprivate let deviceAddress: any SocketAddress
  fileprivate var asyncSocket: AsyncSocket?
  fileprivate var type: Int32 {
    fatalError("must be implemented by subclass")
  }

  public convenience init(
    deviceAddress: Data,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    try self.init(socketAddress: deviceAddress.socketAddress, options: options)
  }

  fileprivate init(
    socketAddress: any SocketAddress,
    options: Ocp1ConnectionOptions
  ) throws {
    deviceAddress = socketAddress
    super.init(options: options)
  }

  deinit {
    try? asyncSocket?.close()
  }

  override func connectDevice() async throws {
    let family = Swift.type(of: deviceAddress).family
    let socket = try Socket(domain: Int32(family), type: type)
    if type == SOCK_STREAM, family == AF_INET {
      try? socket.setValue(true, for: BoolSocketOption(name: TCP_NODELAY), level: IPPROTO_TCP)
    }
    try socket.connect(to: deviceAddress)
    asyncSocket = try await AsyncSocket(
      socket: socket,
      pool: AsyncSocketPoolMonitor.shared.get()
    )
    try await super.connectDevice()
  }

  override public func disconnectDevice(clearObjectCache: Bool) async throws {
    if let asyncSocket {
      try asyncSocket.close()
    }
    try await super.disconnectDevice(clearObjectCache: clearObjectCache)
  }

  private func withMappedError<T: Sendable>(
    _ block: (_ asyncSocket: AsyncSocket) async throws
      -> T
  ) async throws -> T {
    guard let asyncSocket else {
      throw Ocp1Error.notConnected
    }

    do {
      return try await block(asyncSocket)
    } catch let error as SocketError {
      throw error.mappedError
    }
  }

  override public func read(_ length: Int) async throws -> Data {
    try await withMappedError { socket in
      try await Data(socket.read(bytes: length))
    }
  }

  override public func write(_ data: Data) async throws -> Int {
    try await withMappedError { socket in
      try await socket.write(data)
      return data.count
    }
  }
}

public final class Ocp1FlyingSocksDatagramConnection: Ocp1FlyingSocksConnection {
  override public var heartbeatTime: Duration {
    .seconds(1)
  }

  override fileprivate var type: Int32 {
    #if canImport(Glibc)
    Int32(2) // FIXME: why can't we find the symbol for this?
    #else
    SOCK_DGRAM
    #endif
  }

  override public var connectionPrefix: String {
    "\(OcaUdpConnectionPrefix)/\(deviceAddressToString(deviceAddress))"
  }

  override public var isDatagram: Bool { true }
}

public final class Ocp1FlyingSocksStreamConnection: Ocp1FlyingSocksConnection {
  override fileprivate var type: Int32 {
    #if canImport(Glibc)
    Int32(1) // FIXME: why can't we find the symbol for this?
    #else
    SOCK_STREAM
    #endif
  }

  public convenience init(
    path: String,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    try self.init(socketAddress: sockaddr_un.unix(path: path), options: options)
  }

  override public var connectionPrefix: String {
    "\(OcaTcpConnectionPrefix)/\(deviceAddressToString(deviceAddress))"
  }

  override public var isDatagram: Bool { false }
}

func deviceAddressToString(_ deviceAddress: any SocketAddress) -> String {
  var addr = deviceAddress.makeStorage()
  return withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      deviceAddressToString($0)
    }
  }
}

@_spi(SwiftOCAPrivate)
public extension Socket {
  func setValue<O: SocketOption>(_ value: O.Value, for option: O, level: CInt) throws {
    var value = option.makeSocketValue(from: value)
    let result = withUnsafeBytes(of: &value) {
      setsockopt(file.rawValue, SOL_SOCKET, option.name, $0.baseAddress!, socklen_t($0.count))
    }
    guard result >= 0 else {
      throw Errno(rawValue: errno)
    }
  }
}
#endif
