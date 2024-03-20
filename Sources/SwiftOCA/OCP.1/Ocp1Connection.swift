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
public typealias Ocp1UDPConnection = Ocp1IORingDatagramConnection
public typealias Ocp1TCPConnection = Ocp1IORingStreamConnection
#else
public typealias Ocp1UDPConnection = Ocp1CFSocketUDPConnection
public typealias Ocp1TCPConnection = Ocp1FlyingSocksStreamConnection
#endif

public typealias OcaSubscriptionCallback = @Sendable (OcaEvent, Data) async throws
    -> ()

#if canImport(Darwin)
@_spi(SwiftOCAPrivate)
public let SOCK_STREAM = Darwin.SOCK_STREAM
@_spi(SwiftOCAPrivate)
public let SOCK_DGRAM = Darwin.SOCK_DGRAM
#elseif canImport(Glibc)
@_implementationOnly
import CoreFoundation
@_spi(SwiftOCAPrivate)
public let SOCK_STREAM = Int32(CoreFoundation.SOCK_STREAM.rawValue)
@_spi(SwiftOCAPrivate)
public let SOCK_DGRAM = Int32(CoreFoundation.SOCK_DGRAM.rawValue)
#endif

let OcaTcpConnectionPrefix = "oca/tcp"
let OcaUdpConnectionPrefix = "oca/udp"
let OcaSecureTcpConnectionPrefix = "ocasec/tcp"
let OcaWebSocketTcpConnectionPrefix = "ocaws/tcp"
let OcaSpiConnectionPrefix = "oca/spi"

public struct Ocp1ConnectionOptions: Sendable {
    let automaticReconnect: Bool
    let connectionTimeout: Duration
    let responseTimeout: Duration
    let refreshDeviceTreeOnConnection: Bool

    public init(
        automaticReconnect: Bool = false,
        connectionTimeout: Duration = .seconds(2),
        responseTimeout: Duration = .seconds(2),
        refreshDeviceTreeOnConnection: Bool = true
    ) {
        self.automaticReconnect = automaticReconnect
        self.connectionTimeout = connectionTimeout
        self.responseTimeout = responseTimeout
        self.refreshDeviceTreeOnConnection = refreshDeviceTreeOnConnection
    }
}

@OcaConnection
open class Ocp1Connection: CustomStringConvertible, ObservableObject {
    public nonisolated static let MinimumPduSize = 7

    public var options: Ocp1ConnectionOptions

    /// Keepalive/ping interval (only necessary for UDP, but useful for other transports)
    open var heartbeatTime: Duration {
        .seconds(1)
    }

    /// Object interning, main thread only
    var objects = [OcaONo: OcaRoot]()

    /// Root block, immutable
    public let rootBlock = OcaBlock(objectNumber: OcaRootBlockONo)

    /// Well known managers, immutable
    let subscriptionManager = OcaSubscriptionManager()
    public let deviceManager = OcaDeviceManager()
    public let networkManager = OcaNetworkManager()

    final class EventSubscriptions {
        var subscriptions = Set<SubscriptionCancellable>()
    }

    /// Subscription callbacks, main thread only
    var subscriptions = [OcaEvent: EventSubscriptions]()
    var logger = Logger(label: "com.padl.SwiftOCA")

    private var nextCommandHandle = OcaUint32(100)

    var lastMessageSentTime = ContinuousClock.now

    open nonisolated var connectionPrefix: String {
        fatalError(
            "connectionPrefix must be implemented by a concrete subclass of Ocp1Connection"
        )
    }

    /// Monitor structure for matching requests and responses
    actor Monitor {
        typealias Continuation = CheckedContinuation<Ocp1Response, Error>

        private weak var connection: Ocp1Connection?
        private var continuations = [OcaUint32: Continuation]()
        private(set) var lastMessageReceivedTime = ContinuousClock.now

        init(_ connection: Ocp1Connection) {
            self.connection = connection
        }

        func run() async throws {
            guard let connection else { throw Ocp1Error.notConnected }
            do {
                try await receiveMessages(connection)
            } catch Ocp1Error.notConnected {
                if await connection.options.automaticReconnect {
                    try await connection.reconnectDevice()
                } else {
                    resumeAllNotConnected()
                    throw Ocp1Error.notConnected
                }
            }
        }

        func stop() {
            resumeAllNotConnected()
        }

        func register(handle: OcaUint32, continuation: Continuation) {
            continuations[handle] = continuation
        }

        func resumeAllNotConnected() {
            continuations.forEach {
                $0.1.resume(throwing: Ocp1Error.notConnected)
            }
            continuations.removeAll()
        }

        func resume(with response: Ocp1Response) throws {
            guard let continuation = continuations[response.handle] else {
                throw Ocp1Error.invalidHandle
            }
            continuations.removeValue(forKey: response.handle)
            continuation.resume(with: Result<Ocp1Response, Ocp1Error>.success(response))
        }

        func updateLastMessageReceivedTime() {
            lastMessageReceivedTime = ContinuousClock.now
        }
    }

    /// actor for monitoring response and matching them with requests
    var monitor: Monitor?

    private var monitorTask: Task<(), Error>?

    public init(options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()) {
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
        try await connectDeviceWithTimeout()
    }

    private func connectDeviceWithTimeout() async throws {
        do {
            try await withThrowingTimeout(of: options.connectionTimeout) {
                try await self.connectDevice()
            }
        } catch Ocp1Error.responseTimeout {
            throw Ocp1Error.connectionTimeout
        }
    }

    func connectDevice() async throws {
        monitor = Monitor(self)
        monitorTask = Task {
            try await monitor!.run()
        }

        subscriptions = [:]

        if heartbeatTime > .zero {
            // send keepalive to open UDP connection
            try await sendKeepAlive()
        }

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
        if let monitor {
            await monitor.stop()
            self.monitor = nil
        }
        if let monitorTask {
            monitorTask.cancel()
            self.monitorTask = nil
        }
        if clearObjectCache {
            objects = [:]
        }

        #if canImport(Combine) || canImport(OpenCombine)
        objectWillChange.send()
        #endif

        logger.info("Disconnected from \(self)")
    }

    public var isConnected: Bool {
        get async {
            !(monitorTask?.isCancelled ?? true)
        }
    }

    public nonisolated var description: String {
        connectionPrefix
    }

    /// API to be impmlemented by concrete classes
    open func read(_ length: Int) async throws -> Data {
        fatalError("read must be implemented by a concrete subclass of Ocp1Connection")
    }

    open func write(_ data: Data) async throws -> Int {
        fatalError("write must be implemented by a concrete subclass of Ocp1Connection")
    }
}

/// Public API
public extension Ocp1Connection {
    func connect() async throws {
        try await connectDeviceWithTimeout()
        if options.refreshDeviceTreeOnConnection {
            try? await refreshDeviceTree()
        }
    }

    func disconnect() async throws {
        try await removeSubscriptions()
        try await disconnectDevice(clearObjectCache: true)
    }
}

extension Ocp1Connection: Equatable {
    public nonisolated static func == (lhs: Ocp1Connection, rhs: Ocp1Connection) -> Bool {
        lhs.connectionPrefix == rhs.connectionPrefix
    }
}

extension Ocp1Connection: Hashable {
    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(connectionPrefix)
    }
}
