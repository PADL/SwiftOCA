//
//  Ocp1FlyingSocksDeviceEndpoint.swift
//
//  Copyright (c) 2022 Simon Whitty. All rights reserved.
//  Portions Copyright (c) 2023 PADL Software Pty Ltd. All rights reserved.
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
@_implementationOnly
import FlyingSocks
@_spi(Private) @_implementationOnly
import func FlyingSocks.withThrowingTimeout
import Foundation
import Logging
import SwiftOCA

@OcaDevice
public final class Ocp1FlyingSocksDeviceEndpoint: OcaDeviceEndpointPrivate,
    OcaBonjourRegistrableDeviceEndpoint,
    CustomStringConvertible
{
    typealias ControllerType = Ocp1FlyingSocksController

    public var controllers: [OcaController] {
        _controllers
    }

    let pool: AsyncSocketPool

    private let address: sockaddr_storage
    let timeout: Duration
    let logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1FlyingSocksDeviceEndpoint")
    let device: OcaDevice

    private var _controllers = [Ocp1FlyingSocksController]()
    private var endpointRegistrationHandle: OcaDeviceEndpointRegistrar.Handle?

    public convenience init(
        address: Data,
        timeout: Duration = .seconds(15),
        device: OcaDevice = OcaDevice.shared
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
        device: OcaDevice = OcaDevice.shared
    ) async throws {
        let address = sockaddr_un.unix(path: path).makeStorage()
        try await self.init(address: address, timeout: timeout, device: device)
    }

    private init(
        address: sockaddr_storage,
        timeout: Duration = .seconds(15),
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
                Task { endpointRegistrationHandle = try await OcaDeviceEndpointRegistrar.shared
                    .register(endpoint: self, device: device)
                }
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

    var waiting: Set<Continuation> = []
    private(set) var socket: Socket? {
        didSet { isListeningDidUpdate(from: oldValue != nil) }
    }

    private func shutdown(timeout: Duration = .seconds(0)) async {
        if let endpointRegistrationHandle {
            try? await OcaDeviceEndpointRegistrar.shared
                .deregister(handle: endpointRegistrationHandle)
        }

        try? socket?.close()
    }

    func makeSocketAndListen() throws -> Socket {
        let socket = try Socket(domain: Int32(address.ss_family))
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
                    try await Ocp1FlyingSocksController(endpoint: self, socket: socket)
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
                    try await Ocp1FlyingSocksController(endpoint: self, socket: socket)
                        .handle(for: self)
                }
            }
        }
        throw SocketError.disconnected
    }

    static func defaultPool(logger: Logging? = nil) -> AsyncSocketPool {
        #if canImport(Darwin)
        return .kQueue(logger: logger)
        #elseif canImport(CSystemLinux)
        return .ePoll(logger: logger)
        #else
        return .poll(logger: logger)
        #endif
    }

    public nonisolated var serviceType: OcaDeviceEndpointRegistrar.ServiceType {
        .tcp
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

    func add(controller: ControllerType) async {
        _controllers.append(controller)
    }

    func remove(controller: ControllerType) async {
        _controllers.removeAll(where: { $0 == controller })
    }
}

extension Ocp1FlyingSocksDeviceEndpoint {
    public var isListening: Bool { socket != nil }

    func waitUntilListening(timeout: Duration = .seconds(5)) async throws {
        try await SwiftOCA.withThrowingTimeout(of: timeout) {
            try await self.doWaitUntilListening()
        }
    }

    private func doWaitUntilListening() async throws {
        guard !isListening else { return }
        let continuation = Continuation()
        waiting.insert(continuation)
        defer { waiting.remove(continuation) }
        return try await continuation.value
    }

    func isListeningDidUpdate(from previous: Bool) {
        guard isListening else { return }
        let waiting = waiting
        self.waiting = []

        for continuation in waiting {
            continuation.resume()
        }
    }

    typealias Continuation = CancellingContinuation<(), Never>
}

#endif
