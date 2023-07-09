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

typealias AES70OCP1UDPConnection = AES70OCP1SocketUDPConnection
typealias AES70OCP1TCPConnection = AES70OCP1SocketTCPConnection

typealias AES70SubscriptionCallback = @MainActor (Ocp1EventData)
    -> ()

// FIXME: these don't appear to be available on non-Darwin platforms
private var NSEC_PER_MSEC: UInt64 = 1_000_000
private var NSEC_PER_SEC: UInt64 = 1_000_000_000

public struct AES70OCP1ConnectionOptions {
    let automaticReconnect: Bool
    let connectionTimeout: TimeInterval
    let responseTimeout: TimeInterval

    public init(
        automaticReconnect: Bool = false,
        connectionTimeout: TimeInterval = 5,
        responseTimeout: TimeInterval = 5
    ) {
        self.automaticReconnect = automaticReconnect
        self.connectionTimeout = connectionTimeout
        self.responseTimeout = responseTimeout
    }
}

public class AES70OCP1Connection: ObservableObject {
    /// This is effectively an actor (most methods are marked @MainActor) except it supports
    /// subclasses for different
    /// protocol types

    @MainActor
    let options: AES70OCP1ConnectionOptions

    /// Keepalive/ping interval (only necessary for UDP)
    @MainActor
    public var keepAliveInterval: OcaUint16 {
        0
    }

    /// Object interning, main thread only
    @MainActor
    var objects = [OcaONo: OcaRoot]()

    /// Root block, immutable
    @MainActor
    public let rootBlock = OcaBlock(objectNumber: OcaRootBlockONo)

    /// Well known managers, immutable
    @MainActor
    let subscriptionManager = OcaSubscriptionManager()
    @MainActor
    public let deviceManager = OcaDeviceManager()
    @MainActor
    public let networkManager = OcaNetworkManager()

    /// Subscription callbacks, main thread only
    @MainActor
    var subscriptions = [OcaEvent: AES70SubscriptionCallback]()

    // TODO: use SwiftAtomics here?
    @MainActor
    private var nextCommandHandle = OcaUint32(100)

    @MainActor
    var lastMessageSentTime = Date.distantPast

    /// Monitor structure for matching requests and responses
    actor Monitor {
        static let MinimumPduSize = 7

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
    @MainActor
    var monitor: Monitor? = nil

    @MainActor
    private var keepAliveTask: Task<(), Error>? = nil

    @MainActor
    public init(options: AES70OCP1ConnectionOptions = AES70OCP1ConnectionOptions()) {
        self.options = options
        add(object: rootBlock)
        add(object: subscriptionManager)
        add(object: deviceManager)
    }

    @MainActor
    func getNextCommandHandle() async -> OcaUint32 {
        let handle = nextCommandHandle
        nextCommandHandle += 1
        return handle
    }

    @MainActor
    func reconnectDevice() async throws {
        try await disconnectDevice(clearObjectCache: false)
        try await connectDevice()
    }

    @MainActor
    func connectDevice() async throws {
        monitor = Monitor(self)
        await monitor!.run()

        if keepAliveInterval != 0 {
            keepAliveTask = Task.detached(priority: .background) {
                repeat {
                    if await self
                        .lastMessageSentTime + TimeInterval(self.keepAliveInterval) < Date()
                    {
                        try await self.sendKeepAlive()
                    }
                    try await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(self.keepAliveInterval))
                } while true
            }
        }

        subscriptions = [:]

        // refresh all objects
        for (_, object) in objects {
            await object.refresh()
        }

        objectWillChange.send()
    }

    @MainActor
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

        objectWillChange.send()
    }

    public var isConnected: Bool {
        get async {
            await monitor != nil
        }
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
    @MainActor
    func connect() async throws {
        try await connectDevice()
        try? await refreshDeviceTree()
    }

    @MainActor
    func disconnect() async throws {
        try await removeSubscriptions()
        try await disconnectDevice(clearObjectCache: true)
    }
}
