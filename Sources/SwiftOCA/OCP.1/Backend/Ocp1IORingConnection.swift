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
public import IORing
internal import IORingFoundation
internal import IORingUtils
#else
public import IORing
@_implementationOnly import IORingFoundation
@_implementationOnly import IORingUtils
#endif

import SocketAddress
import struct SystemPackage.Errno
#if canImport(Synchronization)
import Synchronization
#endif

package extension Errno {
  var mappedError: Error {
    switch self {
    case .connectionRefused, .connectionReset, .brokenPipe:
      Ocp1Error.notConnected
    case .canceled:
      Ocp1Error.retryOperation
    default:
      self
    }
  }
}

public class Ocp1IORingConnection: Ocp1Connection, Ocp1MutableSocketAddressConnection {
  fileprivate let _ring: IORing
    package let _deviceAddresses: Mutex<[AnySocketAddress]>
    package let _connectedDeviceAddress = Mutex<AnySocketAddress?>(nil)
  fileprivate var _socket: Socket?
  fileprivate var _type: Int32 {
    fatalError("must be implemented by subclass")
  }

    package func _connectDevice(to deviceAddress: AnySocketAddress) async throws {
    fatalError("must be implemented by subclass")
  }

  public convenience init(
    deviceAddress: Data,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions(),
    ring: IORing = .shared
  ) throws {
    try self.init(socketAddresses: [deviceAddress.socketAddress], options: options, ring: ring)
  }

  public convenience init(
    deviceAddresses: [Data],
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions(),
    ring: IORing = .shared
  ) throws {
    try self.init(
      socketAddresses: deviceAddresses.compactMap { try? $0.socketAddress },
      options: options,
      ring: ring
    )
  }

  fileprivate init(
    socketAddresses: [any SocketAddress],
    options: Ocp1ConnectionOptions,
    ring: IORing = .shared
  ) throws {
    _deviceAddresses = Mutex(socketAddresses.map { AnySocketAddress($0) })
    _ring = ring
    super.init(options: options)
  }

  public convenience init(
    path: String,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions(),
    ring: IORing = .shared
  ) throws {
    try self.init(
      socketAddresses: [sockaddr_un(
        family: sa_family_t(AF_LOCAL),
        presentationAddress: path
      )],
      options: options,
      ring: ring
    )
  }

  fileprivate func _cleanupConnection() {
    _socket = nil
  }

  override public func disconnectDevice() async throws {
    _cleanupConnection()
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

  override public var localAddress: Data? {
    guard let socket = _socket else { return nil }
    return try? AnySocketAddress(socket.localAddress).data
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
    socketAddresses: [any SocketAddress],
    options: Ocp1ConnectionOptions,
    ring: IORing
  ) throws {
    guard socketAddresses.allSatisfy({ $0.family == AF_INET || $0.family == AF_INET6 })
    else { throw Errno.addressFamilyNotSupported }
    try super.init(socketAddresses: socketAddresses, options: options, ring: ring)
  }

  override public func connectDevice() async throws {
    _cleanupConnection()
    try await _connectFirstReachableDeviceAddress()
    try await super.connectDevice()
  }

    override package func _connectDevice(to deviceAddress: AnySocketAddress) async throws {
    let socket = try Socket(
      ring: _ring,
      domain: deviceAddress.family,
      type: __socket_type(UInt32(_type)),
      protocol: 0
    )

    try await socket.connect(to: deviceAddress)
    _socket = socket
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
    "\(OcaUdpConnectionPrefix)/\(_currentPresentationAddress)"
  }

  override public var isDatagram: Bool { true }
}

public final class Ocp1IORingDomainSocketDatagramConnection: Ocp1IORingConnection {
  private var receiveBufferSize: Int!
  private var _boundAddress: (any SocketAddress)?

  override public var heartbeatTime: Duration {
    .seconds(1)
  }

  override fileprivate var _type: Int32 {
    SOCK_DGRAM
  }

  override fileprivate init(
    socketAddresses: [any SocketAddress],
    options: Ocp1ConnectionOptions,
    ring: IORing
  ) throws {
    guard socketAddresses.allSatisfy({ $0.family == AF_LOCAL })
    else { throw Errno.addressFamilyNotSupported }
    _boundAddress = try sockaddr_un.ephemeralDatagramDomainSocketName
    try super.init(socketAddresses: socketAddresses, options: options, ring: ring)
  }

  override fileprivate func _cleanupConnection() {
    if let _boundAddress {
      _ = try? unlink(_boundAddress.presentationAddress)
    }
    super._cleanupConnection()
  }

  override public func connectDevice() async throws {
    _cleanupConnection()
    try await _connectFirstReachableDeviceAddress()
    try await super.connectDevice()
  }

    override package func _connectDevice(to deviceAddress: AnySocketAddress) async throws {
    let boundAddress = try sockaddr_un.ephemeralDatagramDomainSocketName
    let ring = try IORing()
    let socket = try Socket(
      ring: ring,
      domain: deviceAddress.family,
      type: __socket_type(UInt32(_type)),
      protocol: 0
    )

    if let receiveBufferSize = try? Int(socket.getIntegerOption(option: SO_RCVBUF)) {
      self.receiveBufferSize = receiveBufferSize
    } else {
      receiveBufferSize = Ocp1MaximumDatagramPduSize
    }
    try socket.bind(to: boundAddress)
    _boundAddress = boundAddress
    try await ring.registerFixedBuffers(count: 1, size: receiveBufferSize)
    try await socket.connect(to: deviceAddress)
    _socket = socket
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
    receiveBufferSize = nil
    try await super.disconnectDevice()
  }

  override public var connectionPrefix: String {
    "\(OcaLocalConnectionPrefix)/\(_currentPresentationAddress)"
  }

  override public var isDatagram: Bool { true }
}

public final class Ocp1IORingStreamConnection: Ocp1IORingConnection {
  override fileprivate var _type: Int32 {
    SOCK_STREAM
  }

  override public func connectDevice() async throws {
    _cleanupConnection()
    try await _connectFirstReachableDeviceAddress()
    try await super.connectDevice()
  }

    override package func _connectDevice(to deviceAddress: AnySocketAddress) async throws {
    let socket = try Socket(
      ring: _ring,
      domain: deviceAddress.family,
      type: __socket_type(UInt32(_type)),
      protocol: 0
    )
    if deviceAddress.family == AF_INET || deviceAddress.family == AF_INET6 {
      try socket.setTcpNoDelay()
    }
    try await socket.connect(to: deviceAddress)
    _socket = socket
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
    let prefix = _currentSocketAddress?.family == sa_family_t(AF_LOCAL)
      ? OcaLocalConnectionPrefix : OcaTcpConnectionPrefix
    return "\(prefix)/\(_currentPresentationAddress)"
  }

  override public var isDatagram: Bool { false }
}

#endif
