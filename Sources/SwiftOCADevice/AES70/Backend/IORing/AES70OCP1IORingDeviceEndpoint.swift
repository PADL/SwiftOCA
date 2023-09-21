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
import Foundation
@_implementationOnly
import IORing
@_implementationOnly
import IORingUtils
import SwiftOCA

@AES70Device
public class AES70OCP1IORingDeviceEndpoint: AES70DeviceEndpoint {
    let address: any SocketAddress
    let timeout: TimeInterval
    let depth: Int
    let ring: IORing

    public var controllers: [AES70Controller] {
        []
    }

    init(
        address: any SocketAddress,
        timeout: TimeInterval = 15,
        depth: Int = 64
    ) async throws {
        self.address = address
        self.timeout = timeout
        self.depth = depth
        ring = try IORing(depth: depth)
        try await AES70Device.shared.add(endpoint: self)
    }

    public convenience init(
        address: Data,
        timeout: TimeInterval = 15,
        depth: Int = 64
    ) async throws {
        let storage = try sockaddr_storage(bytes: Array(address))
        try await self.init(address: storage, timeout: timeout, depth: depth)
    }

    public convenience init(
        path: String,
        timeout: TimeInterval = 15,
        depth: Int = 64
    ) async throws {
        let storage = try sockaddr_un(
            family: sa_family_t(AF_LOCAL),
            presentationAddress: path
        )
        try await self.init(address: storage, timeout: timeout, depth: depth)
    }

    func handle(
        controller: any AES70OCP1IORingControllerPrivate,
        message: Ocp1Message,
        rrq: Bool
    ) async throws {
        var response: Ocp1Response?

        await controller.updateLastMessageReceivedTime()

        switch message {
        case let command as Ocp1Command:
            let commandResponse = await AES70Device.shared.handleCommand(
                command,
                timeout: timeout,
                from: controller
            )
            response = Ocp1Response(
                handle: command.handle,
                statusCode: commandResponse.statusCode,
                parameters: commandResponse.parameters
            )
        case let keepAlive as Ocp1KeepAlive1:
            await controller
                .setKeepAliveInterval(UInt64(keepAlive.heartBeatTime) * NSEC_PER_SEC)
        case let keepAlive as Ocp1KeepAlive2:
            await controller
                .setKeepAliveInterval(UInt64(keepAlive.heartBeatTime) * NSEC_PER_MSEC)
        default:
            throw Ocp1Error.invalidMessageType
        }

        if rrq, let response {
            try await controller.sendMessage(response, type: .ocaRsp)
        }
    }
}

@AES70Device
public final class AES70OCP1IORingStreamDeviceEndpoint: AES70OCP1IORingDeviceEndpoint {
    var _controllers = [AES70OCP1IORingStreamController]()

    private(set) var state: (socket: Socket, task: Task<(), Error>)?

    override public var controllers: [AES70Controller] {
        _controllers
    }

    public func start() async throws {
        let socket = try makeSocketAndListen()
        let task = Task {
            let clients = try await socket.accept()
            for try await client in clients {
                let controller = try await AES70OCP1IORingStreamController(socket: client)
                // FIXME: use task group?
                Task { await handleController(controller) }
            }
        }
        state = (socket: socket, task: task)
    }

    public func stop(timeout: TimeInterval = 0) async {
        state?.task.cancel()
        try? await state?.socket.close()
        state = nil
    }

    func makeSocketAndListen() throws -> Socket {
        let socket = try Socket(ring: ring, domain: address.family, type: SOCK_STREAM, protocol: 0)

        try socket.setNonBlocking()
        try socket.setReuseAddr()
        try socket.setTcpNoDelay()
        try socket.bind(to: address)
        try socket.listen(backlog: depth)

        return socket
    }

    func handleController(_ controller: AES70OCP1IORingStreamController) async {
        _controllers.append(controller)
        do {
            for try await (message, rrq) in await controller.messages {
                try await handle(controller: controller, message: message, rrq: rrq)
            }
        } catch {}
        _controllers.removeAll(where: { $0 == controller })
        try? await controller.close()
    }
}

@AES70Device
public class AES70OCP1IORingDatagramDeviceEndpoint: AES70OCP1IORingDeviceEndpoint {
    var _controllers = [AnySocketAddress: AES70OCP1IORingDatagramController]()

    private(set) var state: (socket: Socket, task: Task<(), Error>)?

    override public var controllers: [AES70Controller] {
        _controllers.map(\.1)
    }

    func remove(controller: AES70OCP1IORingDatagramController) async {
        await AES70Device.shared.unlockAll(controller: controller)
        _controllers[controller.peerAddress] = nil
    }

    static let MaximumPduSize = 1500

    public func start() async throws {
        let socket = try makeSocket()
        let task = Task {
            let messages = try await socket.recvmsg(count: Self.MaximumPduSize)
            for try await message in messages {
                do {
                    let controllerAddress = try AnySocketAddress(bytes: message.name)
                    var controller: AES70OCP1IORingDatagramController! =
                        _controllers[controllerAddress]
                    if controller == nil {
                        controller = try await AES70OCP1IORingDatagramController(
                            endpoint: self,
                            peerAddress: controllerAddress
                        )
                        _controllers[controllerAddress] = controller
                    }
                    do {
                        let messagePdus = try await controller.receiveMessagePdus(message)
                        for (message, rrq) in messagePdus {
                            try await handle(controller: controller, message: message, rrq: rrq)
                        }
                    } catch {
                        await remove(controller: controller)
                    }
                } catch {}
            }
        }
        state = (socket: socket, task: task)
    }

    public func stop(timeout: TimeInterval = 0) async {
        state?.task.cancel()
        try? await state?.socket.close()
        state = nil
    }

    func makeSocket() throws -> Socket {
        let socket = try Socket(ring: ring, domain: address.family, type: SOCK_DGRAM, protocol: 0)

        try socket.setNonBlocking()
        try socket.setReuseAddr()
        try socket.bind(to: address)

        return socket
    }

    func sendMessagePdu(_ messagePdu: Message) async throws {
        guard let socket = state?.socket else {
            throw Ocp1Error.notConnected
        }
        try await socket.sendmsg(messagePdu)
    }
}

#endif
