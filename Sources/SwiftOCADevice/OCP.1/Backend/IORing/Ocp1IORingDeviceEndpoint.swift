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

import AsyncAlgorithms
@preconcurrency
import AsyncExtensions
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Glibc

#if swift(>=6.0)
public import IORing
internal import IORingUtils
#else
public import IORing
@_implementationOnly import IORingUtils
#endif

import Logging
import SocketAddress
@_spi(SwiftOCAPrivate)
import SwiftOCA
import struct SystemPackage.Errno

@OcaDevice
public class Ocp1IORingDeviceEndpoint: OcaBonjourRegistrableDeviceEndpoint,
  CustomStringConvertible
{
  let address: any SocketAddress
  let timeout: Duration
  let device: OcaDevice
  let logger: Logger
  let ring: IORing
  nonisolated(unsafe) var enableMessageTracing = false

  var socket: Socket?
  #if canImport(dnssd)
  private var _endpointRegistrarTask: Task<(), Error>?
  #endif

  public var controllers: [OcaController] {
    []
  }

  public init(
    address: any SocketAddress,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1IORingDeviceEndpoint"),
    ring: IORing = .shared
  ) async throws {
    self.address = address
    self.timeout = timeout
    self.device = device
    self.logger = logger
    self.ring = ring
    try await device.add(endpoint: self)
  }

  public nonisolated var description: String {
    "\(type(of: self))(address: \((try? address.presentationAddress) ?? "<unknown>"), timeout: \(timeout))"
  }

  public convenience init(
    address: Data,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1IORingDeviceEndpoint")
  ) async throws {
    let storage = try sockaddr_storage(bytes: Array(address))
    try await self.init(address: storage, timeout: timeout, device: device, logger: logger)
  }

  public convenience init(
    path: String,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1IORingDeviceEndpoint")
  ) async throws {
    let storage = try sockaddr_un(
      family: sa_family_t(AF_LOCAL),
      presentationAddress: path
    )
    try await self.init(address: storage, timeout: timeout, device: device, logger: logger)
  }

  #if canImport(dnssd)
  public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    .none
  }
  #endif

  public nonisolated var port: UInt16 {
    (try? address.port) ?? 0
  }

  public func run() async throws {
    if port != 0 {
      #if canImport(dnssd)
      _endpointRegistrarTask = Task { try await runBonjourEndpointRegistrar(for: device) }
      #endif
    } else if address.family == AF_LOCAL {
      try? unlinkDomainSocket()
    }
  }

  private nonisolated func unlinkDomainSocket() throws {
    if let presentationAddress = try? address.presentationAddress {
      if unlink(presentationAddress) < 0 {
        throw Errno(rawValue: errno)
      }
    }
  }

  public func setMessageTracingEnabled(to value: Bool) {
    enableMessageTracing = value
  }

  deinit {
    #if canImport(dnssd)
    _endpointRegistrarTask?.cancel()
    #endif
    if address.family == AF_LOCAL { try? unlinkDomainSocket() }
  }
}

@OcaDevice
public final class Ocp1IORingStreamDeviceEndpoint: Ocp1IORingDeviceEndpoint,
  OcaDeviceEndpointPrivate
{
  typealias ControllerType = Ocp1IORingStreamController

  var notificationSocket: Socket?

  var _controllers = [ControllerType]()

  override public var controllers: [OcaController] {
    _controllers
  }

  override public func run() async throws {
    logger.info("starting \(type(of: self)) on \(address.unsafelyUnwrappedPresentationAddress)")
    try await super.run()
    let socket = try makeSocketAndListen()
    self.socket = socket
    let notificationSocket = try makeNotificationSocket()
    self.notificationSocket = notificationSocket
    repeat {
      do {
        let clients: AnyAsyncSequence<Socket> = try await socket.accept()
        do {
          for try await client in clients {
            Task { [weak self] in
              guard let self else { return }
              let controller =
                try await Ocp1IORingStreamController(
                  endpoint: self,
                  socket: client,
                  notificationSocket: notificationSocket
                )
              await controller.handle(for: self)
            }
          }
        } catch let error where error as? Errno == Errno.invalidArgument {
          logger.warning(
            "invalid argument when accepting connections, check kernel version supports multishot accept with io_uring"
          )
          break
        }
      } catch let error where error as? Errno == Errno.canceled {
        logger.debug("received cancelation, trying to accept() again")
      } catch {
        logger.info("received error \(error), bailing")
        break
      }
      if Task.isCancelled {
        logger.info("\(type(of: self)) cancelled, stopping")
        break
      }
    } while true
    self.socket = nil
    try await device.remove(endpoint: self)
  }

  private func makeSocketAndListen() throws -> Socket {
    let socket = try Socket(
      ring: ring,
      domain: address.family,
      type: Glibc.SOCK_STREAM,
      protocol: 0
    )

    do {
      switch address.family {
      case sa_family_t(AF_INET6):
        try socket.setIPv6Only()
        fallthrough
      case sa_family_t(AF_INET):
        try socket.setReuseAddr()
        try socket.setTcpNoDelay()
      default:
        break
      }
      try socket.bind(to: address)
      try socket.listen()
    } catch {
      logger.warning("error \(error), when setting up socket for listening")
      throw error
    }

    return socket
  }

  private func makeNotificationSocket() throws -> Socket {
    try Socket(ring: ring, domain: address.family, type: Glibc.SOCK_DGRAM, protocol: 0)
  }

  #if canImport(dnssd)
  override public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    .tcp
  }
  #endif

  func add(controller: ControllerType) async {
    _controllers.append(controller)
  }

  func remove(controller: ControllerType) async {
    _controllers.removeAll(where: { $0 == controller })
  }
}

