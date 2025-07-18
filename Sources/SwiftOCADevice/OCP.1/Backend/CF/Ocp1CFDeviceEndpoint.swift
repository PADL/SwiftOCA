//
// Copyright (c) 2024 PADL Software Pty Ltd
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

#if canImport(CoreFoundation)

import AsyncAlgorithms
import AsyncExtensions
#if swift(>=6.0)
internal import CoreFoundation
#else
@_implementationOnly import CoreFoundation
#endif
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import SocketAddress
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

@OcaDevice
public class Ocp1CFDeviceEndpoint: OcaBonjourRegistrableDeviceEndpoint,
  CustomStringConvertible
{
  let address: any SocketAddress
  let timeout: Duration
  let device: OcaDevice

  var socket: _CFSocketWrapper?
  #if canImport(dnssd)
  var _endpointRegistrarTask: Task<(), Error>?
  #endif

  public var controllers: [OcaController] {
    []
  }

  public nonisolated var description: String {
    "\(type(of: self))(address: \((try? address.presentationAddress) ?? "<unknown>"), timeout: \(timeout))"
  }

  public init(
    address: any SocketAddress,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared
  ) async throws {
    self.address = address
    self.timeout = timeout
    self.device = device
    try await device.add(endpoint: self)
  }

  public convenience init(
    address: Data,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared
  ) async throws {
    let address = try AnySocketAddress(bytes: Array(address))
    try await self.init(address: address, timeout: timeout, device: device)
  }

  public convenience init(
    path: String,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared
  ) async throws {
    let address = try AnySocketAddress(family: sa_family_t(AF_LOCAL), presentationAddress: path)
    try await self.init(address: address, timeout: timeout, device: device)
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

  deinit {
    #if canImport(dnssd)
    _endpointRegistrarTask?.cancel()
    #endif
    if address.family == AF_LOCAL { try? unlinkDomainSocket() }
  }
}

@OcaDevice
public final class Ocp1CFStreamDeviceEndpoint: Ocp1CFDeviceEndpoint,
  OcaDeviceEndpointPrivate
{
  typealias ControllerType = Ocp1CFStreamController

  let logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1CFStreamDeviceEndpoint")
  var notificationSocket: _CFSocketWrapper?

  var _controllers = [ControllerType]()

  override public var controllers: [OcaController] {
    _controllers
  }

  override public func run() async throws {
    logger.info("starting \(type(of: self)) on \(try! address.presentationAddress)")
    try await super.run()
    socket = try await makeSocketAndListen()
    notificationSocket = try await makeNotificationSocket()
    repeat {
      do {
        for try await client in socket!.acceptedSockets {
          Task {
            let controller =
              try await Ocp1CFStreamController(
                endpoint: self,
                socket: client,
                notificationSocket: notificationSocket!
              )
            await controller.handle(for: self)
          }
        }
      } catch {
        logger.info("received error \(error), bailing")
        break
      }
      if Task.isCancelled {
        logger.info("\(type(of: self)) cancelled, stopping")
        break
      }
    } while true
    socket = nil
    try await device.remove(endpoint: self)
  }

  private func makeSocketAndListen() async throws -> _CFSocketWrapper {
    try await _CFSocketWrapper(address: address, type: SwiftOCA.SOCK_STREAM, options: .server)
  }

  private func makeNotificationSocket() async throws -> _CFSocketWrapper {
    try await _CFSocketWrapper(address: address, type: SwiftOCA.SOCK_DGRAM, options: .server)
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
public class Ocp1CFDatagramDeviceEndpoint: Ocp1CFDeviceEndpoint,
  OcaDeviceEndpointPrivate
{
  typealias ControllerType = Ocp1CFDatagramController

  let logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1CFDatagramDeviceEndpoint")

  var _controllers = [AnySocketAddress: ControllerType]()

  override public var controllers: [OcaController] {
    _controllers.map(\.1)
  }

  func controller(for controllerAddress: AnySocketAddress) async throws
    -> ControllerType
  {
    var controller: ControllerType!

    controller = _controllers[controllerAddress]
    if controller == nil {
      controller = try await Ocp1CFDatagramController(
        endpoint: self,
        peerAddress: controllerAddress
      )
      logger.info("datagram controller added", controller: controller)
      _controllers[controllerAddress] = controller
    }

    return controller
  }

  override public func run() async throws {
    logger.info("starting \(type(of: self)) on \(try! address.presentationAddress)")
    try await super.run()
    socket = try await makeSocket()
    repeat {
      do {
        for try await messagePdu in socket!.receivedMessages {
          let controller =
            try await controller(for: AnySocketAddress(messagePdu.0))
          do {
            let messages = try await controller.decodeMessages(from: Array(messagePdu.1))
            for (message, rrq) in messages {
              try await controller.handle(for: self, message: message, rrq: rrq)
            }
          } catch {
            await unlockAndRemove(controller: controller)
          }
        }
      }
      if Task.isCancelled {
        logger.info("\(type(of: self)) cancelled, stopping")
        break
      }
    } while true
    socket = nil
    try await device.remove(endpoint: self)
  }

  private func makeSocket() async throws -> _CFSocketWrapper {
    let socket = try await _CFSocketWrapper(
      address: address,
      type: SwiftOCA.SOCK_DGRAM,
      options: .server
    )
    return socket
  }

  func sendOcp1EncodedMessage(_ message: CFSocket.Message) async throws {
    guard let socket else {
      throw Ocp1Error.notConnected
    }
    try socket.send(data: message.1, to: message.0)
  }

  #if canImport(dnssd)
  override public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    .udp
  }
  #endif

  func add(controller: ControllerType) async {}

  func remove(controller: ControllerType) async {
    _controllers[controller.peerAddress] = nil
  }
}

#endif
