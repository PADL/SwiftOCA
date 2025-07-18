//
//  Ocp1FlyingSocksStreamDeviceEndpoint.swift
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
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import SwiftOCA

@OcaDevice
public final class Ocp1FlyingSocksStreamDeviceEndpoint: OcaDeviceEndpointPrivate,
  OcaBonjourRegistrableDeviceEndpoint,
  CustomStringConvertible
{
  typealias ControllerType = Ocp1FlyingSocksStreamController

  public var controllers: [OcaController] {
    _controllers
  }

  let pool: AsyncSocketPool

  private let address: any SocketAddress
  let timeout: Duration
  let logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1FlyingSocksStreamDeviceEndpoint")
  let device: OcaDevice

  private var _controllers = [Ocp1FlyingSocksStreamController]()
  #if canImport(dnssd)
  private var _endpointRegistrarTask: Task<(), Error>?
  #endif

  private(set) var socket: Socket?

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
    timeout: Duration = OcaDevice.DefaultTimeout,
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

  public convenience init(
    path: String,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared
  ) async throws {
    let address = sockaddr_un.unix(path: path).makeStorage()
    try await self.init(address: address, timeout: timeout, device: device)
  }

  private init(
    address: some SocketAddress,
    timeout: Duration = OcaDevice.DefaultTimeout,
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

  public func run() async throws {
    let socket = try await preparePoolAndSocket()
    logger.info("starting \(type(of: self)) on \(presentationAddress)")
    do {
      if port != 0 {
        #if canImport(dnssd)
        Task { try await runBonjourEndpointRegistrar(for: device) }
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
    _endpointRegistrarTask?.cancel()
    #endif
    try? socket?.close()
  }

  func makeSocketAndListen() throws -> Socket {
    let socket = try Socket(domain: family)
    try socket.setValue(true, for: .localAddressReuse)
    #if canImport(Darwin)
    try socket.setValue(true, for: .noSIGPIPE)
    #endif
    try socket.bind(to: address)
    try socket.listen()
    return socket
  }

  func _run(on socket: Socket, pool: AsyncSocketPool) async throws {
    let asyncSocket = try AsyncSocket(socket: socket, pool: pool)

    return try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await pool.run()
      }
      group.addTask {
        try await self.listenForControllers(on: asyncSocket)
      }
      try await group.next()
    }
  }

  private func listenForControllers(on socket: AsyncSocket) async throws {
    #if compiler(>=5.9)
    if #available(macOS 14.0, iOS 17.0, tvOS 17.0, *) {
      try await listenForControllersDiscarding(on: socket)
    } else {
      try await listenForControllersFallback(on: socket)
    }
    #else
    try await listenForControllersFallback(on: socket)
    #endif
  }

  #if compiler(>=5.9)
  @available(macOS 14.0, iOS 17.0, tvOS 17.0, *)
  private func listenForControllersDiscarding(on socket: AsyncSocket) async throws {
    try await withThrowingDiscardingTaskGroup { group in
      for try await socket in socket.sockets {
        group.addTask {
          try await Ocp1FlyingSocksStreamController(endpoint: self, socket: socket)
            .handle(for: self)
        }
      }
    }
    throw SocketError.disconnected
  }
  #endif

  @available(macOS, deprecated: 17.0, renamed: "listenForControllersDiscarding(on:)")
  @available(iOS, deprecated: 17.0, renamed: "listenForControllersDiscarding(on:)")
  @available(tvOS, deprecated: 17.0, renamed: "listenForControllersDiscarding(on:)")
  private func listenForControllersFallback(on socket: AsyncSocket) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      for try await socket in socket.sockets {
        group.addTask {
          try await Ocp1FlyingSocksStreamController(endpoint: self, socket: socket)
            .handle(for: self)
        }
      }
    }
    throw SocketError.disconnected
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

  public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    .tcp
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

  func add(controller: ControllerType) async {
    _controllers.append(controller)
  }

  func remove(controller: ControllerType) async {
    _controllers.removeAll(where: { $0 == controller })
  }
}

#endif
