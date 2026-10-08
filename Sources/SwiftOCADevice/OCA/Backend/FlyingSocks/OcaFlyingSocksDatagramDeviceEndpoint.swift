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


#if os(macOS) || os(iOS) || !NonEmbeddedBuild

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
#endif

@available(*, deprecated, renamed: "OcaFlyingSocksDatagramDeviceEndpoint")
public typealias Ocp1FlyingSocksDatagramDeviceEndpoint = OcaFlyingSocksDatagramDeviceEndpoint

@OcaDevice
public final class OcaFlyingSocksDatagramDeviceEndpoint: OcaDeviceEndpointPrivate,
  OcaBonjourRegistrableDeviceEndpoint,
  CustomStringConvertible
{
  package typealias ControllerType = OcaFlyingSocksDatagramController

  var _controllers = Set<ControllerType>()

  public var controllers: [OcaController] {
    Array(_controllers)
  }

  let pool: any AsyncSocketPool = SocketPool.make()

  private let address: SocketAddress
  package let timeout: Duration
  package let device: OcaDevice
  package let controlProtocol: OcaControlProtocol
  package let logger: Logger
  package nonisolated(unsafe) var enableMessageTracing = false

  private var asyncSocket: AsyncSocket?
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
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.OcaFlyingSocksDatagramDeviceEndpoint")
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

  private init(
    address: SocketAddress,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    controlProtocol: OcaControlProtocol = .ocp1,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.OcaFlyingSocksDatagramDeviceEndpoint")
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

  private func controller(
    for controllerAddress: any SocketAddress,
    interfaceIndex: UInt32?,
    localAddress: (any SocketAddress)?
  ) -> ControllerType {
    if let controller = _controllers.first(where: { $0.matchesPeer(address: controllerAddress) }) {
      return controller
    }
    let controller = OcaFlyingSocksDatagramController(
      endpoint: self,
      peerAddress: controllerAddress,
      interfaceIndex: interfaceIndex,
      localAddress: localAddress
    )
    logger.info("datagram controller added", controller: controller)
    _controllers.insert(controller)
    return controller
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
    // removed before binding, as unlinking afterwards removes the file clients send to
    try unlinkDomainSocket()
    let socket = try Socket(domain: Int32(family), type: .datagram)
    try socket.setValue(true, for: .localAddressReuse)
    if address.family == sa_family_t(AF_INET6) { try socket.setIPv6Only() }
    try socket.bind(to: address)
    return socket
  }

  /// Runs the socket pool's event loop alongside the receive loop, until either ends.
  func serve(on socket: Socket) async throws {
    let pool = pool
    let asyncSocket = try AsyncSocket(socket: socket, pool: pool)
    self.asyncSocket = asyncSocket
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { try await pool.run() }
      group.addTask { try await self.receiveMessages(from: asyncSocket) }
      try await group.next()
    }
  }

  private func receiveMessages(from socket: AsyncSocket) async throws {
    let maxMessageLength = min(maximumPduSize + 1, Ocp1MaximumDatagramPduSize)
    while !Task.isCancelled {
      for try await messagePdu in socket.messages(maxMessageLength: maxMessageLength) {
        let controller = controller(
          for: messagePdu.peerAddress,
          interfaceIndex: messagePdu.interfaceIndex,
          localAddress: messagePdu.localAddress
        )
        do {
          try await handle(messagePduData: messagePdu.payload, from: controller)
        } catch {
          await unlockAndRemove(controller: controller)
        }
      }
    }
  }


  func sendOcp1EncodedMessage(_ messagePdu: AsyncSocket.Message) async throws {
    guard let asyncSocket else {
      throw Ocp1Error.notConnected
    }
    try await asyncSocket.send(message: messagePdu)
  }

  public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    OcaNetworkAdvertisingServiceType.udp.withControlProtocol(controlProtocol)
  }

  public nonisolated var port: UInt16 {
    address.port
  }

  package func add(controller: ControllerType) async {}

  package func remove(controller: ControllerType) async {
    _controllers.remove(controller)
  }

  deinit {
    if family == AF_UNIX { try? unlinkDomainSocket() }
  }
}

#endif
