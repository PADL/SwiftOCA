//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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


#if os(macOS) || os(iOS) || os(Windows) || !NonEmbeddedBuild

import AsyncExtensions
import FlyingSocks
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
@_spi(SwiftOCAPrivate)
import SwiftOCA
import SystemPackage
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
#endif

@available(*, deprecated, renamed: "OcaFlyingSocksStreamDeviceEndpoint")
public typealias Ocp1FlyingSocksStreamDeviceEndpoint = OcaFlyingSocksStreamDeviceEndpoint

@OcaDevice
public final class OcaFlyingSocksStreamDeviceEndpoint: OcaDeviceEndpointPrivate,
  OcaBonjourRegistrableDeviceEndpoint,
  CustomStringConvertible
{
  package typealias ControllerType = OcaFlyingSocksStreamController

  public var controllers: [OcaController] {
    _controllers
  }

  let pool: any AsyncSocketPool = SocketPool.make()

  private let address: any SocketAddress
  package let timeout: Duration
  package let device: OcaDevice
  package let logger: Logger
  package let controlProtocol: OcaControlProtocol
  package nonisolated(unsafe) var enableMessageTracing = false

  private var _controllers = [OcaFlyingSocksStreamController]()
  #if canImport(dnssd)
  private var _endpointRegistrarTask: Task<(), Error>?
  #endif


  private nonisolated var family: sa_family_t {
    address.family
  }

  public convenience init(
    address addressData: Data,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    controlProtocol: OcaControlProtocol = .ocp1,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.OcaFlyingSocksStreamDeviceEndpoint")
  ) async throws {
    let address = try FlyingSocks.AnySocketAddress(data: addressData)
    try await self.init(
      address: address,
      timeout: timeout,
      device: device,
      controlProtocol: controlProtocol,
      logger: logger
    )
  }

  public convenience init(
    path: String,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    controlProtocol: OcaControlProtocol = .ocp1,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.OcaFlyingSocksStreamDeviceEndpoint")
  ) async throws {
    let address = sockaddr_un.unix(path: path).makeStorage()
    try await self.init(
      address: address,
      timeout: timeout,
      device: device,
      controlProtocol: controlProtocol,
      logger: logger
    )
  }

  private init(
    address: some SocketAddress,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    controlProtocol: OcaControlProtocol = .ocp1,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.OcaFlyingSocksStreamDeviceEndpoint")
  ) async throws {
    self.address = address
    self.timeout = timeout
    self.device = device
    self.controlProtocol = controlProtocol
    self.logger = logger

    try await device.add(endpoint: self)
  }

  public nonisolated var description: String {
    "\(type(of: self))(address: \(presentationAddress), timeout: \(timeout))"
  }

  private nonisolated var presentationAddress: String {
    address.makeStorage()._presentationAddress
  }

  public func run() async throws {
    let socket = try await bind()
    logger.info("starting \(type(of: self)) (\(controlProtocol)) on \(presentationAddress)")
    #if canImport(dnssd)
    if port != 0 { _endpointRegistrarTask = makeBonjourRegistrarTask(for: device) }
    defer { _endpointRegistrarTask?.cancel() }
    #endif
    do {
      try await serve(on: socket)
    } catch {
      try? socket.close()
      // cancelling the endpoint stops the pool's event queue under its wait, which on
      // Darwin then fails with EBADF, so treat whatever it throws as shutdown
      guard !Task.isCancelled else {
        try? await device.remove(endpoint: self)
        throw CancellationError()
      }
      logger.critical("server error for \(presentationAddress): \(error)")
      throw error
    }
    try await device.remove(endpoint: self)
  }

  /// Prepares the socket pool and binds a socket to the endpoint's address. Tests call
  /// this and `serve(on:)` separately, to learn an ephemeral port before serving.
  func bind() async throws -> Socket {
    do {
      try await pool.prepare()
      return try makeSocket()
    } catch {
      logger.critical("server error for \(presentationAddress): \(error)")
      throw error
    }
  }


  private nonisolated func unlinkDomainSocket() throws {
    if family == AF_UNIX {
      try unlinkSocketFile(at: presentationAddress)
    }
  }

  private func makeSocket() throws -> Socket {
    // a socket file left behind by an earlier endpoint would make bind fail; it must be
    // removed before binding, as unlinking afterwards removes the file clients connect to
    try unlinkDomainSocket()
    let socket = try Socket(domain: Int32(family))
    try socket.setValue(true, for: .localAddressReuse)
    #if canImport(Darwin)
    try socket.setValue(true, for: .noSIGPIPE)
    #endif
    if address.family == sa_family_t(AF_INET6) { try socket.setIPv6Only() }
    try socket.bind(to: address)
    try socket.listen()
    return socket
  }

  /// Runs the socket pool's event loop alongside the accept loop, until either ends.
  func serve(on socket: Socket) async throws {
    let pool = pool
    let listener = try AsyncSocket(socket: socket, pool: pool)
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { try await pool.run() }
      group.addTask { try await self.acceptControllers(from: listener) }
      try await group.next()
    }
  }

  private func acceptControllers(from listener: AsyncSocket) async throws {
    try await withThrowingDiscardingTaskGroup { group in
      for try await socket in listener.sockets {
        group.addTask {
          try await OcaFlyingSocksStreamController(endpoint: self, socket: socket)
            .handle(for: self)
        }
      }
    }
    throw SocketError.disconnected
  }


  public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    OcaNetworkAdvertisingServiceType.tcp.withControlProtocol(controlProtocol)
  }

  public nonisolated var port: UInt16 {
    address.port
  }

  package func add(controller: ControllerType) async {
    _controllers.append(controller)
  }

  package func remove(controller: ControllerType) async {
    _controllers.removeAll(where: { $0 == controller })
  }

  deinit {
    if family == AF_UNIX { try? unlinkDomainSocket() }
  }
}

#endif
