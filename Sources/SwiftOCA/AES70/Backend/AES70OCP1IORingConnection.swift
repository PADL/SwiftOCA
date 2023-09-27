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
import IORingFoundation
@_implementationOnly
import IORingUtils

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

public class AES70OCP1IORingConnection: AES70OCP1Connection {
    fileprivate static let sharedRing = try! IORing()

    fileprivate let deviceAddress: any SocketAddress
    fileprivate var socket: Socket?
    fileprivate var type: UInt32 {
        fatalError("must be implemented by subclass")
    }

    public convenience init(
        deviceAddress: Data,
        options: AES70OCP1ConnectionOptions = AES70OCP1ConnectionOptions()
    ) throws {
        try self.init(socketAddress: deviceAddress.socketAddress, options: options)
    }

    fileprivate init(
        socketAddress: any SocketAddress,
        options: AES70OCP1ConnectionOptions
    ) {
        deviceAddress = socketAddress
        super.init(options: options)
    }

    override func connectDevice() async throws {
        socket = try Socket(
            ring: Self.sharedRing,
            domain: Swift.type(of: deviceAddress).family,
            type: __socket_type(type),
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

    private func withMappedError<T>(
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

    override public func read(_ length: Int) async throws -> Data {
        var buffer = [UInt8](repeating: 0, count: length)
        try await withMappedError { socket in
            if try await socket.read(into: &buffer, count: length) == false {
                throw Ocp1Error.pduTooShort // FIXME: check this, this is EOF return code
            }
        }
        return Data(buffer)
    }

    override public func write(_ data: Data) async throws -> Int {
        try await withMappedError { socket in
            try await socket.write(Array(data), count: data.count)
            return data.count
        }
    }
}

public final class AES70OCP1IORingDatagramConnection: AES70OCP1IORingConnection {
    override public var keepAliveInterval: OcaUint16 {
        1
    }

    override fileprivate var type: UInt32 {
        2 // SOCK_STREAM
    }

    override public var connectionPrefix: String {
        "\(OcaUdpConnectionPrefix)/\(deviceAddressToString(deviceAddress))"
    }
}

public final class AES70OCP1IORingStreamConnection: AES70OCP1IORingConnection {
    override fileprivate var type: UInt32 {
        1 // SOCK_STREAM
    }

    public convenience init(
        path: String,
        options: AES70OCP1ConnectionOptions = AES70OCP1ConnectionOptions()
    ) throws {
        try self.init(
            socketAddress: sockaddr_un(
                family: sa_family_t(AF_LOCAL),
                presentationAddress: path
            ),
            options: options
        )
    }

    override public var connectionPrefix: String {
        "\(OcaTcpConnectionPrefix)/\(deviceAddressToString(deviceAddress))"
    }
}

private func deviceAddressToString(_ deviceAddress: any SocketAddress) -> String {
    do {
        return try deviceAddress.presentationAddress
    } catch {
        return "<unknown>"
    }
}

#endif
