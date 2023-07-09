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

import FlyingSocks
import Foundation

private extension SocketError {
    var connectionFailed: Bool {
        switch self {
        case let .failed(_, errno, _):
            return errno == EBADF || errno == ESHUTDOWN
        case .blocked:
            return false
        case .disconnected:
            return true
        case .unsupportedAddress:
            return false
        }
    }
}

private extension Data {
    var socketAddress: any SocketAddress {
        try! withUnsafeBytes { unbound -> (any SocketAddress) in
            try unbound
                .withMemoryRebound(
                    to: sockaddr_storage
                        .self
                ) { storage -> (any SocketAddress) in
                    let ss = storage.baseAddress!.pointee
                    switch ss.ss_family {
                    case UInt8(AF_INET):
                        return try sockaddr_in.make(from: ss)
                    case UInt8(AF_INET6):
                        return try sockaddr_in6.make(from: ss)
                    default:
                        fatalError("unsupported address family")
                    }
                }
        }
    }
}

private actor AsyncSocketPoolMonitor {
    static let shared = AsyncSocketPoolMonitor()

    private let pool: some AsyncSocketPool = SocketPool.make()
    private var isRunning = false

    func get() async throws -> some AsyncSocketPool {
        guard !isRunning else { return pool }
        try await pool.prepare()
        defer { isRunning = true }
        Task {
            try await pool.run()
        }
        return pool
    }
}

public class AES70OCP1FlyingSocksConnection: AES70OCP1Connection {
    private static var poolIsRunning = false
    private let deviceAddress: any SocketAddress
    fileprivate var socket: AsyncSocket?
    fileprivate var type: Int32 {
        fatalError("must be implemented by subclass")
    }

    @MainActor
    public init(
        deviceAddress: Data,
        options: AES70OCP1ConnectionOptions = AES70OCP1ConnectionOptions(),
        pool: AsyncSocketPool = SocketPool.make()
    ) {
        self.deviceAddress = deviceAddress.socketAddress
        super.init(options: options)
    }

    deinit {
        try? socket?.close()
    }

    override func connectDevice() async throws {
        let socket = try Socket(domain: Int32(Swift.type(of: deviceAddress).family), type: type)
        try socket.setValue(true, for: BoolSocketOption.localAddressReuse)
        try socket.connect(to: deviceAddress)
        self.socket = try await AsyncSocket(
            socket: socket,
            pool: AsyncSocketPoolMonitor.shared.get()
        )
        try await super.connectDevice()
    }

    override func disconnectDevice(clearObjectCache: Bool) async throws {
        if let socket {
            try socket.close()
        }
        try await super.disconnectDevice(clearObjectCache: clearObjectCache)
    }

    private func withMappedError<T>(
        _ block: (_ socket: AsyncSocket) async throws
            -> T
    ) async throws -> T {
        guard let socket else {
            throw Ocp1Error.notConnected
        }

        do {
            return try await block(socket)
        } catch let error as SocketError {
            if error.connectionFailed {
                throw Ocp1Error.notConnected
            } else {
                throw error
            }
        }
    }

    override func read(_ length: Int) async throws -> Data {
        try await withMappedError { socket in
            try await Data(socket.read(bytes: length))
        }
    }

    override func write(_ data: Data) async throws -> Int {
        try await withMappedError { socket in
            try await socket.write(data)
            return data.count
        }
    }
}

public class AES70OCP1FlyingSocksUDPConnection: AES70OCP1FlyingSocksConnection {
    override fileprivate var type: Int32 {
        SOCK_DGRAM
    }
}

public class AES70OCP1FlyingSocksTCPConnection: AES70OCP1FlyingSocksConnection {
    override fileprivate var type: Int32 {
        SOCK_STREAM
    }
}
