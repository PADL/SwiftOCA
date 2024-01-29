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
import Foundation
@_implementationOnly
import IORing
@_implementationOnly
import IORingUtils
import Logging
import SwiftOCA

@OcaDevice
public class Ocp1IORingDeviceEndpoint: OcaBonjourRegistrableDeviceEndpoint,
    CustomStringConvertible
{
    let address: any SocketAddress
    let timeout: Duration
    let device: OcaDevice
    let ring: IORing

    var socket: Socket?
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
        ring = IORing.shared
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
        }
    }

    fileprivate func shutdown(timeout: Duration = .seconds(0)) async {
        if let endpointRegistrationHandle {
            try? await OcaDeviceEndpointRegistrar.shared
                .deregister(handle: endpointRegistrationHandle)
        }
    }
}

@OcaDevice
public final class Ocp1IORingStreamDeviceEndpoint: Ocp1IORingDeviceEndpoint,
    OcaDeviceEndpointPrivate
{
    typealias ControllerType = Ocp1IORingStreamController

    let logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1IORingStreamDeviceEndpoint")
    var notificationSocket: Socket?

    var _controllers = [ControllerType]()

    override public var controllers: [OcaController] {
        _controllers
    }

    override public func run() async throws {
        logger.info("starting \(type(of: self)) on \(try! address.presentationAddress)")
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
                        Task {
                            let controller =
                                try await Ocp1IORingStreamController(
                                    socket: client,
                                    notificationSocket: notificationSocket
                                )
                            await controller.handle(for: self)
                        }
                    }
                } catch Errno.invalidArgument {
                    logger.warning(
                        "invalid argument when accepting connections, check kernel version supports multishot accept with io_uring"
                    )
                    break
                }
            } catch Errno.canceled {
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
    }

    private func makeSocketAndListen() throws -> Socket {
        let socket = try Socket(ring: ring, domain: address.family, type: Glibc.SOCK_STREAM, protocol: 0)

        try socket.setReuseAddr()
        try socket.setTcpNoDelay()
        try socket.bind(to: address)
        try socket.listen()

        return socket
    }

    private func makeNotificationSocket() throws -> Socket {
        try Socket(ring: ring, domain: address.family, type: Glibc.SOCK_DGRAM, protocol: 0)
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
public class Ocp1IORingDatagramDeviceEndpoint: Ocp1IORingDeviceEndpoint,
    OcaDeviceEndpointPrivate
{
    typealias ControllerType = Ocp1IORingDatagramController

    let logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1IORingDatagramDeviceEndpoint")

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
            controller = try await Ocp1IORingDatagramController(
                endpoint: self,
                peerAddress: controllerAddress
            )
            logger.info("datagram controller added", controller: controller)
            _controllers[controllerAddress] = controller
        }

        return controller
    }

    static let MaximumPduSize = 1500

    override public func run() async throws {
        logger.info("starting \(type(of: self)) on \(try! address.presentationAddress)")
        try await super.run()
        let socket = try makeSocket()
        self.socket = socket
        repeat {
            do {
                let messagePdus = try await socket.receiveMessages(count: Self.MaximumPduSize)

                for try await messagePdu in messagePdus {
                    let controller =
                        try await controller(for: AnySocketAddress(bytes: messagePdu.name))
                    do {
                        let messages = try await controller
                            .decodeMessages(from: messagePdu.buffer)
                        for (message, rrq) in messages {
                            try await controller.handle(for: self, message: message, rrq: rrq)
                        }
                    } catch {
                        await unlockAndRemove(controller: controller)
                    }
                }
            } catch Errno.canceled {}
            if Task.isCancelled {
                logger.info("\(type(of: self)) cancelled, stopping")
                break
            }
        } while true
        self.socket = nil
    }

    private func makeSocket() throws -> Socket {
        let socket = try Socket(ring: ring, domain: address.family, type: Glibc.SOCK_DGRAM, protocol: 0)

        try socket.bind(to: address)

        return socket
    }

    func sendOcp1EncodedMessage(_ message: Message) async throws {
        guard let socket else {
            throw Ocp1Error.notConnected
        }
        try await socket.sendMessage(message)
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
