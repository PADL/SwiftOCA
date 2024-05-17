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
import CoreFoundation
import Foundation
import Logging
import SocketAddress
@_spi(SwiftOCAPrivate)
import SwiftOCA
import SystemPackage

@OcaDevice
public class Ocp1CFDeviceEndpoint: OcaBonjourRegistrableDeviceEndpoint,
  CustomStringConvertible
{
  let address: any SocketAddress
  let timeout: Duration
  let device: OcaDevice

  var socket: _CFSocketWrapper?
  var endpointRegistrationHandle: OcaDeviceEndpointRegistrar.Handle?

  public var controllers: [OcaController] {
    []
  }

  init(
    address: any SocketAddress,
    timeout: Duration = .seconds(15),
    device: OcaDevice = OcaDevice.shared
  ) async throws {
    self.address = address
    self.timeout = timeout
    self.device = device
    try await device.add(endpoint: self)
  }

  public nonisolated var description: String {
    "\(type(of: self))(address: \((try? address.presentationAddress) ?? "<unknown>"), timeout: \(timeout))"
  }

  public convenience init(
    address: Data,
    timeout: Duration = .seconds(15),
    device: OcaDevice = OcaDevice.shared
  ) async throws {
    let storage = try sockaddr_storage(bytes: Array(address))
    try await self.init(address: storage, timeout: timeout, device: device)
  }

  public convenience init(
    path: String,
    timeout: Duration = .seconds(15),
    device: OcaDevice = OcaDevice.shared
  ) async throws {
    let storage = try sockaddr_un(
      family: sa_family_t(AF_LOCAL),
      presentationAddress: path
    )
    try await self.init(address: storage, timeout: timeout, device: device)
  }

  public nonisolated var serviceType: OcaDeviceEndpointRegistrar.ServiceType {
    .none
  }

  public nonisolated var port: UInt16 {
    (try? address.port) ?? 0
  }

  public func run() async throws {
    if port != 0 {
      Task {
        endpointRegistrationHandle = try await OcaDeviceEndpointRegistrar.shared
          .register(endpoint: self, device: device)
      }
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

  // FIXME: should we have a shutdown method? we can't deregister in deinit as it
  // will create a strong ref to endpointRegistrationHandle

  deinit {
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
    try await _CFSocketWrapper(address: address, protocol: IPPROTO_TCP, options: .server)
  }

  private func makeNotificationSocket() async throws -> _CFSocketWrapper {
    try await _CFSocketWrapper(address: address, protocol: IPPROTO_UDP, options: .server)
  }

  override public nonisolated var serviceType: OcaDeviceEndpointRegistrar.ServiceType {
    .tcp
  }

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
      protocol: IPPROTO_UDP,
      options: .server
    )
    return socket
  }

  func sendOcp1EncodedMessage(_ message: Message) async throws {
    guard let socket else {
      throw Ocp1Error.notConnected
    }
    try socket.send(data: message.1, to: message.0)
  }

  override public nonisolated var serviceType: OcaDeviceEndpointRegistrar.ServiceType {
    .udp
  }

  func add(controller: ControllerType) async {}

  func remove(controller: ControllerType) async {
    _controllers[controller.peerAddress] = nil
  }
}

#endif
