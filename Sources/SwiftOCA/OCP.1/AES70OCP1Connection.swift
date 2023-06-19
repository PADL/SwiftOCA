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
import AsyncAlgorithms
import AsyncExtensions

typealias AES70SubscriptionCallback = @MainActor (Ocp1EventData) -> Void

public class AES70OCP1Connection: ObservableObject {
    /// This is effectively an actor (most methods are marked @MainActor) except it supports subclasses for different
    /// protocol types
    
    /// Keepalive/ping interval (only necessary for UDP)
    @MainActor
    public var keepAliveInterval: OcaUint16 {
        return 10
    }

    @MainActor
    public var connectionTimeout = TimeInterval(3)
    @MainActor
    public var responseTimeout = TimeInterval(3)
    
    /// Object interning, main thread only
    @MainActor
    var objects = [OcaONo:OcaRoot]()
    
    /// Root block, immutable
    @MainActor
    public let rootBlock = OcaBlock(objectNumber: OcaRootBlockONo)
    
    /// Well known managers, immutable
    @MainActor
    let subscriptionManager = OcaSubscriptionManager()
    @MainActor
    public let deviceManager = OcaDeviceManager()
    
    /// Subscription callbacks, main thread only
    @MainActor
    var subscriptions = [OcaEvent:AES70SubscriptionCallback]()
    
    // TODO: use SwiftAtomics here?
    @MainActor
    private var nextCommandHandle = OcaUint32(100)
        
    @MainActor
    var lastMessageSentTime = Date.distantPast
    
    /// Monitor structure for matching requests and responses
    actor Monitor {
        static let MinimumPduSize = 7

        let channel = AsyncBufferedChannel<Ocp1Response>()
        var task: Task<Void, Error>? = nil
        var connection: AES70OCP1Connection?
        var lastMessageReceivedTime = Date.distantPast
        
        init(_ connection: AES70OCP1Connection) {
            self.connection = connection
        }
        
        func run() {
            precondition(task == nil)
            task = Task.detached { [unowned self] in
                try await self.receiveMessages(connection!)
            }
        }
    
        func updateLastMessageTime() {
            self.lastMessageReceivedTime = Date()
        }
        
        deinit {
            channel.finish()
            task?.cancel()
        }
    }
    
    /// actor for monitoring response and matching them with requests
    @MainActor
    var monitor: Monitor? = nil
    
    @MainActor
    private var keepAliveTask: Task<Void, Error>? = nil
    
    @MainActor
    public init() {
        add(object: self.rootBlock)
        add(object: self.subscriptionManager)
        add(object: self.deviceManager)
    }
    
    @MainActor
    func getNextCommandHandle() async -> OcaUint32{
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

        if self.keepAliveInterval != 0 {
            keepAliveTask = Task.detached(priority: .medium) {
                repeat {
                    if await self.lastMessageSentTime + TimeInterval(self.keepAliveInterval) < Date() {
                        try await self.sendKeepAlive()
                    }
                    try await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(self.keepAliveInterval))
                } while true
            }
        }

        // try await refreshSubscriptions()
        self.subscriptions = [:]
        
        // refresh all objects
        for (_, object) in self.objects {
            try? await object.refresh()
        }
        
        // TODO: on connect should we refresh the device tree

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    @MainActor
    func disconnectDevice(clearObjectCache: Bool) async throws {
        if let keepAliveTask {
            keepAliveTask.cancel()
            self.keepAliveTask = nil
        }
        if clearObjectCache {
            self.objects = [:]
        }
        monitor = nil
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
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
extension AES70OCP1Connection {
    @MainActor
    public func connect() async throws {
        try await connectDevice()
    }

    @MainActor
    public func close() async throws {
        try await removeSubscriptions()
        try await disconnectDevice(clearObjectCache: true)
    }
}

#if canImport(Combine) || canImport(OpenCombine)
#if canImport(Combine)
import Combine
#endif
#if canImport(OpenCombine)
import OpenCombine
#endif

extension AES70OCP1Connection {
    // FIXME: for portability outside of Combine we could use a AsyncPassthroughSubject
    func suspendUntilConnected() async throws {
        try await withTimeout(seconds: connectionTimeout) {
            while await self.monitor == nil {
                var cancellables = Set<AnyCancellable>()
                
                await withCheckedContinuation { continuation in
                    self.objectWillChange.sink { _ in
                        continuation.resume()
                    }.store(in: &cancellables)
                }
            }
        }
    }
}
#endif
