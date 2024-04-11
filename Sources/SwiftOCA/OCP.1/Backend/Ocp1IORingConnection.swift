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

import Foundation
@_implementationOnly
import IORing
@_implementationOnly
import IORingFoundation
@_implementationOnly
import IORingUtils
import SystemPackage

fileprivate extension Errno {
    var connectionFailed: Bool {
        switch self {
        case .connectionRefused:
            fallthrough
        case .connectionReset:
            fallthrough
        case .brokenPipe:
            return true
        default:
            return false
        }
    }
}

public class Ocp1IORingConnection: Ocp1Connection {
    fileprivate class var type: Int32 {
        fatalError("must be implemented by subclass")
    }

    @_spi(SwiftOCAPrivate)
    public class var MaximumPduSize: Int {
        fatalError("must be implemented by subclass")
    }

    fileprivate let deviceAddress: any SocketAddress
    fileprivate var socket: Socket?

    fileprivate var ring: IORing {
        IORing.shared
    }

    public convenience init(
        deviceAddress: Data,
        options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
    ) throws {
        try self.init(socketAddress: deviceAddress.socketAddress, options: options)
    }

    fileprivate init(
        socketAddress: any SocketAddress,
        options: Ocp1ConnectionOptions
    ) throws {
        deviceAddress = socketAddress
        super.init(options: options)
    }

    public convenience init(
        path: String,
        options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
    ) throws {
        try self.init(
            socketAddress: sockaddr_un(
                family: sa_family_t(AF_LOCAL),
                presentationAddress: path
            ),
            options: options
        )
    }

    override func connectDevice() async throws {
        socket = try Socket(
            ring: ring,
            domain: Swift.type(of: deviceAddress).family,
            type: __socket_type(UInt32(Self.type)),
            protocol: 0
        )
        try socket!.setReuseAddr()
        try await socket!.connect(to: deviceAddress)
        try await super.connectDevice()
    }

    override public func disconnectDevice(clearObjectCache: Bool) async throws {
        socket = nil
        try await super.disconnectDevice(clearObjectCache: clearObjectCache)
    }

    fileprivate func withMappedError<T: Sendable>(
        _ block: (_ socket: Socket) async throws
            -> T
    ) async throws -> T {
        guard let socket else {
            throw Ocp1Error.notConnected
        }

        do {
            return try await block(socket)
        } catch let error as Errno {
            if error.connectionFailed {
                throw Ocp1Error.notConnected
            } else {
                throw error
            }
        }
    }
}

public final class Ocp1IORingDatagramConnection: Ocp1IORingConnection {
    override public var heartbeatTime: Duration {
        .seconds(1)
    }

    override fileprivate class var type: Int32 {
        SOCK_DGRAM
    }

    @_spi(SwiftOCAPrivate)
    override public class var MaximumPduSize: Int { 1500 }

    override public func read(_ length: Int) async throws -> Data {
        // read maximum PDU size
        try await withMappedError { socket in
            Data(try await socket.receive(count: Self.MaximumPduSize))
        }
    }

    override public func write(_ data: Data) async throws -> Int {
        try await withMappedError { socket in
            try await socket.send(Array(data))
            return data.count
        }
    }

    override public var connectionPrefix: String {
        "\(OcaUdpConnectionPrefix)/\(deviceAddressToString(deviceAddress))"
    }

    override public var isDatagram: Bool { true }
}

public final class Ocp1IORingStreamConnection: Ocp1IORingConnection {
    override fileprivate class var type: Int32 {
        SOCK_STREAM
    }

    @_spi(SwiftOCAPrivate)
    override public class var MaximumPduSize: Int { 1<<16 }

    private let _ring: IORing
    private var registeredFixedBuffers = false

    override fileprivate var ring: IORing {
        _ring
    }

    override fileprivate init(
        socketAddress: any SocketAddress,
        options: Ocp1ConnectionOptions
    ) throws {
        _ring = try IORing()
        try super.init(socketAddress: socketAddress, options: options)
    }

    override func connectDevice() async throws {
        if !registeredFixedBuffers {
            try await ring.registerFixedBuffers(count: 2, size: Self.MaximumPduSize)
            registeredFixedBuffers = true
        }
        try await super.connectDevice()
    }

    override public func read(_ length: Int) async throws -> Data {
        try await withMappedError { socket in
            Data(try await socket.readFixed(count: length, bufferIndex: 0, awaitingAllRead: true))
        }
    }

    override public func write(_ data: Data) async throws -> Int {
        // FIXME: this still involves a copy, arguably there is no point doing so
        try await withMappedError { socket in
            try await socket.writeFixed(Array(data), bufferIndex: 1, awaitingAllWritten: true)
        }
    }

    override public var connectionPrefix: String {
        "\(OcaTcpConnectionPrefix)/\(deviceAddressToString(deviceAddress))"
    }

    override public var isDatagram: Bool { false }
}

private func deviceAddressToString(_ deviceAddress: any SocketAddress) -> String {
    do {
        return try deviceAddress.presentationAddress
    } catch {
        return "<unknown>"
    }
}

#endif
