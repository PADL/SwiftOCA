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

@AES70Device
public class AES70OCP1IORingDeviceEndpoint: AES70BonjourRegistrableDeviceEndpoint,
    CustomStringConvertible
{
    let address: any SocketAddress
    let timeout: TimeInterval
    let ring: IORing

    var socket: Socket?
    var endpointRegistrationHandle: AES70DeviceEndpointRegistrar.Handle?

    public var controllers: [AES70Controller] {
        []
    }

    init(
        address: any SocketAddress,
        timeout: TimeInterval = 15
    ) async throws {
        self.address = address
        self.timeout = timeout
        ring = IORing.shared
        try await AES70Device.shared.add(endpoint: self)
    }

    public nonisolated var description: String {
        "\(type(of: self))(address: \((try? address.presentationAddress) ?? "<unknown>"), timeout: \(timeout))"
    }

    public convenience init(
        address: Data,
        timeout: TimeInterval = 15
    ) async throws {
        let storage = try sockaddr_storage(bytes: Array(address))
        try await self.init(address: storage, timeout: timeout)
    }

    public convenience init(
        path: String,
        timeout: TimeInterval = 15
    ) async throws {
        let storage = try sockaddr_un(
            family: sa_family_t(AF_LOCAL),
            presentationAddress: path
        )
        try await self.init(address: storage, timeout: timeout)
    }

    public nonisolated var serviceType: AES70DeviceEndpointRegistrar.ServiceType {
        .tcp
    }

    public nonisolated var port: UInt16 {
        (try? address.port) ?? 0
    }

    public func run() async throws {
        if port != 0 {
            Task {
                endpointRegistrationHandle = try await AES70DeviceEndpointRegistrar.shared
                    .register(endpoint: self)
            }
        }
    }

    fileprivate func shutdown(timeout: TimeInterval = 0) async {
        if let endpointRegistrationHandle {
            try? await AES70DeviceEndpointRegistrar.shared
                .deregister(handle: endpointRegistrationHandle)
        }
    }
}

@AES70Device
public final class AES70OCP1IORingStreamDeviceEndpoint: AES70OCP1IORingDeviceEndpoint,
    AES70DeviceEndpointPrivate
{
    typealias ControllerType = AES70OCP1IORingStreamController

    let logger = Logger(label: "com.padl.SwiftOCADevice.AES70OCP1IORingStreamDeviceEndpoint")

    var _controllers = [ControllerType]()

    override public var controllers: [AES70Controller] {
        _controllers
    }

    override public func run() async throws {
        logger.info("starting \(type(of: self)) on \(try! address.presentationAddress)")
        try await super.run()
        let socket = try makeSocketAndListen()
        self.socket = socket
        repeat {
            do {
                let clients: AnyAsyncSequence<Socket> = try await socket.accept()
                do {
                    for try await client in clients {
                        Task {
                            let controller =
                                try await AES70OCP1IORingStreamController(socket: client)
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

    func makeSocketAndListen() throws -> Socket {
        let socket = try Socket(ring: ring, domain: address.family, type: SOCK_STREAM, protocol: 0)

        try socket.setReuseAddr()
        try socket.setTcpNoDelay()
        try socket.bind(to: address)
        try socket.listen()

        return socket
    }

    override public nonisolated var serviceType: AES70DeviceEndpointRegistrar.ServiceType {
        .tcp
    }

    func add(controller: ControllerType) async {
        _controllers.append(controller)
    }

    func remove(controller: ControllerType) async {
        _controllers.removeAll(where: { $0 == controller })
    }
}

@AES70Device
public class AES70OCP1IORingDatagramDeviceEndpoint: AES70OCP1IORingDeviceEndpoint,
    AES70DeviceEndpointPrivate
{
    typealias ControllerType = AES70OCP1IORingDatagramController

    let logger = Logger(label: "com.padl.SwiftOCADevice.AES70OCP1IORingDatagramDeviceEndpoint")

    var _controllers = [AnySocketAddress: ControllerType]()

    override public var controllers: [AES70Controller] {
        _controllers.map(\.1)
    }

    func controller(for controllerAddress: AnySocketAddress) async throws
        -> ControllerType
    {
        var controller: ControllerType!

        controller = _controllers[controllerAddress]
        if controller == nil {
            controller = try await AES70OCP1IORingDatagramController(
                endpoint: self,
                peerAddress: controllerAddress
            )
            logger.info("new datagram client \(controller!)")
            logger.controllerAdded(controller)
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
                    Task { @AES70Device in
                        let controller =
                            try await self.controller(for: AnySocketAddress(bytes: messagePdu.name))
                        do {
                            let messages = try await controller.decodeMessages(from: messagePdu.buffer)
                            for (message, rrq) in messages {
                                try await controller.handle(for: self, message: message, rrq: rrq)
                            }
                        } catch {
                            await remove(controller: controller)
                        }
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

    func makeSocket() throws -> Socket {
        let socket = try Socket(ring: ring, domain: address.family, type: SOCK_DGRAM, protocol: 0)

        try socket.bind(to: address)

        return socket
    }

    func sendMessagePdu(_ messagePdu: Message) async throws {
        guard let socket else {
            throw Ocp1Error.notConnected
        }
        try await socket.sendMessage(messagePdu)
    }

    override public nonisolated var serviceType: AES70DeviceEndpointRegistrar.ServiceType {
        .udp
    }

    func add(controller: ControllerType) async {}

    func remove(controller: ControllerType) async {
        await AES70Device.shared.unlockAll(controller: controller)
        _controllers[controller.peerAddress] = nil
    }
}

#endif
