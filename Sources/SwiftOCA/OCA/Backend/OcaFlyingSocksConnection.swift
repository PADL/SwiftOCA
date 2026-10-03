//
//  OcaFlyingSocksConnection.swift
//
//  Copyright (c) 2022 Simon Whitty. All rights reserved.
//  Portions Copyright (c) 2023-2026 PADL Software Pty Ltd. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

#if os(macOS) || os(iOS) || os(Windows) || canImport(Android) || !NonEmbeddedBuild

import FlyingSocks
import Logging
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
// Selectively import only the PADL `AnySocketAddress` struct, not the whole
// `SocketAddress` package: this file vends its own `AnySocketAddress` via the
// `FlyingSocks` enum, so a wholesale import would clash with the PADL
// `SocketAddress` protocol. `FlyingSocks.AnySocketAddress` stays fully qualified.
import struct SocketAddress.AnySocketAddress
import SystemPackage
#if canImport(Synchronization)
import Synchronization
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(WinSDK)
import WinSDK
#endif

fileprivate extension SocketError {
  var mappedError: Error {
    switch self {
    case let .failed(_, errno, _):
      if errno == EBADF || errno == ESHUTDOWN || errno == EPIPE {
        Ocp1Error.notConnected
      } else {
        Errno(rawValue: errno)
      }
    case .disconnected:
      Ocp1Error.notConnected
    default:
      self
    }
  }
}

@_spi(SwiftOCAPrivate)
public enum FlyingSocks {
  public struct AnySocketAddress: SocketAddress, Sendable {
    private let _storage: sockaddr_storage

    public init(_ address: any SocketAddress) {
      self.init(address.makeStorage())
    }

    public init(_ storage: sockaddr_storage) {
      _storage = storage
    }

    public init(data: Data) throws {
      try self.init(bytes: Array(data))
    }

    public init(bytes addressBytes: [UInt8]) throws {
      guard addressBytes.count >= MemoryLayout<sockaddr>.size,
            addressBytes.count <= MemoryLayout<sockaddr_storage>.size
      else {
        throw SocketError.unsupportedAddress
      }

      var storage = sockaddr_storage()
      withUnsafeMutablePointer(to: &storage) { ptr in
        _ = memcpy(ptr, addressBytes, addressBytes.count)
      }
      self.init(storage)
    }

    public var bytes: [UInt8] {
      Array(withUnsafeBytes(of: _storage) { $0 }.prefix(_size))
    }

    public var data: Data {
      Data(bytes)
    }

    public static var family: sa_family_t {
      sa_family_t(AF_UNSPEC)
    }

    #if compiler(>=6.0)
    public func withSockAddr<
      R,
      E: Error
    >(_ body: (UnsafePointer<sockaddr>, socklen_t) throws(E) -> R) throws(E) -> R {
      let size = _size
      return try withUnsafeBytes(of: _storage) { p throws(E) -> R in
        try body(p.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(size))
      }
    }
    #else
    public func withSockAddr<R>(_ body: (UnsafePointer<sockaddr>, socklen_t) throws -> R) rethrows
      -> R
    {
      let size = _size
      return try withUnsafeBytes(of: _storage) { p in
        try body(p.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(size))
      }
    }
    #endif

    private var _size: Int {
      #if canImport(Darwin)
      return Int(_storage.ss_len)
      #else
      switch Int32(_storage.ss_family) {
      case AF_INET: return MemoryLayout<sockaddr_in>.size
      case AF_INET6: return MemoryLayout<sockaddr_in6>.size
      case AF_UNIX: return MemoryLayout<sockaddr_un>.size
      default: return MemoryLayout<sockaddr_storage>.size
      }
      #endif
    }

    public func makeStorage() -> sockaddr_storage {
      _storage
    }
  }
}