@OcaDevice
public class Ocp1IORingDatagramDeviceEndpoint: Ocp1IORingDeviceEndpoint,
  OcaDeviceEndpointPrivate
{
  typealias ControllerType = Ocp1IORingDatagramController

  private let _bufferCount: Int?
  var _controllers = [AnySocketAddress: ControllerType]()

  override public var controllers: [OcaController] {
    _controllers.map(\.1)
  }

  public init(
    address: any SocketAddress,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1IORingDeviceEndpoint"),
    bufferCount: Int? = nil,
    ring: IORing = .shared
  ) async throws {
    _bufferCount = bufferCount
    try await super.init(
      address: address,
      timeout: timeout,
      device: device,
      logger: logger,
      ring: ring
    )
  }

  public convenience init(
    address: Data,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1IORingDeviceEndpoint"),
    bufferCount: Int? = nil
  ) async throws {
    let storage = try sockaddr_storage(bytes: Array(address))
    try await self.init(
      address: storage,
      timeout: timeout,
      device: device,
      logger: logger,
      bufferCount: bufferCount
    )
  }

  public convenience init(
    path: String,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1IORingDeviceEndpoint"),
    bufferCount: Int? = nil
  ) async throws {
    let storage = try sockaddr_un(
      family: sa_family_t(AF_LOCAL),
      presentationAddress: path
    )
    try await self.init(
      address: storage,
      timeout: timeout,
      device: device,
      logger: logger,
      bufferCount: bufferCount
    )
  }

  func controller(for controllerAddress: AnySocketAddress) -> ControllerType {
    var controller: ControllerType!

    controller = _controllers[controllerAddress]
    if controller == nil {
      controller = Ocp1IORingDatagramController(
        endpoint: self,
        peerAddress: controllerAddress
      )

      logger.info("datagram controller added", controller: controller)
      _controllers[controllerAddress] = controller
    }

    return controller
  }

  override public func run() async throws {
    logger.info("starting \(type(of: self)) on \(address.unsafelyUnwrappedPresentationAddress)")
    try await super.run()

    let socket = try makeSocket()
    self.socket = socket

    var receiveBufferSize: Int!

    if address.family == AF_UNIX {
      receiveBufferSize = try? Int(socket.getIntegerOption(option: SO_RCVBUF))
    }
    if receiveBufferSize == nil {
      receiveBufferSize = Ocp1MaximumDatagramPduSize
    }

    repeat {
      do {
        let messagePdus = try await socket.receiveMessages(
          count: receiveBufferSize,
          capacity: _bufferCount
        )

        for try await messagePdu in messagePdus {
          var controller: ControllerType!

          do {
            controller = try self.controller(for: AnySocketAddress(bytes: messagePdu.name))
            try await handle(messagePduData: messagePdu.buffer, from: controller)
          } catch {
            if let controller { await unlockAndRemove(controller: controller) }
          }
        }
      } catch let error as Errno {
        // if the IORing has not being sized properly we may receive noBufferSpace
        guard error == Errno.canceled || error == Errno.noBufferSpace else { throw error }
      } catch {
        logger
          .error(
            "unexpected error \(error) running \(type(of: self)) event loop on \(address.unsafelyUnwrappedPresentationAddress); no longer servicing requests"
          )
        throw error
      }
    } while !Task.isCancelled

    self.socket = nil
    try await device.remove(endpoint: self)
  }

  private func makeSocket() throws -> Socket {
    let socket = try Socket(
      ring: ring,
      domain: address.family,
      type: Glibc.SOCK_DGRAM,
      protocol: 0
    )

    if address.family == sa_family_t(AF_INET6) { try socket.setIPv6Only() }
    try socket.bind(to: address)

    return socket
  }

  func sendOcp1EncodedMessage(_ message: Message) async throws {
    guard let socket else {
      throw Ocp1Error.notConnected
    }
    try await socket.sendMessage(message)
  }

  override public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    .udp
  }

  func add(controller: ControllerType) async {}

  func remove(controller: ControllerType) async {
    _controllers[controller.peerAddress] = nil
  }
}

#endif
