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
@preconcurrency
import Foundation
import Logging
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#endif

#if canImport(IORing)
public typealias AES70OCP1UDPConnection = AES70OCP1IORingDatagramConnection
public typealias AES70OCP1TCPConnection = AES70OCP1IORingStreamConnection
#else
public typealias AES70OCP1UDPConnection = AES70OCP1CFSocketUDPConnection
public typealias AES70OCP1TCPConnection = AES70OCP1FlyingSocksStreamConnection
#endif

public typealias AES70SubscriptionCallback = @Sendable (OcaEvent, Data) async throws
    -> ()

let OcaTcpConnectionPrefix = "oca/tcp"
let OcaUdpConnectionPrefix = "oca/udp"
let OcaSecureTcpConnectionPrefix = "ocasec/tcp"
let OcaWebSocketTcpConnectionPrefix = "ocaws/tcp"
let OcaSpiConnectionPrefix = "oca/spi"

public struct AES70OCP1ConnectionOptions: Sendable {
    let automaticReconnect: Bool
    let connectionTimeout: Duration
    let responseTimeout: Duration

    public init(
        automaticReconnect: Bool = false,
        connectionTimeout: Duration = .seconds(2),
        responseTimeout: Duration = .seconds(2)
    ) {
        self.automaticReconnect = automaticReconnect
        self.connectionTimeout = connectionTimeout
        self.responseTimeout = responseTimeout
    }
}

@MainActor
open class AES70OCP1Connection: CustomStringConvertible, ObservableObject {
    public nonisolated static let MinimumPduSize = 7

    let options: AES70OCP1ConnectionOptions

    /// Keepalive/ping interval (only necessary for UDP)
    public var keepAliveInterval: Duration {
        .zero
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
    var logger = Logger(label: "com.padl.SwiftOCA")

    // TODO: use SwiftAtomics here?
    private var nextCommandHandle = OcaUint32(100)

    var lastMessageSentTime = ContinuousClock.now
    open nonisolated var connectionPrefix: String {
        fatalError(
            "connectionPrefix must be implemented by a concrete subclass of AES70OCP1Connection"
        )
    }

    /// Monitor structure for matching requests and responses
    actor Monitor {
        private let connection: AES70OCP1Connection!
        typealias Continuation = CheckedContinuation<Ocp1Response, Error>
        private var continuations = [OcaUint32: Continuation]()
        private var lastMessageReceivedTime = ContinuousClock.now
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
            lastMessageReceivedTime = ContinuousClock.now
        }

        /// returns `true` if insufficient keepalives were received to keep connection fresh
        var connectionIsStale: Bool {
            get async {
                let keepAliveInterval = await connection.keepAliveInterval
                return keepAliveInterval > .zero &&
                    ContinuousClock
                    .now - (lastMessageReceivedTime + keepAliveInterval) > .seconds(0)
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

    // FIXME: why does need to be public for non-debug builds to link?
    public func getNextCommandHandle() async -> OcaUint32 {
        let handle = nextCommandHandle
        nextCommandHandle += 1
        return handle
    }

    // FIXME: why does need to be public for non-debug builds to link?
    public func reconnectDevice() async throws {
        try await disconnectDevice(clearObjectCache: false)
        try await connectDevice()
    }

    func connectDevice() async throws {
        monitor = Monitor(self)
        await monitor!.run()

        if keepAliveInterval > .zero {
            keepAliveTask = Task.detached(priority: .background) { [self] in
                repeat {
                    if await lastMessageSentTime + keepAliveInterval < ContinuousClock().now {
                        try await sendKeepAlive()
                    }
                    try await Task.sleep(for: keepAliveInterval)
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

        logger.info("Connected to \(self)")
    }

    open func disconnectDevice(clearObjectCache: Bool) async throws {
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
    open func read(_ length: Int) async throws -> Data {
        fatalError("read must be implemented by a concrete subclass of AES70OCP1Connection")
    }

    open func write(_ data: Data) async throws -> Int {
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
