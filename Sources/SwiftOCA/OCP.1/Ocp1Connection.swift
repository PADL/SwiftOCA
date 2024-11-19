//
// Copyright (c) 2023-2024 PADL Software Pty Ltd
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
import AsyncExtensions
import Atomics
@preconcurrency
import Foundation
import Logging
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#endif

package let Ocp1MaximumDatagramPduSize = 1500

#if canImport(IORing)
public typealias Ocp1UDPConnection = Ocp1IORingDatagramConnection
public typealias Ocp1TCPConnection = Ocp1IORingStreamConnection
#elseif canImport(FlyingSocks)
public typealias Ocp1UDPConnection = Ocp1FlyingSocksDatagramConnection
public typealias Ocp1TCPConnection = Ocp1FlyingSocksStreamConnection
#else
public typealias Ocp1UDPConnection = Ocp1CFSocketUDPConnection
public typealias Ocp1TCPConnection = Ocp1CFSocketTCPConnection
#endif

public typealias OcaSubscriptionCallback = @Sendable (OcaEvent, Data) async throws
  -> ()

#if canImport(Darwin)
package let SOCK_STREAM: Int32 = Darwin.SOCK_STREAM
package let SOCK_DGRAM: Int32 = Darwin.SOCK_DGRAM
#elseif canImport(Android)
import Android

package let SOCK_STREAM = Int32(Android.SOCK_STREAM)
package let SOCK_DGRAM = Int32(Android.SOCK_DGRAM)
#elseif canImport(Glibc)
import CoreFoundation

package let SOCK_STREAM = Int32(Glibc.SOCK_STREAM.rawValue)
package let SOCK_DGRAM = Int32(Glibc.SOCK_DGRAM.rawValue)
#endif

public let OcaTcpConnectionPrefix = "oca/tcp"
public let OcaUdpConnectionPrefix = "oca/udp"
public let OcaSecureTcpConnectionPrefix = "ocasec/tcp"
public let OcaWebSocketTcpConnectionPrefix = "ocaws/tcp"
public let OcaLocalConnectionPrefix = "oca/local"
public let OcaDatagramProxyConnectionPrefix = "oca/dg-proxy"

public struct Ocp1ConnectionFlags: OptionSet, Sendable {
  public static let automaticReconnect = Ocp1ConnectionFlags(rawValue: 1 << 0)
  public static let refreshDeviceTreeOnConnection = Ocp1ConnectionFlags(rawValue: 1 << 1)

  public typealias RawValue = UInt

  public let rawValue: RawValue

  public init(rawValue: RawValue) {
    self.rawValue = rawValue
  }
}

public struct Ocp1ConnectionOptions: Sendable {
  let flags: Ocp1ConnectionFlags
  let connectionTimeout: Duration
  let responseTimeout: Duration
  let reconnectMaxTries: Int
  let reconnectPauseInterval: Duration
  let reconnectExponentialBackoffThreshold: Range<Int>

  public init(
    flags: Ocp1ConnectionFlags = .refreshDeviceTreeOnConnection,
    connectionTimeout: Duration = .seconds(2),
    responseTimeout: Duration = .seconds(2),
    reconnectMaxTries: Int = 15,
    reconnectPauseInterval: Duration = .milliseconds(250),
    reconnectExponentialBackoffThreshold: Range<Int> = 3..<8
  ) {
    self.flags = flags
    self.connectionTimeout = connectionTimeout
    self.responseTimeout = responseTimeout
    self.reconnectMaxTries = reconnectMaxTries
    self.reconnectPauseInterval = reconnectPauseInterval
    self.reconnectExponentialBackoffThreshold = reconnectExponentialBackoffThreshold
  }

  @available(*, deprecated, message: "use Ocp1ConnectionFlags initializer")
  public init(
    automaticReconnect: Bool = false,
    connectionTimeout: Duration = .seconds(2),
    responseTimeout: Duration = .seconds(2),
    refreshDeviceTreeOnConnection: Bool = true,
    reconnectMaxTries: Int = 15,
    reconnectPauseInterval: Duration = .milliseconds(250),
    reconnectExponentialBackoffThreshold: Range<Int> = 3..<8
  ) {
    var flags = Ocp1ConnectionFlags()
    if automaticReconnect { flags.insert(.automaticReconnect) }
    if refreshDeviceTreeOnConnection { flags.insert(.refreshDeviceTreeOnConnection) }

    self.init(
      flags: flags,
      connectionTimeout: connectionTimeout,
      responseTimeout: responseTimeout,
      reconnectMaxTries: reconnectMaxTries,
      reconnectPauseInterval: reconnectPauseInterval,
      reconnectExponentialBackoffThreshold: reconnectExponentialBackoffThreshold
    )
  }
}