package extension SocketAddress {
  var port: UInt16 {
    let storage = makeStorage()
    return withUnsafePointer(to: storage) { address in
      switch Int32(family) {
      case AF_INET:
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
          UInt16(bigEndian: sin.pointee.sin_port)
        }
      case AF_INET6:
        address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
          UInt16(bigEndian: sin6.pointee.sin6_port)
        }
      default:
        0
      }
    }
  }
}

private actor AsyncSocketPoolMonitor {
  static let shared = AsyncSocketPoolMonitor()

  private static let logger = Logger(label: "com.padl.SwiftOCA")

  private typealias Pool = (generation: Int, pool: any AsyncSocketPool, prepared: Task<(), Error>)

  // shared by every connection, so never stopped on behalf of any one of them
  private var current: Pool?
  private var generation = 0

  func get() async throws -> any AsyncSocketPool {
    let current = current ?? _start()
    try await current.prepared.value
    return current.pool
  }

  // installs the pool before suspending, so concurrent callers share one prepare() and run()
  private func _start() -> Pool {
    generation += 1
    let generation = generation
    let pool: any AsyncSocketPool = SocketPool.make()
    let prepared = Task { try await pool.prepare() }
    let current = (generation: generation, pool: pool, prepared: prepared)
    self.current = current
    Task { [weak self] in
      // SocketPool.run() is not restartable: one kqueue/epoll error (e.g. a
      // peer's socket closed mid-poll) permanently kills the pool. Build a
      // fresh one so reconnecting connections can recover.
      do {
        try await prepared.value
        try await pool.run()
      } catch {
        Self.logger.warning("socket pool event loop failed: \(error), rebuilding pool")
      }
      await self?._discard(generation)
    }
    return current
  }

  private func _discard(_ staleGeneration: Int) {
    if current?.generation == staleGeneration {
      current = nil
    }
  }
}

/// One connection's view of the shared pool. FlyingSocks keeps its own record of the
/// events registered per fd, which closing the fd does not clear: a later socket given
/// the same fd is then never registered and hangs. So a connection drains its waits,
/// letting the pool deregister their events, before closing its socket. Remove once
/// swhitty/FlyingFox#244 is merged and the pin includes it.
private final class ConnectionSocketPool: AsyncSocketPool {
  private struct State {
    var isDrained = false
    var nextID = 0
    var waits = [Int: Task<(), Error>]()
  }

  private let shared: any AsyncSocketPool
  private let state = Mutex(State())

  init(shared: any AsyncSocketPool) {
    self.shared = shared
  }

  func prepare() async throws {}

  func run() async throws {}

  func suspendSocket(_ socket: Socket, untilReadyFor events: Socket.Events) async throws {
    let shared = shared
    let wait = Task { try await shared.suspendSocket(socket, untilReadyFor: events) }
    let id = state.withLock { state -> Int? in
      guard !state.isDrained else { return nil }
      state.nextID += 1
      state.waits[state.nextID] = wait
      return state.nextID
    }
    guard let id else {
      wait.cancel()
      _ = try? await wait.value
      throw Ocp1Error.notConnected
    }
    defer { _ = state.withLock { $0.waits.removeValue(forKey: id) } }
    try await withTaskCancellationHandler {
      try await wait.value
    } onCancel: {
      wait.cancel()
    }
  }

  func drain() async {
    let waits = state.withLock { state in
      state.isDrained = true
      return Array(state.waits.values)
    }
    for wait in waits { wait.cancel() }
    for wait in waits { _ = try? await wait.value }
  }
}

@available(*, deprecated, renamed: "OcaFlyingSocksConnection")
public typealias Ocp1FlyingSocksConnection = OcaFlyingSocksConnection

public class OcaFlyingSocksConnection: OcaConnection, Ocp1MutableSocketAddressConnection {
  // The bare `AnySocketAddress` here is the PADL struct (selectively imported
  // above); `FlyingSocks.AnySocketAddress` stays fully qualified everywhere else.
  package let _deviceAddressState: Mutex<Ocp1DeviceAddressState>
  fileprivate var _asyncSocket: AsyncSocket?
  private var _socketPool: ConnectionSocketPool?

