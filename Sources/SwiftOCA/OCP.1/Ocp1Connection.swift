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
import Observation

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
  public static let retainObjectCacheAfterDisconnect = Ocp1ConnectionFlags(rawValue: 1 << 2)
  public static let enableTracing = Ocp1ConnectionFlags(rawValue: 1 << 3)
  public static let refreshSubscriptionsOnReconnection = Ocp1ConnectionFlags(rawValue: 1 << 4)

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
  /// controller has not been connected, or was explicitly disconnected
  case notConnected
  /// controller is connecting
  case connecting
  /// controller is connected
  case connected
  /// controller is reconnecting (only if `automaticReconnect` flag is set)
  case reconnecting
  /// missed heartbeat and `automaticReconnect` flag unset
  case connectionTimedOut
  /// connection failed
  case connectionFailed
}

public struct Ocp1ConnectionStatistics: Sendable {
  public let connectionState: Ocp1ConnectionState
  public let connectionID: Int
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
open class Ocp1Connection: Observable, CustomStringConvertible {
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

    if oldFlags.symmetricDifference(options.flags).contains(.enableTracing) {
      _configureTracing()
    }
  }

  /// Keepalive/ping interval (only necessary for UDP, but useful for other transports)
  open var heartbeatTime: Duration {
    .seconds(1)
  }

  let _connectionState = AsyncCurrentValueSubject<Ocp1ConnectionState>(.notConnected)
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
  var connectionID = 0
  let _$observationRegistrar = Observation.ObservationRegistrar()

  private var nextCommandHandle = CommandHandleBase

  var lastMessageSentTime = Monitor.now

  open nonisolated var connectionPrefix: String {
    fatalError(
      "connectionPrefix must be implemented by a concrete subclass of Ocp1Connection"
    )
  }

  public var statistics: Ocp1ConnectionStatistics {
    Ocp1ConnectionStatistics(
      connectionState: currentConnectionState,
      connectionID: connectionID,
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
  @OcaConnection
  final class Monitor: @unchecked Sendable, CustomStringConvertible {
    typealias Continuation = CheckedContinuation<Ocp1Response, Error>

    private let _connection: Weak<Ocp1Connection>
    let _connectionID: Int
    private let _continuations = ManagedCriticalState<[OcaUint32: Continuation]>([:])
    private var _lastMessageReceivedTime = ManagedAtomic<UInt64>(0)

    static var now: UInt64 {
      UInt64(time(nil))
    }

    init(_ connection: Ocp1Connection, id: Int) {
      _connection = Weak(connection)
      _connectionID = id
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
        resumeAllNotConnected()
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

    private func resumeAllNotConnected() {
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

    var description: String {
      let connectionString: String = if let connection { connection.description }
      else { "<null>" }

      return "\(connectionString)[\(_connectionID)]"
    }
  }

  /// actor for monitoring response and matching them with requests
  var monitor: Monitor?
  var monitorTask: Task<(), Error>?

  private func _configureTracing() {
    if options.flags.contains(.enableTracing) {
      logger.logLevel = .trace
    } else {
      logger.logLevel = .info
    }
  }

  public init(options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()) {
    connectionState = _connectionState.eraseToAnyAsyncSequence()
    self.options = options
    add(object: rootBlock)
    add(object: subscriptionManager)
    add(object: deviceManager)
    _configureTracing()
  }

  func getNextCommandHandle() async -> OcaUint32 {
    let handle = nextCommandHandle
    nextCommandHandle += 1
    return handle
  }

  open func connectDevice() async throws {}

  public func clearObjectCache() async {
    objects = [:]
    await rootBlock.refreshAll()
  }

  open func disconnectDevice() async throws {}

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
