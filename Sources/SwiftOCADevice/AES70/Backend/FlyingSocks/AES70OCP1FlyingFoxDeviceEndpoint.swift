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

#if os(macOS) || os(iOS)

import AsyncExtensions
@_implementationOnly
import FlyingFox
@_implementationOnly
import FlyingSocks
import Foundation
import Logging
import SwiftOCA

@AES70Device
public final class AES70OCP1FlyingFoxDeviceEndpoint: AES70DeviceEndpointPrivate,
    AES70BonjourRegistrableDeviceEndpoint,
    CustomStringConvertible
{
    typealias ControllerType = AES70OCP1FlyingFoxController

    public var controllers: [AES70Controller] {
        _controllers
    }

    let logger = Logger(label: "com.padl.SwiftOCADevice.AES70OCP1FlyingFoxDeviceEndpoint")
    let timeout: Duration
    let device: AES70Device

    private var httpServer: HTTPServer!
    private let address: sockaddr_storage
    private var _controllers = [AES70OCP1FlyingFoxController]()
    private var endpointRegistrationHandle: AES70DeviceEndpointRegistrar.Handle?

    final class Handler: WSMessageHandler, @unchecked
    Sendable {
        weak var endpoint: AES70OCP1FlyingFoxDeviceEndpoint?

        init(_ endpoint: AES70OCP1FlyingFoxDeviceEndpoint) {
            self.endpoint = endpoint
        }

        func makeMessages(for client: AsyncStream<WSMessage>) async throws
            -> AsyncStream<WSMessage>
        {
            AsyncStream<WSMessage> { continuation in
                let controller = AES70OCP1FlyingFoxController(
                    inputStream: client,
                    outputStream: continuation,
                    endpoint: endpoint
                )

                let task = Task { @AES70Device in
                    if let endpoint {
                        await controller.handle(for: endpoint)
                    }
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        }
    }

    public convenience init(
        address: Data,
        timeout: Duration = .seconds(15),
        device: AES70Device = AES70Device.shared
    ) async throws {
        var storage = sockaddr_storage()
        _ = withUnsafeMutableBytes(of: &storage) { dst in
            address.withUnsafeBytes { src in
                memcpy(dst.baseAddress!, src.baseAddress!, src.count)
            }
        }
        try await self.init(address: storage, timeout: timeout, device: device)
    }

    public convenience init(
        path: String,
        timeout: Duration = .seconds(15),
        device: AES70Device = AES70Device.shared
    ) async throws {
        let address = sockaddr_un.unix(path: path).makeStorage()
        try await self.init(address: address, timeout: timeout, device: device)
    }

    private init(
        address: sockaddr_storage,
        timeout: Duration = .seconds(15),
        device: AES70Device = AES70Device.shared
    ) async throws {
        self.device = device
        self.address = address
        self.timeout = timeout

        // FIXME: API impedance mismatch
        let address: SocketAddress

        switch self.address.ss_family {
        case sa_family_t(AF_INET):
            address = try sockaddr_in.make(from: self.address)
        case sa_family_t(AF_INET6):
            address = try sockaddr_in6.make(from: self.address)
        case sa_family_t(AF_LOCAL):
            address = try sockaddr_un.make(from: self.address)
        default:
            throw Ocp1Error.unknownServiceType
        }

        httpServer = HTTPServer(
            address: address,
            timeout: timeout.timeInterval
        )

        await httpServer.appendRoute("GET /", to: .webSocket(Handler(self)))

        try await device.add(endpoint: self)
    }

    public nonisolated var description: String {
        withUnsafePointer(to: address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                let presentationAddress = deviceAddressToString(sa)
                return "\(type(of: self))(address: \(presentationAddress), timeout: \(timeout))"
            }
        }
    }

    public func run() async throws {
        do {
            if port != 0 {
                Task { endpointRegistrationHandle = try await AES70DeviceEndpointRegistrar.shared
                    .register(endpoint: self, device: device)
                }
            }
            try await httpServer.start()
        } catch {
            throw error
        }
    }

    public nonisolated var serviceType: AES70DeviceEndpointRegistrar.ServiceType {
        .tcpWebSocket
    }

    public nonisolated var port: UInt16 {
        var address = address
        return UInt16(bigEndian: withUnsafePointer(to: &address) { address in
            switch Int32(address.pointee.ss_family) {
            case AF_INET:
                return address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                    sin.pointee.sin_port
                }
            case AF_INET6:
                return address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                    sin6.pointee.sin6_port
                }
            default:
                return 0
            }
        })
    }

    func add(controller: AES70OCP1FlyingFoxController) async {
        _controllers.append(controller)
    }

    func remove(controller: AES70OCP1FlyingFoxController) async {
        _controllers.removeAll(where: { $0.id == controller.id })
    }
}
#endif