  package init(
    addressState: Ocp1DeviceAddressState,
    options: OcaConnectionOptions = OcaConnectionOptions()
  ) throws {
    _deviceAddressState = Mutex(addressState)
    super.init(options: options)
  }

  public convenience init(
    deviceAddresses: [Data],
    options: OcaConnectionOptions = OcaConnectionOptions()
  ) throws {
    // Drop any candidate that won't parse rather than discarding the whole list.
    try self.init(
      addressState: Ocp1DeviceAddressState(
        addresses: deviceAddresses.compactMap { try? AnySocketAddress(bytes: Array($0)) }
      ),
      options: options
    )
  }

  public convenience init(
    deviceAddress: Data,
    options: OcaConnectionOptions = OcaConnectionOptions()
  ) throws {
    try self.init(deviceAddresses: [deviceAddress], options: options)
  }

  /// Connect to `host`:`port`, resolved to candidate addresses on each connect
  /// attempt. An unresolved name is treated as "not reachable yet" and retried.
  public convenience init(
    host: String,
    port: UInt16,
    options: OcaConnectionOptions = OcaConnectionOptions()
  ) throws {
    try self.init(
      addressState: Ocp1DeviceAddressState(networkAddress: Ocp1NetworkAddress(
        address: host,
        port: port
      )),
      options: options
    )
  }

  deinit {
    try? _asyncSocket?.close()
  }

  override public var localAddress: Data? {
    guard let socket = _asyncSocket?.socket else { return nil }
    var addr = sockaddr_storage()
    var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
    let result = withUnsafeMutablePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
        getsockname(socket.file.rawValue, sa, &len)
      }
    }
    guard result == 0 else { return nil }
    return FlyingSocks.AnySocketAddress(addr).data
  }

  private func _cleanupConnection() async {
    let asyncSocket = _asyncSocket, socketPool = _socketPool
    _asyncSocket = nil
    _socketPool = nil
    await socketPool?.drain()
    try? asyncSocket?.close()
  }

  override public func connectDevice() async throws {
    await _cleanupConnection()
    do {
      try await _connectFirstReachableDeviceAddress()
      try await super.connectDevice()
    } catch {
      await _cleanupConnection()
      throw error
    }
  }

  package func _connectDevice(to deviceAddress: AnySocketAddress) async throws {
    let fsAddress = try FlyingSocks.AnySocketAddress(data: deviceAddress.data)
    let socket = try Socket(domain: Int32(fsAddress.family), type: socketType)
    do {
      try? setSocketOptions(socket, family: fsAddress.family)
      // Wrap before connecting: AsyncSocket marks the socket non-blocking, so
      // connect suspends on the pool and stays cancellable — a blocked syscall
      // would let one black-holed candidate eat the whole connect budget.
      // also connect UDP sockets to ensure we do not receive unsolicited replies
      let socketPool = try await ConnectionSocketPool(shared: AsyncSocketPoolMonitor.shared.get())
      let asyncSocket = try AsyncSocket(socket: socket, pool: socketPool)
      do {
        try await asyncSocket.connect(to: fsAddress)
      } catch {
        await socketPool.drain()
        throw error
      }
      _asyncSocket = asyncSocket
      _socketPool = socketPool
    } catch {
      try? socket.close()
      throw error
    }
  }

  override public func disconnectDevice() async throws {
    await _cleanupConnection()
    try await super.disconnectDevice()
  }

  public convenience init(
    path: String,
    options: OcaConnectionOptions = OcaConnectionOptions()
  ) throws {
    try self.init(
      deviceAddresses: [FlyingSocks.AnySocketAddress(sockaddr_un.unix(path: path)).data],
      options: options
    )
  }

  fileprivate func withMappedError<T: Sendable>(
    _ block: (_ asyncSocket: AsyncSocket) async throws
      -> T
  ) async throws -> T {
    guard let _asyncSocket else {
      throw Ocp1Error.notConnected
    }

    do {
      return try await block(_asyncSocket)
    } catch let error as SocketError {
      throw error.mappedError
    } catch is CancellationError where !Task.isCancelled {
      // spurious resumption from the socket pool tearing down its waiters
      // after its event loop died; recoverable, unlike a real cancellation
      throw Ocp1Error.notConnected
    } catch let error as Ocp1Error {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as Errno {
      throw error
    } catch {
      // e.g. the pool's "Not Ready" error once its event loop has died;
      // treat as connection loss so the monitor reconnects onto a fresh pool
      logger.debug("socket error \(error), treating as connection loss")
      throw Ocp1Error.notConnected
    }
  }

  override public func write(_ data: Data) async throws -> Int {
    try await withMappedError { socket in
      try await socket.write(data)
      return data.count
    }
  }

  var socketType: SocketType {
    fatalError("socketType must be implemented by a concrete subclass of OcaFlyingSocksConnection")
  }

  func setSocketOptions(_ socket: Socket, family: sa_family_t) throws {}
}

