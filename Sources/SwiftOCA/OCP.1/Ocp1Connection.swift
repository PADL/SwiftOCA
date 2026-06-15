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
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
@preconcurrency
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Logging
import SocketAddress
import Synchronization

package let Ocp1MaximumDatagramPduSize = 1500

#if canImport(IORing)
public typealias Ocp1UDPConnection = Ocp1IORingDatagramConnection
public typealias Ocp1TCPConnection = Ocp1IORingStreamConnection
#elseif canImport(FlyingSocks)
public typealias Ocp1UDPConnection = Ocp1FlyingSocksDatagramConnection
public typealias Ocp1TCPConnection = Ocp1FlyingSocksStreamConnection
#elseif canImport(CoreFoundation) && NonEmbeddedBuild
public typealias Ocp1UDPConnection = Ocp1CFSocketUDPConnection
public typealias Ocp1TCPConnection = Ocp1CFSocketTCPConnection
#endif

#if os(macOS) || os(iOS)
// note: not available on Linux because some Foundation networking unavailable
public typealias Ocp1WSConnection = Ocp1FlyingFoxConnection
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
#if swift(>=6.0)
internal import CoreFoundation
#else
@_implementationOnly import CoreFoundation
#endif

package let SOCK_STREAM = Int32(Glibc.SOCK_STREAM.rawValue)
package let SOCK_DGRAM = Int32(Glibc.SOCK_DGRAM.rawValue)
#endif

public let OcaTcpConnectionPrefix = "oca/tcp"
public let OcaUdpConnectionPrefix = "oca/udp"
public let OcaWebSocketTcpConnectionPrefix = "ocaws/tcp"
public let OcaLocalConnectionPrefix = "oca/local"
public let OcaDatagramProxyConnectionPrefix = "oca/dg-proxy"
#if canImport(Darwin)
public let OcaMachPortConnectionPrefix = "oca/mach"
#endif

public struct Ocp1ConnectionFlags: OptionSet, Sendable {
  public static let automaticReconnect = Ocp1ConnectionFlags(rawValue: 1 << 0)
  public static let refreshDeviceTreeOnConnection = Ocp1ConnectionFlags(rawValue: 1 << 1)
  public static let retainObjectCacheAfterDisconnect = Ocp1ConnectionFlags(rawValue: 1 << 2)
  public static let enableTracing = Ocp1ConnectionFlags(rawValue: 1 << 3)
  public static let refreshSubscriptionsOnReconnection = Ocp1ConnectionFlags(rawValue: 1 << 4)
  /// Disable TLS certificate verification.
  public static let disableCertificateVerification = Ocp1ConnectionFlags(rawValue: 1 << 5)

  public typealias RawValue = UInt

  public let rawValue: RawValue

  public init(rawValue: RawValue) {
    self.rawValue = rawValue
  }
}

public struct Ocp1ConnectionOptions: Sendable {
  public struct BatchingOptions: Equatable, Sendable {
    let batchSize: UInt32?
    let batchThreshold: Duration?

    // if batchSize / batchThrehsold are nil, sensible defaults will be used
    // based on the connection type
    public init(batchSize: UInt32? = nil, batchThreshold: Duration? = nil) throws {
      if let batchSize, batchSize < Ocp1Connection.MinimumPduSize {
        throw Ocp1Error.status(.parameterError)
      }
      if let batchThreshold, batchThreshold == .zero {
        throw Ocp1Error.status(.parameterError)
      }
      self.batchSize = batchSize
      self.batchThreshold = batchThreshold
    }
  }

  public let flags: Ocp1ConnectionFlags
  public let connectionTimeout: Duration
  public let responseTimeout: Duration
  public let reconnectMaxTries: Int
  public let reconnectPauseInterval: Duration
  public let reconnectExponentialBackoffThreshold: Range<Int>
  public let batchingOptions: BatchingOptions?

  public init(
    flags: Ocp1ConnectionFlags = .refreshDeviceTreeOnConnection,
    connectionTimeout: Duration = .seconds(2),
    responseTimeout: Duration = .seconds(5),
    reconnectMaxTries: Int = 15,
    reconnectPauseInterval: Duration = .milliseconds(250),
    reconnectExponentialBackoffThreshold: Range<Int> = 3..<8,
    batchingOptions: BatchingOptions? = nil
  ) {
    self.flags = flags
    self.connectionTimeout = connectionTimeout
    self.responseTimeout = responseTimeout
    self.reconnectMaxTries = reconnectMaxTries
    self.reconnectPauseInterval = reconnectPauseInterval
    self.reconnectExponentialBackoffThreshold = reconnectExponentialBackoffThreshold
    self.batchingOptions = batchingOptions
  }

