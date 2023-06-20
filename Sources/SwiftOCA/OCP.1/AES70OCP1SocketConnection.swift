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

fileprivate extension Errno {
    var connectionFailed: Bool {
        self == .badFileDescriptor || self == .socketShutdown
    }
}

public class AES70OCP1SocketConnection: AES70OCP1Connection {
    private let deviceAddress: any SocketAddress
    var socket: Socket? = nil
    
    @MainActor
    public init(deviceAddress: any SocketAddress) {
        self.deviceAddress = deviceAddress
        super.init()
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
}

public class AES70OCP1UDPConnection: AES70OCP1SocketConnection {
    static let mtu = 1500
    
    override func connectDevice() async throws {
        if socket == nil {
            Socket.configuration = AsyncSocketConfiguration(monitorPriority: .userInitiated)
            socket = try await Socket(IPv4Protocol.udp)
        }
        try await super.connectDevice()
    }
    
    override func read(_ length: Int) async throws -> Data {
        guard let socket else {
            throw Ocp1Error.notConnected
        }
        
        do {
            return try await socket.receiveMessage(Self.mtu)
        } catch let error as Errno {
            if error.connectionFailed {
                throw Ocp1Error.notConnected
            } else {
                throw error
            }
        }
    }
    
    override func write(_ data: Data) async throws -> Int {
        guard let socket else {
            throw Ocp1Error.notConnected
        }
        
        do {
            return try await socket.sendMessage(data)
        } catch let error as Errno {
            if error.connectionFailed {
                throw Ocp1Error.notConnected
            } else {
                throw error
            }
        }
    }
}

public class AES70OCP1TCPConnection: AES70OCP1SocketConnection {
    override func connectDevice() async throws {
        if socket == nil {
            Socket.configuration = AsyncSocketConfiguration(monitorPriority: .userInitiated)
            socket = try await Socket(IPv4Protocol.tcp)
        }
        try await super.connectDevice()
    }
    
    override func read(_ length: Int) async throws -> Data {
        guard let socket else {
            throw Ocp1Error.notConnected
        }
        
        var bytesLeft = length
        var data = Data()
        
        do {
            repeat {
                let fragment = try await socket.read(bytesLeft)
                bytesLeft -= fragment.count
                data += fragment
            } while bytesLeft > 0
        } catch let error as Errno {
            if error.connectionFailed {
                throw Ocp1Error.notConnected
            } else {
                throw error
            }
        }
        return data
    }
    
    override func write(_ data: Data) async throws -> Int {
        guard let socket else {
            throw Ocp1Error.notConnected
        }
        
        var bytesWritten = 0
        
        do {
            repeat {
                bytesWritten += try await socket.write(data.subdata(in: bytesWritten..<data.count))
            } while bytesWritten < data.count
        } catch let error as Errno {
            if error.connectionFailed {
                throw Ocp1Error.notConnected
            } else {
                throw error
            }
        }
        
        return bytesWritten
    }
}
