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

#if canImport(IORing)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import Glibc

#if swift(>=6.0)
internal import IORing
internal import IORingFoundation
internal import IORingUtils
#else
@_implementationOnly import IORing
@_implementationOnly import IORingFoundation
@_implementationOnly import IORingUtils
#endif

import SocketAddress
import struct SystemPackage.Errno

fileprivate extension Errno {
  var mappedError: Error {
    switch self {
    case .connectionRefused:
      fallthrough
    case .connectionReset:
      fallthrough
    case .brokenPipe:
      return Ocp1Error.notConnected
    case .canceled:
      return Ocp1Error.retryOperation
    default:
      return self
    }
  }
}

public class Ocp1IORingConnection: Ocp1Connection {
  fileprivate let _deviceAddress: any SocketAddress
  fileprivate var _socket: Socket?
  fileprivate var _type: Int32 {
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
    _deviceAddress = socketAddress
    super.init(options: options)
  }

  public convenience init(
    path: String,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    try self.init(
      socketAddress: sockaddr_un(
        family: sa_family_t(AF_LOCAL),
        presentationAddress: path
      ),
      options: options
    )
  }

  override public func disconnectDevice() async throws {
    _socket = nil
    try await super.disconnectDevice()
  }

  fileprivate func withMappedError<T: Sendable>(
    _ block: (_ socket: Socket) async throws
      -> T
  ) async throws -> T {
    guard let _socket else {
      throw Ocp1Error.notConnected
    }

    do {
      return try await block(_socket)
    } catch let error as Errno {
      throw error.mappedError
    }
  }
}

public final class Ocp1IORingDatagramConnection: Ocp1IORingConnection {
  private var receiveBufferSize: Int!

  override public var heartbeatTime: Duration {
    .seconds(1)
  }

  override fileprivate var _type: Int32 {
    SOCK_DGRAM
  }

  override fileprivate init(
    socketAddress: any SocketAddress,
    options: Ocp1ConnectionOptions
  ) throws {
    guard socketAddress.family == AF_INET || socketAddress.family == AF_INET6
    else { throw Errno.addressFamilyNotSupported }
    try super.init(socketAddress: socketAddress, options: options)
  }

  override public func connectDevice() async throws {
    let socket = try Socket(
      ring: IORing.shared,
      domain: _deviceAddress.family,
      type: __socket_type(UInt32(_type)),
      protocol: 0
    )

    try await socket.connect(to: _deviceAddress)
    _socket = socket
    try await super.connectDevice()
  }

  override public func read(_ length: Int) async throws -> Data {
    try await withMappedError { socket in
      try await Data(socket.receive(count: Ocp1MaximumDatagramPduSize))
    }
  }

  override public func write(_ data: Data) async throws -> Int {
    try await withMappedError { socket in
      try await socket.send(Array(data))
      return data.count
    }
  }

  override public var connectionPrefix: String {
    "\(OcaUdpConnectionPrefix)/\(try! _deviceAddress.presentationAddress)"
  }

  override public var isDatagram: Bool { true }
}

public final class Ocp1IORingDomainSocketDatagramConnection: Ocp1IORingConnection {
  private var receiveBufferSize: Int!
  private var localAddress: (any SocketAddress)?

  override public var heartbeatTime: Duration {
    .seconds(1)
  }

  override fileprivate var _type: Int32 {
    SOCK_DGRAM
  }

  override fileprivate init(
    socketAddress: any SocketAddress,
    options: Ocp1ConnectionOptions
  ) throws {
    guard socketAddress.family == AF_LOCAL else { throw Errno.addressFamilyNotSupported }
    localAddress = try sockaddr_un.ephemeralDatagramDomainSocketName
    try super.init(socketAddress: socketAddress, options: options)
  }

  override public func connectDevice() async throws {
    let localAddress = try sockaddr_un.ephemeralDatagramDomainSocketName
    let ring = try IORing()
    let socket = try Socket(
      ring: ring,
      domain: _deviceAddress.family,
      type: __socket_type(UInt32(_type)),
      protocol: 0
    )

    if let receiveBufferSize = try? Int(socket.getIntegerOption(option: SO_RCVBUF)) {
      self.receiveBufferSize = receiveBufferSize
    } else {
      receiveBufferSize = Ocp1MaximumDatagramPduSize
    }
    try socket.bind(to: localAddress)
    self.localAddress = localAddress
    try await ring.registerFixedBuffers(count: 1, size: receiveBufferSize)
    try await socket.connect(to: _deviceAddress)
    _socket = socket
    try await super.connectDevice()
  }

  override public func read(_ length: Int) async throws -> Data {
    try await withMappedError { socket in
      try await Data(socket.readFixed(
        count: receiveBufferSize,
        bufferIndex: 0,
        awaitingAllRead: false
      ))
    }
  }

  override public func write(_ data: Data) async throws -> Int {
    try await withMappedError { socket in
      try await socket.send(Array(data))
      return data.count
    }
  }

  override public func disconnectDevice() async throws {
    if let localAddress {
      _ = try? unlink(localAddress.presentationAddress)
    }
    receiveBufferSize = nil
    try await super.disconnectDevice()
  }

  override public var connectionPrefix: String {
    "\(OcaLocalConnectionPrefix)/\(try! _deviceAddress.presentationAddress)"
  }

  override public var isDatagram: Bool { true }
}

public final class Ocp1IORingStreamConnection: Ocp1IORingConnection {
  override fileprivate var _type: Int32 {
    SOCK_STREAM
  }

  override public func connectDevice() async throws {
    let socket = try Socket(
      ring: IORing.shared,
      domain: _deviceAddress.family,
      type: __socket_type(UInt32(_type)),
      protocol: 0
    )
    if _deviceAddress.family == AF_INET || _deviceAddress.family == AF_INET6 {
      try socket.setTcpNoDelay()
    }
    try await socket.connect(to: _deviceAddress)
    _socket = socket
    try await super.connectDevice()
  }

  override public func read(_ length: Int) async throws -> Data {
    try await withMappedError { socket in
      try await Data(socket.read(count: length, awaitingAllRead: true))
    }
  }

  override public func write(_ data: Data) async throws -> Int {
    try await withMappedError { socket in
      try await socket.write(Array(data), count: data.count, awaitingAllWritten: true)
    }
  }

  override public var connectionPrefix: String {
    let prefix = _deviceAddress
      .family == AF_LOCAL ? OcaLocalConnectionPrefix : OcaTcpConnectionPrefix
    return "\(prefix)/\(try! _deviceAddress.presentationAddress)"
  }

  override public var isDatagram: Bool { false }
}

#endif
