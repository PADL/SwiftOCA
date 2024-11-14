//
//  Ocp1FlyingSocksDatagramDeviceEndpoint.swift
//
//  Copyright (c) 2022 Simon Whitty. All rights reserved.
//  Portions Copyright (c) 2023-2024 PADL Software Pty Ltd. All rights reserved.
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

#if os(macOS) || os(iOS)

import AsyncExtensions
import FlyingSocks
import Foundation
import Logging
import SwiftOCA

@OcaDevice
public final class Ocp1FlyingSocksDatagramDeviceEndpoint: OcaDeviceEndpointPrivate,
  OcaBonjourRegistrableDeviceEndpoint,
  CustomStringConvertible
{
  typealias ControllerType = Ocp1FlyingSocksDatagramController

  var _controllers = Set<ControllerType>()

  public var controllers: [OcaController] {
    Array(_controllers)
  }

  let pool: AsyncSocketPool

  private let address: SocketAddress
  let timeout: Duration
  let logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1FlyingSocksDatagramDeviceEndpoint")
  let device: OcaDevice

  #if canImport(dnssd)
  private var endpointRegistrationHandle: OcaDeviceEndpointRegistrar.Handle?
  #endif
  private(set) var socket: Socket?
  private var asyncSocket: AsyncSocket?

  private nonisolated var family: Int32 {
    switch address {
    case is sockaddr_in: AF_INET
    case is sockaddr_in6: AF_INET6
    case is sockaddr_un: AF_UNIX
    default: AF_UNSPEC
    }
  }

  public convenience init(
    address addressData: Data,
    timeout: Duration = .seconds(15),
    device: OcaDevice = OcaDevice.shared
  ) async throws {
    let address: any SocketAddress = try addressData.withUnsafeBytes { addressBytes in
      try addressBytes.withMemoryRebound(to: sockaddr.self) { address in
        switch address.baseAddress?.pointee.sa_family {
        case sa_family_t(AF_INET): return address.baseAddress!
          .withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        case sa_family_t(AF_INET6): return address.baseAddress!
          .withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
        case sa_family_t(AF_UNIX): return address.baseAddress!
          .withMemoryRebound(to: sockaddr_un.self, capacity: 1) { $0.pointee }
        default: throw SocketError.unsupportedAddress
        }
      }
    }

    try await self.init(address: address, timeout: timeout, device: device)
  }

  private init(
    address: SocketAddress,
    timeout: Duration = .seconds(15),
    device: OcaDevice = OcaDevice.shared
  ) async throws {
    self.address = address
    self.timeout = timeout
    self.device = device
    pool = Self.defaultPool()

    try await device.add(endpoint: self)
  }

  public nonisolated var description: String {
    withUnsafePointer(to: address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ in
        "\(type(of: self))(address: \(presentationAddress), timeout: \(timeout))"
      }
    }
  }

  private nonisolated var presentationAddress: String {
    withUnsafePointer(to: address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
        deviceAddressToString(sa)
      }
    }
  }

  func controller(
    for controllerAddress: any SocketAddress,
    interfaceIndex: UInt32?,
    localAddress: (any SocketAddress)?
  ) async throws -> ControllerType {
    var controller: ControllerType!

    controller = _controllers.first(where: { $0.matchesPeer(address: controllerAddress) })
    if controller == nil {
      controller = try await Ocp1FlyingSocksDatagramController(
        endpoint: self,
        peerAddress: controllerAddress,
        interfaceIndex: interfaceIndex,
        localAddress: localAddress
      )
      logger.info("datagram controller added", controller: controller)
      _controllers.insert(controller)
    }

    return controller
  }

  public func run() async throws {
    let socket = try await preparePoolAndSocket()
    logger.info("starting \(type(of: self)) on \(presentationAddress)")
    do {
      if port != 0 {
        #if canImport(dnssd)
        Task { endpointRegistrationHandle = try await OcaDeviceEndpointRegistrar.shared
          .register(endpoint: self, device: device)
        }
        #endif
      }
      try await _run(on: socket, pool: pool)
    } catch {
      logger.critical("server error: \(error.localizedDescription)")
      try? socket.close()
      throw error
    }
    try await device.remove(endpoint: self)
  }

  func preparePoolAndSocket() async throws -> Socket {
    do {
      try await pool.prepare()
      return try makeSocketAndListen()
    } catch {
      logger.critical("server error: \(error.localizedDescription)")
      throw error
    }
  }

  private func shutdown(timeout: Duration = .seconds(0)) async {
    #if canImport(dnssd)
    if let endpointRegistrationHandle {
      try? await OcaDeviceEndpointRegistrar.shared
        .deregister(handle: endpointRegistrationHandle)
    }
    #endif
    try? socket?.close()
  }

  func makeSocketAndListen() throws -> Socket {
    let socket = try Socket(domain: family, type: .datagram)
    try socket.setValue(true, for: .localAddressReuse)
    try socket.bind(to: address)
    return socket
  }

  private func _receiveMessages() async throws {
    precondition(asyncSocket != nil)

    repeat {
      do {
        for try await messagePdu in asyncSocket!
          .messages(maxMessageLength: Ocp1MaximumDatagramPduSize)
        {
          let controller = try await controller(
            for: messagePdu.peerAddress,
            interfaceIndex: messagePdu.interfaceIndex,
            localAddress: messagePdu.localAddress
          )
          do {
            let messages = try await controller.decodeMessages(from: messagePdu.bytes)
            for (message, rrq) in messages {
              try await controller.handle(for: self, message: message, rrq: rrq)
            }
          } catch {
            await unlockAndRemove(controller: controller)
          }
        }
      }
    } while !Task.isCancelled
  }

  func _run(on socket: Socket, pool: AsyncSocketPool) async throws {
    asyncSocket = try AsyncSocket(socket: socket, pool: pool)

    return try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await pool.run()
      }
      group.addTask {
        try await self._receiveMessages()
      }
      try await group.next()
    }
  }

  static func defaultPool(logger: Logging = .disabled) -> AsyncSocketPool {
    #if canImport(Darwin)
    return .kQueue(logger: logger)
    #elseif canImport(CSystemLinux)
    return .ePoll(logger: logger)
    #else
    return .poll(logger: logger)
    #endif
  }

  func sendOcp1EncodedMessage(_ message: (
    some SocketAddress,
    Data,
    UInt32?,
    (some SocketAddress)?
  )) async throws {
    guard let asyncSocket else {
      throw Ocp1Error.notConnected
    }
    try await asyncSocket.send(
      message: message.1,
      to: message.0,
      interfaceIndex: message.2,
      from: message.3
    )
  }

  public nonisolated var serviceType: OcaDeviceEndpointRegistrar.ServiceType {
    .udp
  }

  public nonisolated var port: UInt16 {
    var address = address
    return UInt16(bigEndian: withUnsafePointer(to: &address) { address in
      switch family {
      case AF_INET:
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
          sin.pointee.sin_port
        }
      case AF_INET6:
        address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
          sin6.pointee.sin6_port
        }
      default:
        0
      }
    })
  }

  func add(controller: ControllerType) async {}

  func remove(controller: ControllerType) async {
    _controllers.remove(controller)
  }
}

#endif
