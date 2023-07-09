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

import Foundation
import Socket

private extension Errno {
    var connectionFailed: Bool {
        self == .badFileDescriptor || self == .socketShutdown
    }
}

private extension Data {
    var socketAddress: any SocketAddress {
        var data = self
        return data.withUnsafeMutableBytes { unbound -> (any SocketAddress) in
            unbound
                .withMemoryRebound(to: sockaddr.self) { sa -> (any SocketAddress) in
                    let socketAddress: any SocketAddress

                    switch sa.baseAddress!.pointee.sa_family {
                    case UInt8(AF_INET):
                        socketAddress = IPv4SocketAddress.withUnsafePointer(sa.baseAddress!)
                    case UInt8(AF_INET6):
                        socketAddress = IPv6SocketAddress.withUnsafePointer(sa.baseAddress!)
                    case UInt8(AF_LINK):
                        socketAddress = LinkLayerSocketAddress.withUnsafePointer(sa.baseAddress!)
                    default:
                        fatalError("unsupported address family")
                    }

                    return socketAddress
                }
        }
    }
}

public class AES70OCP1SocketConnection: AES70OCP1Connection {
    let monitorInterval: UInt64 = 10 * NSEC_PER_MSEC
    private let deviceAddress: any SocketAddress
    var socket: Socket?

    @MainActor
    public init(
        deviceAddress: Data,
        options: AES70OCP1ConnectionOptions = AES70OCP1ConnectionOptions()
    ) {
        self.deviceAddress = deviceAddress.socketAddress
        super.init(options: options)
    }

    override func connectDevice() async throws {
        guard let socket else {
            throw Ocp1Error.notConnected
        }

        // TODO: should this be done in a separate task?
        debugPrint("Connecting to \(deviceAddress) on socket \(socket)")
        do {
            try await socket.connect(to: deviceAddress)
        } catch Errno.socketIsConnected {
        } catch {
            debugPrint("Socket connection error \(error)")
            throw error
        }

        try await super.connectDevice()
    }

    override func disconnectDevice(clearObjectCache: Bool) async throws {
        if let socket {
            debugPrint("Closing socket \(socket)")
            await socket.close()
        }
        try await super.disconnectDevice(clearObjectCache: clearObjectCache)
    }

    fileprivate func withMappedError<T>(
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

public class AES70OCP1SocketUDPConnection: AES70OCP1SocketConnection {
    @MainActor
    override public var keepAliveInterval: OcaUint16 {
        1
    }

    static let mtu = 1500

    override func connectDevice() async throws {
        if socket == nil {
            Socket.configuration = AsyncSocketConfiguration(monitorInterval: monitorInterval)
            socket = try await Socket(IPv4Protocol.udp)
        }
        try await super.connectDevice()
    }

    override func read(_ length: Int) async throws -> Data {
        try await withMappedError { socket in
            try await socket.receiveMessage(Self.mtu)
        }
    }

    override func write(_ data: Data) async throws -> Int {
        try await withMappedError { socket in
            try await socket.sendMessage(data)
        }
    }
}

public class AES70OCP1SocketTCPConnection: AES70OCP1SocketConnection {
    override func connectDevice() async throws {
        if socket == nil {
            Socket.configuration = AsyncSocketConfiguration(monitorInterval: monitorInterval)
            socket = try await Socket(IPv4Protocol.tcp)
        }
        try await super.connectDevice()
    }

    override func read(_ length: Int) async throws -> Data {
        try await withMappedError { socket in
            var bytesLeft = length
            var data = Data()

            repeat {
                let fragment = try await socket.read(bytesLeft)
                bytesLeft -= fragment.count
                data += fragment
            } while bytesLeft > 0
            return data
        }
    }

    override func write(_ data: Data) async throws -> Int {
        try await withMappedError { socket in
            var bytesWritten = 0

            repeat {
                bytesWritten += try await socket.write(data.subdata(in: bytesWritten..<data.count))
            } while bytesWritten < data.count

            return bytesWritten
        }
    }
}