  @available(*, deprecated, message: "use Ocp1ConnectionFlags initializer")
  public init(
    automaticReconnect: Bool = false,
    connectionTimeout: Duration = .seconds(2),
    responseTimeout: Duration = .seconds(2),
    refreshDeviceTreeOnConnection: Bool = true,
    reconnectMaxTries: Int = 15,
    reconnectPauseInterval: Duration = .milliseconds(250),
    reconnectExponentialBackoffThreshold: Range<Int> = 3..<8,
    batchingOptions: BatchingOptions? = nil
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
      reconnectExponentialBackoffThreshold: reconnectExponentialBackoffThreshold,
      batchingOptions: batchingOptions
    )
  }

  func copy(
    flags: Ocp1ConnectionFlags? = nil,
    connectionTimeout: Duration? = nil,
    responseTimeout: Duration? = nil,
    reconnectMaxTries: Int? = nil,
    reconnectPauseInterval: Duration? = nil,
    reconnectExponentialBackoffThreshold: Range<Int>? = nil,
    batchingOptions: BatchingOptions? = nil
  ) -> Self {
    Self(
      flags: flags ?? self.flags,
      connectionTimeout: connectionTimeout ?? self.connectionTimeout,
      responseTimeout: responseTimeout ?? self.responseTimeout,
      reconnectMaxTries: reconnectMaxTries ?? self.reconnectMaxTries,
      reconnectPauseInterval: reconnectPauseInterval ?? self.reconnectPauseInterval,
      reconnectExponentialBackoffThreshold:
      reconnectExponentialBackoffThreshold ?? self.reconnectExponentialBackoffThreshold,
      batchingOptions: batchingOptions ?? self.batchingOptions
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

public struct Ocp1ConnectionStatistics: Sendable, CustomStringConvertible {
  public let connectionState: Ocp1ConnectionState
  public let connectionID: Int
  public var isConnected: Bool { connectionState == .connected }
  public let requestCount: Int
  public let outstandingRequests: [OcaUint32]
  public let cachedObjectCount: Int
  public let subscribedEvents: [OcaEvent]
  public let lastMessageSentTime: Date
  public let lastMessageReceivedTime: Date?

  public var description: String { """
  \(type(of: self))(
    connectionState: \(connectionState),
    connectionID: \(connectionID),
    isConnected: \(isConnected),
    lastMessageSentTime: \(lastMessageSentTime),
    lastMessageReceivedTime: \(lastMessageReceivedTime.map(String.init(describing:)) ?? "<nil>"),
    requestCount: \(requestCount),
    outstandingRequests: \(outstandingRequests),
    cachedObjectCount: \(cachedObjectCount),
    subscribedEventCount: \(subscribedEvents.count),
    subscribedEvents: \(subscribedEvents)
  )
  """
  }
}

private let CommandHandleBase = OcaUint32(100)

@OcaConnection
open class Ocp1Connection: CustomStringConvertible {
  package nonisolated static let MinimumPduSize = 1 /* SyncVal */ + Ocp1Header.HeaderSize

  public internal(set) var options: Ocp1ConnectionOptions

  public func set(options: Ocp1ConnectionOptions) async throws {
    let oldFlags = self.options.flags
    let oldBatchOptions = self.options.batchingOptions
    self.options = options

    if oldFlags.symmetricDifference(options.flags).contains(.enableTracing) {
      _configureTracing()
    }

    if oldBatchOptions != options.batchingOptions {
      try? await batcher.dequeue()
      _configureBatching(options.batchingOptions)
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
  nonisolated(unsafe) var logger = Logger(label: "com.padl.SwiftOCA")
  var connectionID = 0

  private var nextCommandHandle = CommandHandleBase
  private var continuousClockReference = ContinuousClockReference()

  var lastMessageSentTime = ContinuousClock.recentPast

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
      lastMessageSentTime: continuousClockReference.date(for: lastMessageSentTime),
      lastMessageReceivedTime: monitor?.lastMessageReceivedTime != nil ? continuousClockReference
        .date(for: monitor!.lastMessageReceivedTime) : nil
    )
  }

  /// for datagram connections, ensure the timeout is at least twice the heartbeat time
  var responseTimeout: Duration {
    let timeout = options.responseTimeout

    if isDatagram, timeout < heartbeatTime * 2 {
      return heartbeatTime * 2
    } else {
      return timeout
    }
  }

  /// Monitor for matching requests and responses.
  /// Deliberately not isolated to `@OcaConnection` so that the
  /// receiveMessages/keepAlive loops run on the default executor and
  /// are not starved by work on other connections sharing the global actor.
  final class Monitor: Sendable, CustomStringConvertible {
    typealias Continuation = UnsafeContinuation<Ocp1Response, Error>

    private let _connection: Weak<Ocp1Connection>
    let _connectionID: Int
    private let _continuations = Mutex<[OcaUint32: Continuation]>([:])
    private let _lastMessageReceivedTime = Mutex<ContinuousClock.Instant>(.now)

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
        _resumeAllNotConnected()
      }
    }

    func stop() {
      _resumeAllNotConnected()
    }

    func register(handle: OcaUint32, continuation: Continuation) {
      _continuations.withLock { $0[handle] = continuation }
    }

    private func _resumeAllNotConnected() {
      let continuations = _continuations.withLock { continuations in
        let values = Array(continuations.values)
        continuations.removeAll()
        return values
      }
      for continuation in continuations {
        continuation.resume(throwing: Ocp1Error.notConnected)
      }
    }

    func resumeTimedOut(handle: OcaUint32) throws {
      let continuation = try _findAndRemoveContinuation(for: handle)
      continuation.resume(with: Result<Ocp1Response, Ocp1Error>.failure(Ocp1Error.responseTimeout))
    }

    func resume(with response: Ocp1Response) throws {
      let continuation = try _findAndRemoveContinuation(for: response.handle)
      continuation.resume(with: Result<Ocp1Response, Ocp1Error>.success(response))
    }

    private func _findAndRemoveContinuation(
      for handle: OcaUint32
    ) throws -> Continuation {
      try _continuations.withLock { continuations in
        guard let continuation = continuations[handle] else {
          throw Ocp1Error.invalidHandle
        }
        continuations.removeValue(forKey: handle)
        return continuation
      }
    }

    func updateLastMessageReceivedTime() {
      _lastMessageReceivedTime.withLock { $0 = .now }
    }

    fileprivate var outstandingRequests: [OcaUint32] {
      _continuations.withLock { Array($0.keys) }
    }

    var lastMessageReceivedTime: ContinuousClock.Instant {
      _lastMessageReceivedTime.withLock { $0 }
    }

    var description: String {
      "Ocp1Connection.Monitor[\(_connectionID)]"
    }
  }

  /// actor for monitoring response and matching them with requests
  var monitor: Monitor?
  var monitorTask: Task<(), Error>?
  var reconnectTask: Task<(), Error>?
  var batcher: Ocp1MessageBatcher!

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
    _configureBatching(options.batchingOptions)
  }

  func getNextCommandHandle() async -> OcaUint32 {
    let handle = nextCommandHandle
    nextCommandHandle += 1
    return handle
  }

  open func connectDevice() async throws {}

  public func clearObjectCache() async {
    objects = [:]
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

  /// Plaintext transports return `false`; TLS-wrapping transports override.
  open var hasTransportLayerSecurity: Bool {
    false
  }

  /// The local socket address of the connection, if available.
  open var localAddress: Data? {
    nil
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

/// A mutable connection that targets one or more resolved socket addresses (as
/// opposed to, say, a Mach port or a WebSocket URL). Conformers declare only the
/// two storage cells plus the per-candidate connect; this extension derives the
/// public ``deviceAddresses``, tracks the candidate actually connected to, and
/// drives first-reachable connect — so the address-handling lives here, with the
/// backends, rather than on the base `Ocp1Connection`.
///
/// The protocol is public so its extension can witness the public
/// `deviceAddresses`; the storage/connect requirements are `@_spi` SwiftOCA
/// internals.
public protocol Ocp1MutableSocketAddressConnection: Ocp1Connection {
  /// Backing store for the candidate addresses, parsed, in preference order.
  @_spi(SwiftOCAPrivate)
  nonisolated var _deviceAddresses: Mutex<[AnySocketAddress]> { get }

  /// Backing store for the candidate actually connected to (`nil` while
  /// disconnected).
  @_spi(SwiftOCAPrivate)
  nonisolated var _connectedDeviceAddress: Mutex<AnySocketAddress?> { get }

  /// Establish the underlying transport to a single resolved candidate. Called
  /// by ``_connectFirstReachableDeviceAddress()`` for each address in turn;
  /// implementations mutate connection state, so this is `@OcaConnection`
  /// isolated like ``connectDevice()`` itself.
  @_spi(SwiftOCAPrivate)
  func _connectDevice(to deviceAddress: AnySocketAddress) async throws
}

public extension Ocp1MutableSocketAddressConnection {
  /// The candidate device addresses, in preference order. A hostname can resolve
  /// to several addresses (e.g. an IPv4 and an IPv6 ULA) and only some may be
  /// reachable at any moment; `connectDevice()` tries them in order and connects
  /// to the first that answers. Setting replaces the entire set; a change
  /// re-resolves the live connection (`deviceAddressesDidChange()`), an unchanged
  /// set is a no-op.
  nonisolated var deviceAddresses: [AnySocketAddress] {
    get { _deviceAddresses.criticalValue }
    set {
      let changed = _deviceAddresses.withLock { stored -> Bool in
        guard stored != newValue else { return false }
        stored = newValue
        return true
      }
      if changed { deviceAddressesDidChange() }
    }
  }

  /// Single-address convenience over ``deviceAddresses``: reads the preferred
  /// (first) candidate; writing replaces the whole set with the one address.
  nonisolated var deviceAddress: AnySocketAddress? {
    get { _deviceAddresses.criticalValue.first }
    set { deviceAddresses = newValue.map { [$0] } ?? [] }
  }

  /// The candidate actually connected to — which may not be
  /// `deviceAddresses.first` if the preferred address was unreachable. `nil`
  /// while disconnected.
  nonisolated var connectedDeviceAddress: AnySocketAddress? {
    _connectedDeviceAddress.criticalValue
  }

  // MARK: `Data`-valued convenience for compatibility with callers that work in
  // raw `sockaddr` `Data` rather than `AnySocketAddress`.

  /// The candidate addresses as `sockaddr` `Data`. Setting drops any entry that
  /// does not parse rather than discarding the whole set.
  nonisolated var deviceAddressData: [Data] {
    get { deviceAddresses.map(\.data) }
    set { deviceAddresses = newValue.compactMap { try? AnySocketAddress(bytes: Array($0)) } }
  }
}

@_spi(SwiftOCAPrivate)
public extension Ocp1MutableSocketAddressConnection {
  /// The address currently in use: the connected candidate while connected,
  /// otherwise the preferred (first) candidate. Use this — not
  /// `deviceAddresses.first` — for any accessor that describes the live
  /// connection, so a connect that failed over to a non-preferred address is
  /// reported accurately.
  nonisolated var _currentSocketAddress: AnySocketAddress? {
    _connectedDeviceAddress.criticalValue ?? _deviceAddresses.criticalValue.first
  }

  /// Numeric presentation ("host:port"/"[v6]:port") of the address currently in
  /// use, for `connectionPrefix` and logging.
  nonisolated var _currentPresentationAddress: String {
    _currentSocketAddress?._presentationAddress ?? "<unknown>"
  }

  nonisolated func _clearConnectedDeviceAddress() {
    _connectedDeviceAddress.withLock { $0 = nil }
  }

  /// Connect to the first candidate in ``deviceAddresses`` for which
  /// ``_connectDevice(to:)`` succeeds, trying each in preference order, and
  /// record it as ``connectedDeviceAddress``. The overall connect budget
  /// (`_connectionTimeout`, applied by `_connectDeviceWithTimeout`) is divided
  /// across the candidates, so a black-holed early address (SYN dropped, no RST)
  /// cannot consume the whole budget before the next candidate is tried. The
  /// real connect *is* the reachability test — there is no separate probe.
  @OcaConnection
  func _connectFirstReachableDeviceAddress() async throws {
    let candidates = _deviceAddresses.criticalValue
    guard !candidates.isEmpty else { throw Ocp1Error.notConnected }

    _connectedDeviceAddress.withLock { $0 = nil }

    // Single candidate: rely on the outer `_connectDeviceWithTimeout`. Multiple:
    // give each an equal slice so their sum fits the outer budget (which would
    // otherwise abort the whole connect at the first candidate's expiry).
    let perCandidateTimeout: Duration = candidates.count > 1
      ? _connectionTimeout / candidates.count
      : .zero

    var lastError: Error?
    for deviceAddress in candidates {
      do {
        if perCandidateTimeout > .zero {
          try await withThrowingTimeout(of: perCandidateTimeout, clock: .continuous) {
            [self] in try await _connectDevice(to: deviceAddress)
          }
        } else {
          try await _connectDevice(to: deviceAddress)
        }
        _connectedDeviceAddress.withLock { $0 = deviceAddress }
        if candidates.count > 1 {
          logger.debug("connectDevice: connected to \(deviceAddress._presentationAddress)")
        }
        return
      } catch {
        lastError = error
        logger.debug("connectDevice: \(deviceAddress._presentationAddress) unreachable: \(error)")
      }
    }
    throw lastError ?? Ocp1Error.notConnected
  }
}
