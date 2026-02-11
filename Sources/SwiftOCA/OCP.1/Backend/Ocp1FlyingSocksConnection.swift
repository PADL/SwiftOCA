//
//  Ocp1FlyingSocksConnection.swift
//
//  Copyright (c) 2022 Simon Whitty. All rights reserved.
//  Portions Copyright (c) 2023 PADL Software Pty Ltd. All rights reserved.
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

#if os(macOS) || os(iOS) || canImport(Android)

import FlyingSocks
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SystemPackage
#if canImport(Synchronization)
import Synchronization
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

  private let pool: some AsyncSocketPool = SocketPool.make()
  private var task: Task<(), Error>?

  func get() async throws -> some AsyncSocketPool {
    guard task == nil else { return pool }
    try await pool.prepare()
    task = Task {
      try await pool.run()
    }
    return pool
  }

  func stop() {
    if let task {
      task.cancel()
      self.task = nil
    }
  }

  deinit {
    if let task {
      task.cancel()
    }
  }
}

public class Ocp1FlyingSocksConnection: Ocp1Connection {
  fileprivate let _deviceAddress: Mutex<FlyingSocks.AnySocketAddress>
  fileprivate var _asyncSocket: AsyncSocket?

  public convenience init(
    deviceAddress: Data,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    try self.init(
      socketAddress: FlyingSocks.AnySocketAddress(data: deviceAddress),
      options: options
    )
  }

  fileprivate init(
    socketAddress: FlyingSocks.AnySocketAddress,
    options: Ocp1ConnectionOptions
  ) throws {
    _deviceAddress = Mutex<FlyingSocks.AnySocketAddress>(socketAddress)
    super.init(options: options)
  }

  deinit {
    try? _asyncSocket?.close()
  }

  nonisolated var deviceAddress: Data {
    get {
      _deviceAddress.criticalValue.data
    }
    set {
      do {
        try _deviceAddress.withLock {
          $0 = try FlyingSocks.AnySocketAddress(data: newValue)
          Task { [weak self] in await self?.deviceAddressDidChange() }
        }
      } catch {}
    }
  }

  fileprivate nonisolated var _presentationAddress: String {
    deviceAddress.socketPresentationAddress!
  }

  override public func connectDevice() async throws {
    let socket = try _deviceAddress.withLock { deviceAddress in
      let socket = try Socket(domain: Int32(deviceAddress.family), type: socketType)
      try? setSocketOptions(socket, family: deviceAddress.family)
      // also connect UDP sockets to ensure we do not receive unsolicited replies
      try socket.connect(to: deviceAddress)
      return socket
    }
    _asyncSocket = try await AsyncSocket(
      socket: socket,
      pool: AsyncSocketPoolMonitor.shared.get()
    )
    try await super.connectDevice()
  }

  override public func disconnectDevice() async throws {
    await AsyncSocketPoolMonitor.shared.stop()
    if let _asyncSocket {
      try _asyncSocket.close()
      self._asyncSocket = nil
    }
    try await super.disconnectDevice()
  }

  public convenience init(
    path: String,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    try self.init(
      socketAddress: FlyingSocks.AnySocketAddress(sockaddr_un.unix(path: path)),
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
    }
  }

  override public func write(_ data: Data) async throws -> Int {
    try await withMappedError { socket in
      try await socket.write(data)
      return data.count
    }
  }

  var socketType: SocketType {
    fatalError("socketType must be implemented by a concrete subclass of Ocp1FlyingSocksConnection")
  }

  func setSocketOptions(_ socket: Socket, family: sa_family_t) throws {}
}

public final class Ocp1FlyingSocksStreamConnection: Ocp1FlyingSocksConnection {
  override public var connectionPrefix: String {
    "\(OcaTcpConnectionPrefix)/\(_presentationAddress)"
  }

  override public var isDatagram: Bool { false }

  override var socketType: SocketType { .stream }

  override public func read(_ length: Int) async throws -> Data {
    try await withMappedError { socket in
      try await Data(socket.read(bytes: length))
    }
  }

  override func setSocketOptions(_ socket: Socket, family: sa_family_t) throws {
    if family == AF_INET {
      try socket.setValue(true, for: BoolSocketOption(name: TCP_NODELAY), level: CInt(IPPROTO_TCP))
    }
  }
}

public final class Ocp1FlyingSocksDatagramConnection: Ocp1FlyingSocksConnection {
  override public var connectionPrefix: String {
    "\(OcaUdpConnectionPrefix)/\(_presentationAddress)"
  }

  override public var heartbeatTime: Duration {
    .seconds(1)
  }

  override public var isDatagram: Bool { true }

  override var socketType: SocketType { .datagram }

  override public func read(_ length: Int) async throws -> Data {
    try await withMappedError { socket in
      try await Data(socket.read(atMost: Ocp1MaximumDatagramPduSize))
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
