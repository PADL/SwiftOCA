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

import AsyncAlgorithms
import Foundation
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#endif

public typealias AES70OCP1UDPConnection = AES70OCP1CFSocketUDPConnection
public typealias AES70OCP1TCPConnection = AES70OCP1FlyingSocksTCPConnection

public typealias AES70SubscriptionCallback = @MainActor (OcaEvent, Data)
    -> ()

// FIXME: these don't appear to be available on non-Darwin platforms
let NSEC_PER_MSEC: UInt64 = 1_000_000
let NSEC_PER_SEC: UInt64 = 1_000_000_000

let OcaTcpConnectionPrefix = "oca/tcp"
let OcaUdpConnectionPrefix = "oca/udp"
let OcaSecureTcpConnectionPrefix = "ocasec/tcp"
let OcaWebSocketTcpConnectionPrefix = "ocaws/tcp"

public struct AES70OCP1ConnectionOptions {
    let automaticReconnect: Bool
    let connectionTimeout: TimeInterval
    let responseTimeout: TimeInterval

    public init(
        automaticReconnect: Bool = false,
        connectionTimeout: TimeInterval = 2,
        responseTimeout: TimeInterval = 2
    ) {
        self.automaticReconnect = automaticReconnect
        self.connectionTimeout = connectionTimeout
        self.responseTimeout = responseTimeout
    }
}

@MainActor
public class AES70OCP1Connection: CustomStringConvertible, ObservableObject {
    public static let MinimumPduSize = 7

    let options: AES70OCP1ConnectionOptions

    /// Keepalive/ping interval (only necessary for UDP)
    public var keepAliveInterval: OcaUint16 {
        0
    }

    /// Object interning, main thread only
    var objects = [OcaONo: OcaRoot]()

    /// Root block, immutable
    public let rootBlock = OcaBlock(objectNumber: OcaRootBlockONo)

    /// Well known managers, immutable
    let subscriptionManager = OcaSubscriptionManager()
    public let deviceManager = OcaDeviceManager()
    public let networkManager = OcaNetworkManager()

    /// Subscription callbacks, main thread only
    var subscriptions = [OcaEvent: AES70SubscriptionCallback]()

    // TODO: use SwiftAtomics here?
    private var nextCommandHandle = OcaUint32(100)

    var lastMessageSentTime = Date.distantPast
    public nonisolated var connectionPrefix: String {
        fatalError("read must be implemented by a concrete subclass of AES70OCP1Connection")
    }

    /// Monitor structure for matching requests and responses
    actor Monitor {
        private let connection: AES70OCP1Connection!
        typealias Continuation = CheckedContinuation<Ocp1Response, Error>
        private var continuations = [OcaUint32: Continuation]()
        private var lastMessageReceivedTime = Date.distantPast
        private var task: Task<(), Error>?

        init(_ connection: AES70OCP1Connection) {
            self.connection = connection
        }

        func run() {
            precondition(task == nil)
            task = Task { [unowned self] in
                do {
                    try await self.receiveMessages(connection)
                } catch Ocp1Error.notConnected {
                    if connection.options.automaticReconnect {
                        try await connection.reconnectDevice()
                    } else {
                        throw Ocp1Error.notConnected
                    }
                }
            }
        }

        func stop() {
            precondition(task != nil)
            continuations.forEach {
                $0.1.resume(throwing: Ocp1Error.notConnected)
            }
            continuations.removeAll()
            lastMessageReceivedTime = Date.distantPast
            task?.cancel()
            task = nil
        }

        var isCancelled: Bool {
            guard let task else { return true }
            return task.isCancelled
        }

        func register(handle: OcaUint32, continuation: Continuation) {
            continuations[handle] = continuation
        }

        func resume(with response: Ocp1Response) throws {
            guard let continuation = continuations[response.handle] else {
                throw Ocp1Error.invalidHandle
            }
            continuations.removeValue(forKey: response.handle)
            Task {
                continuation.resume(with: Result<Ocp1Response, Ocp1Error>.success(response))
            }
        }

        func updateLastMessageReceivedTime() {
            lastMessageReceivedTime = Date()
        }

        var connectionIsStale: Bool {
            get async {
                await lastMessageReceivedTime + TimeInterval(3 * connection.keepAliveInterval) <
                    Date()
            }
        }
    }

    /// actor for monitoring response and matching them with requests
    var monitor: Monitor?

    private var keepAliveTask: Task<(), Error>?

    public init(options: AES70OCP1ConnectionOptions = AES70OCP1ConnectionOptions()) {
        self.options = options
        add(object: rootBlock)
        add(object: subscriptionManager)
        add(object: deviceManager)
    }

    func getNextCommandHandle() async -> OcaUint32 {
        let handle = nextCommandHandle
        nextCommandHandle += 1
        return handle
    }

    func reconnectDevice() async throws {
        try await disconnectDevice(clearObjectCache: false)
        try await connectDevice()
    }

    func connectDevice() async throws {
        monitor = Monitor(self)
        await monitor!.run()

        if keepAliveInterval > 0 {
            keepAliveTask = Task.detached(priority: .background) { [self] in
                repeat {
                    if await lastMessageSentTime + TimeInterval(self.keepAliveInterval) < Date() {
                        try await sendKeepAlive()
                    }
                    try await Task.sleep(nanoseconds: UInt64(self.keepAliveInterval) * NSEC_PER_SEC)
                } while !Task.isCancelled
            }
        }

        subscriptions = [:]

        // refresh all objects
        for (_, object) in objects {
            await object.refresh()
        }

        #if canImport(Combine) || canImport(OpenCombine)
        objectWillChange.send()
        #endif

        debugPrint("Connected to \(self)")
    }

    func disconnectDevice(clearObjectCache: Bool) async throws {
        if let keepAliveTask {
            keepAliveTask.cancel()
            self.keepAliveTask = nil
        }
        if let monitor {
            await monitor.stop()
            self.monitor = nil
        }
        if clearObjectCache {
            objects = [:]
        }

        #if canImport(Combine) || canImport(OpenCombine)
        objectWillChange.send()
        #endif
    }

    public var isConnected: Bool {
        get async {
            monitor != nil
        }
    }

    public nonisolated var description: String {
        connectionPrefix
    }

    /// API to be impmlemented by concrete classes
    func read(_ length: Int) async throws -> Data {
        fatalError("read must be implemented by a concrete subclass of AES70OCP1Connection")
    }

    func write(_ data: Data) async throws -> Int {
        fatalError("write must be implemented by a concrete subclass of AES70OCP1Connection")
    }
}

/// Public API
public extension AES70OCP1Connection {
    func connect() async throws {
        try await connectDevice()
        try? await refreshDeviceTree()
    }

    func disconnect() async throws {
        try await removeSubscriptions()
        try await disconnectDevice(clearObjectCache: true)
    }
}

extension AES70OCP1Connection: Equatable {
    public nonisolated static func == (lhs: AES70OCP1Connection, rhs: AES70OCP1Connection) -> Bool {
        lhs.connectionPrefix == rhs.connectionPrefix
    }
}

extension AES70OCP1Connection: Hashable {
    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(connectionPrefix)
    }
}
