//
// Copyright (c) 2025 PADL Software Pty Ltd
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

#if canImport(DNSServiceDiscovery) && canImport(CDNSSD)

import AsyncAlgorithms
import AsyncExtensions
import Dispatch
import DNSServiceDiscovery
import Foundation
import ServiceDiscovery

/// A client-side connection broker that discovers OCA devices via DNS Service Discovery
/// and manages connections to them.
///
/// The connection broker automatically discovers OCA devices on the network using DNS-SD,
/// maintains a registry of available devices, and provides connection management functionality.
/// It supports both TCP and UDP OCA connections and emits events for device lifecycle changes.
///
/// Example usage:
/// ```swift
/// let broker = await OcaConnectionBroker()
///
/// // Listen for device events
/// for await event in broker.events {
///   switch event.eventType {
///   case .deviceAdded:
///     print("Device added: \(event.deviceIdentifier.name)")
///   case .deviceRemoved:
///     print("Device removed: \(event.deviceIdentifier.name)")
///   case .connectionStateChanged(let state):
///     print("Connection state changed: \(state)")
///   }
/// }
///
/// // Connect to a discovered device
/// try await broker.connect(device: deviceIdentifier)
///
/// // Use the connection
/// try await broker.withConnectedDevice(deviceIdentifier) { connection in
///   // Perform operations with the connection
/// }
/// ```
@OcaConnection
public final class OcaConnectionBroker {
  /// Uniquely identifies an OCA device discovered via DNS Service Discovery.
  ///
  /// A device identifier combines the device's model GUID and serial number to provide
  /// a unique identifier that persists across network sessions. The identifier also
  /// maintains the DNS-SD query information for device resolution.
  public struct DeviceIdentifier: Sendable, Hashable {
    public let modelGUID: OcaModelGUID
    public let serialNumber: OcaString
    public let serviceType: OcaNetworkAdvertisingServiceType
    public let name: OcaString

    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.modelGUID == rhs.modelGUID && lhs.serialNumber == rhs.serialNumber && lhs
        .serviceType == rhs.serviceType
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(modelGUID)
      hasher.combine(serialNumber)
      hasher.combine(serviceType)
    }
  }

  /// Represents the type of event emitted by the connection broker.
  public enum EventType: Sendable {
    /// A new device has been discovered on the network
    case deviceAdded
    /// A device has been removed from the network or is no longer available
    case deviceRemoved
    /// The connection state of a device has changed
    case connectionStateChanged(Ocp1ConnectionState)
  }

  /// An event emitted by the connection broker containing information about device lifecycle
  /// changes.
  ///
  /// Events are emitted when devices are discovered or removed from the network, and when
  /// connection states change for registered devices.
  public struct Event: Sendable {
    /// The type of event that occurred
    let eventType: EventType
    /// The device identifier associated with this event
    let deviceIdentifier: DeviceIdentifier
  }

  struct DeviceInfo: Sendable, Hashable {
    let deviceIdentifier: DeviceIdentifier
    let host: String
    let port: UInt16

    var serviceType: OcaNetworkAdvertisingServiceType {
      deviceIdentifier.serviceType
    }

    private var hints: addrinfo {
      var info = addrinfo()
      info.ai_family = AF_UNSPEC
      info.ai_socktype = serviceType.socktype
      return info
    }

    func resolve() throws -> [Data] {
      var addrInfo: UnsafeMutablePointer<addrinfo>?
      var hints = hints

      if getaddrinfo(host, nil, &hints, &addrInfo) < 0 {
        throw Ocp1Error.remoteDeviceResolutionFailed
      }

      defer {
        freeaddrinfo(addrInfo)
      }

      guard let firstAddr = addrInfo else {
        throw Ocp1Error.remoteDeviceResolutionFailed
      }

      return sequence(first: firstAddr, next: { $0.pointee.ai_next }).map { addr in
        Data(bytes: addr.pointee.ai_addr, count: Int(addr.pointee.ai_addrlen))
      }
    }
  }

  private final class DeviceConnection {
    let connection: Ocp1Connection
    var connectionStateMonitor: Task<(), Error>?
    weak var owner: OcaConnectionBroker?

    init(
      deviceIdentifier: DeviceIdentifier,
      connection: Ocp1Connection,
      broker: OcaConnectionBroker
    ) {
      self.connection = connection
      owner = broker
      connectionStateMonitor = Task { @OcaConnection in
        for try await connectionState in connection.connectionState {
          let event = Event(
            eventType: .connectionStateChanged(connectionState),
            deviceIdentifier: deviceIdentifier
          )
          await owner?._events.send(event)
        }
      }
    }

    func expire() async {
      connectionStateMonitor?.cancel()
      connectionStateMonitor = nil
      try? await connection.disconnect()
    }

    deinit {
      connectionStateMonitor?.cancel()
    }
  }

  /// An async sequence of events emitted by the connection broker.
  ///
  /// This sequence provides notifications about device lifecycle changes and connection state
  /// updates.
  /// Events are emitted when devices are discovered or removed from the network, and when
  /// connection
  /// states change for registered devices.
  ///
  /// - Returns: An async sequence of `Event` instances
  public var events: AnyAsyncSequence<Event> { _events.eraseToAnyAsyncSequence() }

  private let _sd = DNSServiceDiscovery()
  private var _devices = [DeviceIdentifier: DeviceInfo]()
  private var _connections = [DeviceIdentifier: DeviceConnection]()
  private let _connectionOptions: Ocp1ConnectionOptions
  private let _events = AsyncChannel<Event>()

  private func _getRegisteredConnection(for device: DeviceIdentifier) throws -> DeviceConnection {
    guard let connection = _connections[device] else {
      throw Ocp1Error.notConnected
    }
    return connection
  }

  private func _getDeviceInfo(for device: DeviceIdentifier) throws -> DeviceInfo {
    guard let deviceInfo = _devices[device] else {
      throw Ocp1Error.endpointNotRegistered
    }
    return deviceInfo
  }

  private func _updateDevices(_ instances: [DNSServiceInstance]) async {
    let resolvedDevices = await withCheckedContinuation { continuation in
      var resolvedDevices = Set<DeviceInfo>()

      guard !instances.isEmpty else {
        continuation.resume(returning: resolvedDevices)
        return
      }

      var remainingLookups = instances.count

      for instance in instances {
        _sd.lookup(DNSServiceQuery(instance)) { result in
          if let deviceInfo = try? result.get().first?.deviceInfo {
            resolvedDevices.insert(deviceInfo)
          }
          remainingLookups -= 1
          if remainingLookups == 0 {
            continuation.resume(returning: resolvedDevices)
          }
        }
      }
    }

    await _updateDevices(resolvedDevices)
  }

  private func _removeConnection(for device: DeviceIdentifier) -> DeviceConnection? {
    if let index = _connections.index(forKey: device) {
      let connection = _connections.values[index]
      _connections.remove(at: index)
      return connection
    } else {
      return nil
    }
  }

  private struct ExistingConnectionState {
    let deviceInfo: DeviceInfo
    let connected: Bool
    let subscriptions: [OcaEvent]?
  }

  // unfortunately swift-dns-service-discovery doesn't provide an interface to indicate
  // when services are added or removed, so we need to compute the union of sets each
  // time
  private func _updateDevices(_ devices: Set<DeviceInfo>) async {
    let deviceIdentifiers = Set(devices.map(\.deviceIdentifier))
    let addedDevices = deviceIdentifiers.subtracting(_devices.keys)
    let removedDevices = Set(_devices.keys).subtracting(deviceIdentifiers)
    var expiredConnections = [DeviceConnection]()
    var changedConnections = [ExistingConnectionState]()

    for device in removedDevices {
      if let oldConnection = _removeConnection(for: device) {
        expiredConnections.append(oldConnection)
      }
      _devices.removeValue(forKey: device)
    }

    for device in devices {
      if let existingDevice = _devices[device.deviceIdentifier],
         existingDevice != device,
         let existingConnection = _removeConnection(for: device.deviceIdentifier)
      {
        let subscriptions = _connectionOptions.flags
          .contains(.refreshSubscriptionsOnReconnection) ?
          Array(existingConnection.connection.subscriptions.keys) : nil
        let existingConnectionInfo = ExistingConnectionState(
          deviceInfo: device,
          connected: existingConnection.connection.isConnected,
          subscriptions: subscriptions
        )
        changedConnections.append(existingConnectionInfo)
        expiredConnections.append(existingConnection)
      }
      _devices[device.deviceIdentifier] = device
    }

    for connectionState in changedConnections {
      try? await _open(
        device: connectionState.deviceInfo.deviceIdentifier,
        connect: connectionState.connected,
        subscriptions: connectionState.subscriptions
      )
    }

    // to avoid any reentrancy issues, any asynchronous methods must be called
    // after we've updated the local _devices dictionary.
    for event in removedDevices
      .map({ Event(eventType: .deviceRemoved, deviceIdentifier: $0) }) + addedDevices.map({ Event(
        eventType: .deviceAdded,
        deviceIdentifier: $0
      ) })
    {
      await _events.send(event)
    }

    for connection in expiredConnections {
      await connection.expire()
    }
  }

  private var _sdQueries = [OcaNetworkAdvertisingServiceType: CancellationToken]()

  private func _sdQuery(serviceType: OcaNetworkAdvertisingServiceType) {
    _sdQueries[serviceType] = _sd.subscribe(
      to: DNSServiceQuery(type: serviceType.dnsServiceType),
      onNext: { result in
        guard let instances = try? result.get() else { return }
        Task { await self._updateDevices(instances) }
      },
      onComplete: { _ in }
    )
  }

  /// Initializes a new connection broker with the specified connection options.
  ///
  /// The broker immediately starts discovering OCA devices on the network via DNS Service Discovery
  /// for both TCP and UDP service types. Device discovery runs continuously in the background.
  ///
  /// - Parameter connectionOptions: Configuration options for connections created by this broker.
  ///   Defaults to standard options if not specified.
  public init(connectionOptions: Ocp1ConnectionOptions = .init()) async {
    _connectionOptions = connectionOptions
    _sdQuery(serviceType: .tcp)
    _sdQuery(serviceType: .udp)
  }

  deinit {
    _sdQueries.values.forEach { $0.cancel() }
  }

  private func _registerConnection(_ connection: Ocp1Connection, for device: DeviceIdentifier) {
    _connections[device] = DeviceConnection(
      deviceIdentifier: device,
      connection: connection,
      broker: self
    )
  }

  func _open(
    device: DeviceIdentifier,
    connect: Bool = false,
    subscriptions: [OcaEvent]? = nil
  ) async throws {
    let deviceInfo = try _getDeviceInfo(for: device)
    var lastError: Error?

    if let connection = try? _getRegisteredConnection(for: device) {
      let connection = connection.connection
      if connect {
        do {
          try await connection.connect()
        } catch Ocp1Error.alreadyConnected {
        } catch Ocp1Error.connectionAlreadyInProgress {}
      }
      return
    }

    for address in try deviceInfo.resolve() {
      let connection: Ocp1Connection

      switch deviceInfo.serviceType {
      case .tcp:
        connection = try Ocp1TCPConnection(
          deviceAddress: address,
          options: _connectionOptions
        )
      case .udp:
        connection = try Ocp1UDPConnection(
          deviceAddress: address,
          options: _connectionOptions
        )
      default:
        continue
      }

      do {
        if connect { try await connection.connect() }
        if let subscriptions { await connection.addSubscriptions(for: subscriptions) }
        _registerConnection(connection, for: device)
      } catch {
        lastError = error
      }
    }

    if let lastError {
      throw lastError
    }
  }

  /// Establishes a connection to the specified device.
  ///
  /// This method creates a connection to the device if one doesn't exist, and then attempts to
  /// connect.
  /// If a connection already exists and is connected, this method has no effect. If the connection
  /// exists
  /// but is not connected, it will attempt to reconnect.
  ///
  /// The connection type (TCP or UDP) is determined by the device's advertised service type
  /// discovered
  /// via DNS-SD. Multiple network addresses may be attempted if the device resolves to multiple
  /// addresses.
  ///
  /// - Parameter device: The device identifier for the device to connect to
  /// - Throws: `Ocp1Error.endpointNotRegistered` if the device hasn't been discovered
  /// - Throws: `Ocp1Error.remoteDeviceResolutionFailed` if the device's network address cannot be
  /// resolved
  /// - Throws: Connection-specific errors if the connection attempt fails
  public func connect(device: DeviceIdentifier) async throws {
    try await _open(device: device, connect: true)
  }

  /// Disconnects from the specified device.
  ///
  /// This method gracefully disconnects from the device and optionally removes it from the device
  /// registry.
  /// The connection object remains registered unless `retiring` is true, allowing for reconnection
  /// later.
  ///
  /// - Parameter device: The device identifier for the device to disconnect from
  /// - Parameter retiring: If true, removes the device from the registry after disconnecting.
  ///   Defaults to false.
  /// - Throws: `Ocp1Error.notConnected` if no connection exists for the device
  /// - Throws: Connection-specific errors during disconnection
  public func disconnect(device: DeviceIdentifier, retiring: Bool = false) async throws {
    try await withConnectedDevice(device) { connection in
      try await connection.disconnect()
    }
    if retiring {
      _devices.removeValue(forKey: device)
    }
  }

  /// Returns the current connection state for the specified device.
  ///
  /// This method provides the current state of the connection to the device, such as whether
  /// it's connected, disconnected, or in a transitional state.
  ///
  /// - Parameter device: The device identifier to query
  /// - Returns: The current connection state
  /// - Throws: `Ocp1Error.notConnected` if no connection exists for the device
  public func getConnectionState(device: DeviceIdentifier) async throws -> Ocp1ConnectionState {
    try _getRegisteredConnection(for: device).connection._connectionState.value
  }

  /// Executes a closure with a connected device, ensuring the connection is available.
  ///
  /// This method provides safe access to a device connection by ensuring the device is connected
  /// before executing the provided closure. The connection is guaranteed to be available within
  /// the closure's execution context.
  ///
  /// Example usage:
  /// ```swift
  /// let deviceName = try await broker.withConnectedDevice(deviceId) { connection in
  ///   let root = try await connection.rootBlock
  ///   return try await root.getDeviceName()
  /// }
  /// ```
  ///
  /// - Parameter device: The device identifier for the device to access
  /// - Parameter body: A closure that receives the connection and returns a value of type T
  /// - Returns: The value returned by the closure
  /// - Throws: `Ocp1Error.notConnected` if no connection exists or the device is not connected
  /// - Throws: Any error thrown by the closure
  public func withConnectedDevice<T>(
    _ device: DeviceIdentifier,
    body: (_ connection: Ocp1Connection) async throws -> T
  ) async throws -> T {
    let connection = try _getRegisteredConnection(for: device)
    guard connection.connection.isConnected else { throw Ocp1Error.notConnected }
    return try await body(connection.connection)
  }
}