public enum Ocp1ConnectionState: OcaUint8, Codable, Sendable {
  case notConnected
  case connecting
  case connected
  case reconnecting
  case timedOut
}

public struct Ocp1ConnectionStatistics: Sendable {
  public let connectionState: Ocp1ConnectionState
  public var isConnected: Bool { connectionState == .connected }
  public let requestCount: Int
  public let outstandingRequests: [OcaUint32]
  public let cachedObjectCount: Int
  public let subscribedEvents: [OcaEvent]
  public let lastMessageSentTime: Date
  public let lastMessageReceivedTime: Date?
}

private let CommandHandleBase = OcaUint32(100)

@OcaConnection
open class Ocp1Connection: CustomStringConvertible, ObservableObject {
  public nonisolated static let MinimumPduSize = 7

  public internal(set) var options: Ocp1ConnectionOptions

  public func set(options: Ocp1ConnectionOptions) async throws {
    let oldFlags = self.options.flags
    self.options = options
    if !oldFlags.contains(.automaticReconnect) && options.flags.contains(.automaticReconnect) {
      try await connect()
    } else if !oldFlags.contains(.refreshDeviceTreeOnConnection) && options.flags
      .contains(.refreshDeviceTreeOnConnection)
    {
      try await refreshDeviceTree()
    }
  }

  /// Keepalive/ping interval (only necessary for UDP, but useful for other transports)
  open var heartbeatTime: Duration {
    .seconds(1)
  }

  private let _connectionState = AsyncCurrentValueSubject<Ocp1ConnectionState>(.notConnected)
  public let connectionState: AnyAsyncSequence<Ocp1ConnectionState>

  /// Object interning
  var objects = [OcaONo: OcaRoot]()

  /// Root block, immutable
  public let rootBlock = OcaBlock(objectNumber: OcaRootBlockONo)

  /// Well known managers, immutable
  let subscriptionManager = OcaSubscriptionManager()
  public let deviceManager = OcaDeviceManager()
  public let networkManager = OcaNetworkManager()

  @OcaConnection
  final class EventSubscriptions {
    var subscriptions = Set<SubscriptionCancellable>()
  }

  var subscriptions = [OcaEvent: EventSubscriptions]()
  var logger = Logger(label: "com.padl.SwiftOCA")

  private var nextCommandHandle = CommandHandleBase

  var lastMessageSentTime = Monitor.now

  open nonisolated var connectionPrefix: String {
    fatalError(
      "connectionPrefix must be implemented by a concrete subclass of Ocp1Connection"
    )
  }

  public var statistics: Ocp1ConnectionStatistics {
    Ocp1ConnectionStatistics(
      connectionState: _connectionState.value,
      requestCount: Int(nextCommandHandle - CommandHandleBase),
      outstandingRequests: monitor?.outstandingRequests ?? [],
      cachedObjectCount: objects.count,
      subscribedEvents: Array(subscriptions.keys),
      lastMessageSentTime: Date(timeIntervalSince1970: TimeInterval(lastMessageSentTime)),
      lastMessageReceivedTime: monitor != nil ?
        Date(timeIntervalSince1970: TimeInterval(monitor!.lastMessageReceivedTime)) : nil
    )
  }

  /// Monitor structure for matching requests and responses
  final class Monitor: @unchecked Sendable {
    typealias Continuation = CheckedContinuation<Ocp1Response, Error>

    private let _connection: Weak<Ocp1Connection>
    private let _continuations = ManagedCriticalState<[OcaUint32: Continuation]>([:])
    private var _lastMessageReceivedTime = ManagedAtomic<UInt64>(0)

    static var now: UInt64 {
      UInt64(time(nil))
    }

    init(_ connection: Ocp1Connection) {
      _connection = Weak(connection)
      updateLastMessageReceivedTime()
    }

