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

package extension AnySocketAddress {
  init(data: Data) throws {
    try self.init(bytes: Array(data))
  }

  init(bytes addressBytes: [UInt8]) throws {
    try self.init(sockaddr_storage(bytes: addressBytes))
  }

  var bytes: [UInt8] {
    let storage = makeStorage()
    #if canImport(Darwin)
    let size = storage.ss_len
    #else
    let size = switch Int32(family) {
    case AF_INET: MemoryLayout<sockaddr_in>.size
    case AF_INET6: MemoryLayout<sockaddr_in6>.size
    case AF_UNIX: MemoryLayout<sockaddr_un>.size
    default: MemoryLayout<sockaddr_storage>.size
    }
    #endif
    return Array(withUnsafeBytes(of: storage) { $0 }.prefix(Int(size)))
  }

  var data: Data {
    Data(bytes)
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

  var presentationAddress: String {
    deviceAddressToString(makeStorage())
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
  fileprivate let deviceAddress: any SocketAddress
  fileprivate var asyncSocket: AsyncSocket?

  public convenience init(
    deviceAddress: Data,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    try self.init(socketAddress: AnySocketAddress(data: deviceAddress), options: options)
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

  override public func connectDevice() async throws {
    let socket = try Socket(domain: Int32(deviceAddress.family), type: socketType)
    try? setSocketOptions(socket)
    // also connect UDP sockets to ensure we do not receive unsolicited replies
    try socket.connect(to: deviceAddress)
    asyncSocket = try await AsyncSocket(
      socket: socket,
      pool: AsyncSocketPoolMonitor.shared.get()
    )
    try await super.connectDevice()
  }

  override public func disconnectDevice() async throws {
    await AsyncSocketPoolMonitor.shared.stop()
    if let asyncSocket {
      try asyncSocket.close()
      self.asyncSocket = nil
    }
    try await super.disconnectDevice()
  }

  public convenience init(
    path: String,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    try self.init(socketAddress: sockaddr_un.unix(path: path), options: options)
  }

  fileprivate func withMappedError<T: Sendable>(
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

  override public func write(_ data: Data) async throws -> Int {
    try await withMappedError { socket in
      try await socket.write(data)
      return data.count
    }
  }

  var socketType: SocketType {
    fatalError("socketType must be implemented by a concrete subclass of Ocp1FlyingSocksConnection")
  }

  func setSocketOptions(_ socket: Socket) throws {}
}

public final class Ocp1FlyingSocksStreamConnection: Ocp1FlyingSocksConnection {
  override public var connectionPrefix: String {
    "\(OcaTcpConnectionPrefix)/\(deviceAddressToString(deviceAddress))"
  }

  override public var isDatagram: Bool { false }

  override var socketType: SocketType { .stream }

  override public func read(_ length: Int) async throws -> Data {
    try await withMappedError { socket in
      try await Data(socket.read(bytes: length))
    }
  }

  override func setSocketOptions(_ socket: Socket) throws {
    if deviceAddress.family == AF_INET {
      try socket.setValue(true, for: BoolSocketOption(name: TCP_NODELAY), level: CInt(IPPROTO_TCP))
    }
  }
}

public final class Ocp1FlyingSocksDatagramConnection: Ocp1FlyingSocksConnection {
  override public var connectionPrefix: String {
    "\(OcaUdpConnectionPrefix)/\(deviceAddressToString(deviceAddress))"
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
      setsockopt(file.rawValue, level, option.name, $0.baseAddress!, socklen_t($0.count))
    }
    guard result >= 0 else {
      throw Errno(rawValue: errno)
    }
  }
}

package extension Socket {
  func setIPv6Only() throws {
    try setValue(1, for: Int32SocketOption(name: IPV6_V6ONLY), level: IPPROTO_IPV6)
  }
}
#endif
