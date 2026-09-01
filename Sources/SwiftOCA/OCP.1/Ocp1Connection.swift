//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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
// macOS-only, not Darwin-wide: see Ocp1MachPortSupport.swift.
#if os(macOS)
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
  public let requestCount: UInt64
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

  private let _rootBlock = OcaBlock(objectNumber: OcaRootBlockONo)

  /// Well known managers, immutable
  private let _subscriptionManager = OcaSubscriptionManager()
  private let _deviceManager = OcaDeviceManager()
  private let _networkManager = OcaNetworkManager()

  // The well-known proxies return the deepest subclass resolved so far (a
  // vendor subclass replaces the built-in base instance in the object
  // registry), falling back to the built-in instance. Successive reads can
  // return different instances as deeper classes are resolved; capture the
  // result when a stable observation target is needed.

  public var rootBlock: OcaBlock {
    objects[OcaRootBlockONo] as? OcaBlock ?? _rootBlock
  }

  public var deviceManager: OcaDeviceManager {
    objects[OcaDeviceManagerONo] as? OcaDeviceManager ?? _deviceManager
  }

  public var networkManager: OcaNetworkManager {
    objects[OcaNetworkManagerONo] as? OcaNetworkManager ?? _networkManager
  }

  var subscriptionManager: OcaSubscriptionManager {
    objects[OcaSubscriptionManagerONo] as? OcaSubscriptionManager ?? _subscriptionManager
  }

  @OcaConnection
  final class EventSubscriptions {
    var subscriptions = Set<SubscriptionCancellable>()
  }

  var subscriptions = [OcaEvent: EventSubscriptions]()
  nonisolated(unsafe) var logger = Logger(label: "com.padl.SwiftOCA")
  var connectionID = 0

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
      requestCount: monitor?.requestCount ?? 0,
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

  /// actor for monitoring response and matching them with requests
  var monitor: Monitor?
  var monitorTask: Task<(), Error>?
  var reconnectTask: Task<(), Error>?
  /// Serialises transport writes where a PDU can be written partially and resumed from
  /// an offset. Datagram transports write whole PDUs and bypass it.
  let writeQueue = Ocp1WriteQueue()

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
    add(object: _rootBlock)
    add(object: _subscriptionManager)
    add(object: _deviceManager)
    add(object: _networkManager)
    _configureTracing()
    _configureBatching(options.batchingOptions)
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

  /// Datagram transports must override this. Defaulting to `false` costs a stream subclass
  /// nothing, whereas defaulting to `true` would silently skip write serialisation for one.
  open var isDatagram: Bool {
    false
  }

  /// `true` when `write` delivers a whole PDU, so it can bypass the write queue. Datagram
  /// transports are message-oriented; so is any stream whose `write` cannot split a PDU.
  open var isMessageOriented: Bool {
    isDatagram
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

/// The mutable address state of a socket connection — the candidate addresses,
/// the candidate actually connected to, and an optional host:port to re-resolve —
/// bundled into one value so a backend declares a single `Mutex`-protected cell
/// and the presentation accessors observe a consistent snapshot under one lock.
/// A `struct` (not a class) so the `Mutex` owns and protects the value.
package struct Ocp1DeviceAddressState: Sendable {
  /// Candidate addresses, in preference order.
  package var addresses: [AnySocketAddress]
  /// The candidate the current session connected to (`nil` while disconnected),
  /// which may differ from `addresses.first` if the preferred address failed.
  package var connectedAddress: AnySocketAddress?
  /// When set, the connection resolves this host:port on each connect attempt
  /// instead of using `addresses` directly (NW resolves it natively and leaves
  /// `addresses` empty). `Ocp1NetworkAddress.address` may be a hostname or a
  /// numeric address.
  package let networkAddress: Ocp1NetworkAddress?

  package init(
    addresses: [AnySocketAddress] = [],
    connectedAddress: AnySocketAddress? = nil,
    networkAddress: Ocp1NetworkAddress? = nil
  ) {
    self.addresses = addresses
    self.connectedAddress = connectedAddress
    self.networkAddress = networkAddress
  }

  /// Whether replacing the candidates with `newAddresses` requires migrating a
  /// live connection.
  ///
  /// Only when the candidate actually connected to is no longer offered. A
  /// multi-homed host advertises the same device on every interface, so the set
  /// legitimately gains and loses *secondary* addresses while the connected one
  /// stays reachable; migrating on those tears down a working connection, and
  /// with `.automaticReconnect` it repeats on every advertisement.
  package func requiresMigration(replacingWith newAddresses: [AnySocketAddress]) -> Bool {
    guard let connectedAddress else { return true }
    return !newAddresses.contains(connectedAddress)
  }
}

/// A mutable connection that targets one or more resolved socket addresses (as
/// opposed to, say, a Mach port or a WebSocket URL). Conformers declare only the
/// single `Mutex`-protected ``Ocp1DeviceAddressState`` cell plus the per-candidate
/// connect; this extension derives ``deviceAddresses``, tracks the candidate
/// actually connected to, resolves an optional hostname, and drives first-reachable
/// connect — so the address-handling lives here, not on the base `Ocp1Connection`.
///
/// `package` for now: an internal mechanism shared by the package's socket
/// backends, not yet public API.
package protocol Ocp1MutableSocketAddressConnection: Ocp1Connection {
  /// Single store for the candidate addresses, the connected candidate, and an
  /// optional hostname. A `Mutex` (not actor isolation) because the accessors are
  /// read and written `nonisolated`, off the `@OcaConnection` actor.
  nonisolated var _deviceAddressState: Mutex<Ocp1DeviceAddressState> { get }

  /// Establish the underlying transport to a single resolved candidate. Called
  /// by ``_connectFirstReachableDeviceAddress()`` for each address in turn;
  /// implementations mutate connection state, so this is `@OcaConnection`
  /// isolated like ``connectDevice()`` itself.
  func _connectDevice(to deviceAddress: AnySocketAddress) async throws
}

package extension Ocp1MutableSocketAddressConnection {
  /// The candidate device addresses, in preference order. A hostname can resolve
  /// to several addresses (e.g. an IPv4 and an IPv6 ULA) and only some may be
  /// reachable at any moment; `connectDevice()` tries them in order and connects
  /// to the first that answers. Setting replaces the entire set; an unchanged set
  /// is a no-op.
  ///
  /// A change re-resolves the live connection (`deviceAddressesDidChange()`)
  /// only when the address actually in use is no longer among the candidates.
  /// A multi-homed host advertises the same device on every interface, so the
  /// candidate set legitimately gains and loses *secondary* addresses while the
  /// connected one remains reachable; migrating on those would tear down a
  /// working connection, and with `.automaticReconnect` it would happen again on
  /// every subsequent advertisement.
  nonisolated var deviceAddresses: [AnySocketAddress] {
    get { _deviceAddressState.criticalValue.addresses }
    set {
      let outcome = _deviceAddressState
        .withLock { state -> (migrate: Bool, from: [AnySocketAddress])? in
          guard state.addresses != newValue else { return nil }
          let previous = state.addresses
          let migrate = state.requiresMigration(replacingWith: newValue)
          state.addresses = newValue
          return (migrate, previous)
        }

      guard let outcome else { return }

      let from = outcome.from.map(\._presentationAddress)
      let to = newValue.map(\._presentationAddress)
      if outcome.migrate {
        logger.info("device addresses changed from \(from) to \(to), migrating connection")
        deviceAddressesDidChange()
      } else {
        logger.debug(
          "device addresses changed from \(from) to \(to), keeping connection to \(_currentPresentationAddress)"
        )
      }
    }
  }

  /// Single-address convenience over ``deviceAddresses``: reads the preferred
  /// (first) candidate; writing replaces the whole set with the one address.
  nonisolated var deviceAddress: AnySocketAddress? {
    get { _deviceAddressState.criticalValue.addresses.first }
    set { deviceAddresses = newValue.map { [$0] } ?? [] }
  }

  /// The candidate actually connected to — which may not be
  /// `deviceAddresses.first` if the preferred address was unreachable. `nil`
  /// while disconnected.
  nonisolated var connectedDeviceAddress: AnySocketAddress? {
    _deviceAddressState.criticalValue.connectedAddress
  }

  /// The host:port this connection resolves, if any.
  nonisolated var _deviceNetworkAddress: Ocp1NetworkAddress? {
    _deviceAddressState.criticalValue.networkAddress
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

package extension Ocp1MutableSocketAddressConnection {
  /// The address currently in use: the connected candidate while connected,
  /// otherwise the preferred (first) candidate, read under one lock. Use this —
  /// not `deviceAddresses.first` — for any accessor that describes the live
  /// connection, so a connect that failed over to a non-preferred address is
  /// reported accurately.
  nonisolated var _currentSocketAddress: AnySocketAddress? {
    _deviceAddressState.withLock { $0.connectedAddress ?? $0.addresses.first }
  }

  /// Numeric presentation of the address currently in use, for `connectionPrefix`
  /// and logging. A hostname connection reports its (stable) `host:port` so its
  /// identity doesn't churn as resolution changes the underlying address.
  nonisolated var _currentPresentationAddress: String {
    _deviceAddressState.withLock { state in
      if let networkAddress = state.networkAddress {
        return "\(networkAddress.address):\(networkAddress.port)"
      }
      return (state.connectedAddress ?? state.addresses.first)?._presentationAddress ?? "<unknown>"
    }
  }

  nonisolated func _clearConnectedDeviceAddress() {
    _deviceAddressState.withLock { $0.connectedAddress = nil }
  }

  /// Connect to the first reachable candidate, trying each in preference order
  /// and recording it as ``connectedDeviceAddress``. If a hostname is set it is
  /// re-resolved (off-actor) first, so a device absent at launch or one that
  /// moved is picked up on a later attempt. The overall connect budget
  /// (`_connectionTimeout`) is divided across the candidates, so a black-holed
  /// early address can't consume the whole budget before the next is tried. The
  /// real connect *is* the reachability test — there is no separate probe.
  @OcaConnection
  func _connectFirstReachableDeviceAddress() async throws {
    if let networkAddress = _deviceNetworkAddress {
      // Re-resolve off the actor on each attempt. Set directly (not via the
      // `deviceAddresses` setter) so it doesn't fire `deviceAddressesDidChange()`
      // mid-connect.
      let resolved = await _resolveDeviceAddresses(
        host: networkAddress.address,
        port: networkAddress.port,
        isDatagram: isDatagram
      )
      _deviceAddressState.withLock { $0.addresses = resolved }
    }

    let candidates = _deviceAddressState.withLock { state -> [AnySocketAddress] in
      state.connectedAddress = nil
      return state.addresses
    }
    guard !candidates.isEmpty else { throw Ocp1Error.notConnected }

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
        _deviceAddressState.withLock { $0.connectedAddress = deviceAddress }
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