    var connection: Ocp1Connection? {
      _connection.object
    }

    func run() async throws {
      guard let connection else { throw Ocp1Error.notConnected }
      do {
        try await receiveMessages(connection)
      } catch Ocp1Error.notConnected {
        if await connection.options.flags.contains(.automaticReconnect) {
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
      _continuations.withCriticalRegion { continuations in
        continuations[handle] = continuation
      }
    }

    func resumeAllNotConnected() {
      _continuations.withCriticalRegion { continuations in
        for continuation in continuations.values {
          continuation.resume(throwing: Ocp1Error.notConnected)
        }
        continuations.removeAll()
      }
    }

    func resume(with response: Ocp1Response) throws {
      try _continuations.withCriticalRegion { continuations in
        let continuation = try popContinuation(for: response, in: &continuations)
        continuation.resume(with: Result<Ocp1Response, Ocp1Error>.success(response))
      }
    }

    private func popContinuation(
      for response: Ocp1Response,
      in continuations: inout [OcaUint32: Continuation]
    ) throws -> Continuation {
      guard let continuation = continuations[response.handle] else {
        throw Ocp1Error.invalidHandle
      }
      continuations.removeValue(forKey: response.handle)
      return continuation
    }

    func updateLastMessageReceivedTime() {
      _lastMessageReceivedTime.store(Monitor.now, ordering: .releasing)
    }

    fileprivate var outstandingRequests: [OcaUint32] {
      _continuations.withCriticalRegion { Array($0.keys) }
    }

    var lastMessageReceivedTime: UInt64 {
      _lastMessageReceivedTime.load(ordering: .relaxed)
    }
  }

  /// actor for monitoring response and matching them with requests
  var monitor: Monitor?

  private var monitorTask: Task<(), Error>?

  public init(options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()) {
    connectionState = _connectionState.eraseToAnyAsyncSequence()
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

    var lastError: Error?
    var backoff: Duration = options.reconnectPauseInterval

    for i in 0..<options.reconnectMaxTries {
      do {
        try await connectDeviceWithTimeout()
        _connectionState.send(.connected)
        break
      } catch {
        lastError = error
        _connectionState.send(.reconnecting)
        if options.reconnectExponentialBackoffThreshold.contains(i) {
          backoff *= 2
        }
        try await Task.sleep(for: backoff)
      }
    }

    if let lastError {
      throw lastError
    } else if !isConnected {
      throw Ocp1Error.notConnected
    }

    await refreshSubscriptions()
  }

  private func connectDeviceWithTimeout() async throws {
    do {
      try await withThrowingTimeout(of: options.connectionTimeout) {
        try await self.connectDevice()
      }
    } catch Ocp1Error.responseTimeout {
      throw Ocp1Error.connectionTimeout
    } catch {
      throw error
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

  open func clearObjectCache() async {
    objects = [:]
    await rootBlock.refreshAll()
  }

  open func disconnectDevice(clearObjectCache: Bool) async throws {
    if let monitor {
      monitor.stop()
      self.monitor = nil
    }
    monitorTask = nil
    _connectionState.send(.notConnected)

    if clearObjectCache {
      await self.clearObjectCache()
    }

    #if canImport(Combine) || canImport(OpenCombine)
    objectWillChange.send()
    #endif

    logger.info("Disconnected from \(self)")
  }

  public var isConnected: Bool {
    _connectionState.value == .connected
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

  /// by default, connection implementations that require heartbeats are assumed to use datagrams.
  /// A concrete implementation is free to override this however.
  open var isDatagram: Bool {
    heartbeatTime > .seconds(0)
  }
}

/// Public API
public extension Ocp1Connection {
  func connect() async throws {
    _connectionState.send(.connecting)
    do {
      try await connectDeviceWithTimeout()
    } catch Ocp1Error.connectionTimeout {
      _connectionState.send(.timedOut)
      throw Ocp1Error.connectionTimeout
    } catch {
      _connectionState.send(.notConnected)
      throw error
    }
    _connectionState.send(.connected)
    if options.flags.contains(.refreshDeviceTreeOnConnection) {
      try? await refreshDeviceTree()
    }
  }

  func disconnect() async throws {
    await removeSubscriptions()
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