extension OcaNetworkAdvertisingServiceType {
  var dnsServiceType: DNSServiceType {
    DNSServiceType(rawValue: rawValue)
  }

  var socktype: CInt {
    switch self {
    case .udp: SOCK_DGRAM
    default: SOCK_STREAM
    }
  }

  init?(dnsServiceType: DNSServiceType) {
    self.init(rawValue: dnsServiceType.rawValue)
  }
}

extension DNSServiceInstance {
  var deviceIdentifier: OcaConnectionBroker.DeviceIdentifier? {
    guard let modelGUID = txtRecord["modelGUID"],
          let serialNumber = txtRecord["serialNumber"],
          let serviceType = OcaNetworkAdvertisingServiceType(dnsServiceType: type)
    else {
      return nil
    }

    return try? OcaConnectionBroker.DeviceIdentifier(
      modelGUID: OcaModelGUID(modelGUID),
      serialNumber: OcaString(serialNumber),
      serviceType: serviceType,
      name: name
    )
  }

  var deviceInfo: OcaConnectionBroker.DeviceInfo? {
    guard let deviceIdentifier else { return nil }
    guard let host, let port else { return nil }

    return OcaConnectionBroker.DeviceInfo(
      deviceIdentifier: deviceIdentifier,
      host: host,
      port: port
    )
  }
}

extension DNSServiceQuery: @retroactive @unchecked Sendable {}

#endif