@available(*, deprecated, renamed: "OcaFlyingSocksStreamConnection")
public typealias Ocp1FlyingSocksStreamConnection = OcaFlyingSocksStreamConnection

public final class OcaFlyingSocksStreamConnection: OcaFlyingSocksConnection {
  override public var connectionPrefix: String {
    let prefix = _connectionPrefix(ocp1: OcaTcpConnectionPrefix, ocp2: OcaJsonTcpConnectionPrefix)
    return "\(prefix)/\(_currentPresentationAddress)"
  }

  override public var isDatagram: Bool { false }

  override var socketType: SocketType { .stream }

  override public func read(_ length: Int, awaitingAllRead: Bool) async throws -> Data {
    try await withMappedError { socket in
      if awaitingAllRead {
        return try await Data(socket.read(bytes: length))
      }
      return try await Data(socket.read(atMost: length))
    }
  }

  override func setSocketOptions(_ socket: Socket, family: sa_family_t) throws {
    if family == AF_INET {
      try socket.setValue(true, for: BoolSocketOption(name: TCP_NODELAY), level: CInt(IPPROTO_TCP))
    }
  }
}

@available(*, deprecated, renamed: "OcaFlyingSocksDatagramConnection")
public typealias Ocp1FlyingSocksDatagramConnection = OcaFlyingSocksDatagramConnection

public final class OcaFlyingSocksDatagramConnection: OcaFlyingSocksConnection {
  override public var connectionPrefix: String {
    let prefix = _connectionPrefix(ocp1: OcaUdpConnectionPrefix, ocp2: OcaJsonUdpConnectionPrefix)
    return "\(prefix)/\(_currentPresentationAddress)"
  }

  override public var heartbeatTime: Duration {
    .seconds(1)
  }

  override public var isDatagram: Bool { true }

  override var socketType: SocketType { .datagram }

  override public func read(_ length: Int, awaitingAllRead: Bool) async throws -> Data {
    try await withMappedError { socket in
      try await Data(socket.read(atMost: min(length, Ocp1MaximumDatagramPduSize)))
    }
  }
}

@_spi(SwiftOCAPrivate)
public extension Socket {
  func setValue<O: SocketOption>(_ value: O.Value, for option: O, level: CInt) throws {
    var value = option.makeSocketValue(from: value)
    let result = withUnsafeBytes(of: &value) {
      setsockopt(file.rawValue, level, option.name, $0.baseAddress!, socklen_t($0.count))
    }
    guard result >= 0 else {
      throw Errno(rawValue: errno)
    }
  }
}

package extension Socket {
  func setIPv6Only() throws {
    try setValue(1, for: Int32SocketOption(name: IPV6_V6ONLY), level: CInt(IPPROTO_IPV6))
  }
}
#endif
