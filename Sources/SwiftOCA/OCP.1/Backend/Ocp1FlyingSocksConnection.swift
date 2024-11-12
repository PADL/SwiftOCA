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

package extension SocketAddress {
  func makeStorage() -> sockaddr_storage {
    var storage = sockaddr_storage()
    var addr = self
    let addrSize = MemoryLayout<Self>.size
    let storageSize = MemoryLayout<sockaddr_storage>.size

    withUnsafePointer(to: &addr) { addrPtr in
      let addrRawPtr = UnsafeRawPointer(addrPtr)
      withUnsafeMutablePointer(to: &storage) { storagePtr in
        let storageRawPtr = UnsafeMutableRawPointer(storagePtr)
        let copySize = min(addrSize, storageSize)
        storageRawPtr.copyMemory(from: addrRawPtr, byteCount: copySize)
      }
    }
    return storage
  }
}

#if os(Linux)
extension sockaddr_in: SocketAddress {}
extension sockaddr_in6: SocketAddress {}
extension sockaddr_un: SocketAddress {}
#endif
extension sockaddr_storage: SocketAddress {}

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

public class Ocp1FlyingSocksStreamConnection: Ocp1Connection {
  fileprivate let deviceAddress: any SocketAddress
  fileprivate var asyncSocket: AsyncSocket?

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
    let socket = try Socket(domain: Int32(family), type: .stream)
    if family == AF_INET {
      try? socket.setValue(true, for: BoolSocketOption(name: TCP_NODELAY), level: CInt(IPPROTO_TCP))
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
      try await Data(socket.read(atMost: length))
    }
  }

  override public func write(_ data: Data) async throws -> Int {
    try await withMappedError { socket in
      try await socket.write(data)
      return data.count
    }
  }
}

public final class Ocp1FlyingSocksDatagramConnection: Ocp1Connection {
  fileprivate let deviceAddress: any SocketAddress
  fileprivate var asyncSocket: AsyncSocket?

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
    let socket = try Socket(domain: Int32(family), type: .datagram)
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

  override public var connectionPrefix: String {
    "\(OcaUdpConnectionPrefix)/\(deviceAddressToString(deviceAddress))"
  }

  override public var heartbeatTime: Duration {
    .seconds(1)
  }

  override public var isDatagram: Bool { true }

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
      try await Data(socket.read(atMost: Ocp1MaximumDatagramPduSize))
    }
  }

  override public func write(_ data: Data) async throws -> Int {
    try await withMappedError { socket in
      try await socket.write(data)
      return data.count
    }
  }
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
