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

import Foundation

// @_implementationOnly
import IORing

// @_implementationOnly
import IORingFoundation

// @_implementationOnly
import IORingUtils
import SocketAddress
import SystemPackage

fileprivate extension Errno {
  var mappedError: Error {
    switch self {
    case .connectionRefused:
      fallthrough
    case .connectionReset:
      fallthrough
    case .brokenPipe:
      return Ocp1Error.notConnected
    default:
      return self
    }
  }
}

public class Ocp1IORingConnection: Ocp1Connection {
  fileprivate let deviceAddress: any SocketAddress
  fileprivate var socket: Socket?
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
  ) {
    deviceAddress = socketAddress
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

  override func connectDevice() async throws {
    let socket = try Socket(
      ring: IORing.shared,
      domain: deviceAddress.family,
      type: __socket_type(UInt32(type)),
      protocol: 0
    )
    if type == SOCK_STREAM, deviceAddress.family == AF_INET || deviceAddress.family == AF_INET6 {
      try socket.setTcpNoDelay()
    }
    try await socket.connect(to: deviceAddress)
    self.socket = socket
    try await super.connectDevice()
  }

  override public func disconnectDevice(clearObjectCache: Bool) async throws {
    socket = nil
    try await super.disconnectDevice(clearObjectCache: clearObjectCache)
  }

  fileprivate func withMappedError<T: Sendable>(
    _ block: (_ socket: Socket) async throws
      -> T
  ) async throws -> T {
    guard let socket else {
      throw Ocp1Error.notConnected
    }

    do {
      return try await block(socket)
    } catch let error as Errno {
      throw error.mappedError
    }
  }
}

public final class Ocp1IORingDatagramConnection: Ocp1IORingConnection {
  override public var heartbeatTime: Duration {
    .seconds(1)
  }

  override fileprivate var type: Int32 {
    SOCK_DGRAM
  }

  override public func read(_ length: Int) async throws -> Data {
    // read maximum PDU size
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
    let prefix = deviceAddress
      .family == AF_LOCAL ? OcaLocalConnectionPrefix : OcaUdpConnectionPrefix
    return "\(prefix)/\(deviceAddressToString(deviceAddress))"
  }

  override public var isDatagram: Bool { true }
}

public final class Ocp1IORingStreamConnection: Ocp1IORingConnection {
  override fileprivate var type: Int32 {
    SOCK_STREAM
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
    let prefix = deviceAddress
      .family == AF_LOCAL ? OcaLocalConnectionPrefix : OcaTcpConnectionPrefix
    return "\(prefix)/\(deviceAddressToString(deviceAddress))"
  }

  override public var isDatagram: Bool { false }
}

private func deviceAddressToString(_ deviceAddress: any SocketAddress) -> String {
  do {
    return try deviceAddress.presentationAddress
  } catch {
    return "<unknown>"
  }
}

#endif
