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

#if canImport(Darwin) || canImport(dnssd)

import AsyncAlgorithms
import AsyncExtensions
import Dispatch
import Foundation
import SocketAddress

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
public actor OcaConnectionBroker {
  /// Uniquely identifies an OCA device discovered via DNS Service Discovery.
  ///
  /// A device identifier combines the device's model GUID and serial number to provide
  /// a unique identifier that persists across network sessions. The identifier also
  /// maintains the DNS-SD query information for device resolution.
  public struct DeviceIdentifier: Sendable, Hashable, Identifiable, CustomStringConvertible {
    public typealias ID = String

    public let serialNumber: OcaString
    public let modelGUID: OcaModelGUID
    public let serviceType: OcaNetworkAdvertisingServiceType
    public var name: OcaString

    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.serviceType == rhs.serviceType
        && lhs.modelGUID == rhs.modelGUID
        && lhs.serialNumber == rhs.serialNumber
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(serviceType)
      hasher.combine(modelGUID)
      hasher.combine(serialNumber)
    }

    public var id: ID { "\(serviceType)#\(modelGUID)#\(serialNumber)" }

    public var description: String { id }

    public init(
      serviceType: OcaNetworkAdvertisingServiceType,
      modelGUID: OcaModelGUID,
      serialNumber: OcaString,
      name: OcaString
    ) {
      self.serviceType = serviceType
      self.modelGUID = modelGUID
      self.serialNumber = serialNumber
      self.name = name
    }

    public init?(_ string: String) {
      let components = string.components(separatedBy: "#")
      guard components.count == 3 else { return nil }

      guard let serviceType = OcaNetworkAdvertisingServiceType(components[0]),
            let modelGUID = try? OcaModelGUID(components[1])
      else {
        return nil
      }

      self.init(
        serviceType: serviceType,
        modelGUID: modelGUID,
        serialNumber: components[3],
        name: ""
      )
    }
  }

  /// Represents the type of event emitted by the connection broker.
  public enum EventType: Equatable, Sendable {
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
    public let eventType: EventType
    /// The device identifier associated with this event
    public let deviceIdentifier: DeviceIdentifier
  }

  struct DeviceInfo: Sendable, Hashable {
    let deviceIdentifier: DeviceIdentifier
    let serviceInfo: AnyOcaNetworkAdvertisingServiceInfo

    init(deviceIdentifier: DeviceIdentifier, serviceInfo: any OcaNetworkAdvertisingServiceInfo) {
      self.deviceIdentifier = deviceIdentifier
      self.serviceInfo = AnyOcaNetworkAdvertisingServiceInfo(serviceInfo)
    }

    var serviceType: OcaNetworkAdvertisingServiceType {
      deviceIdentifier.serviceType
    }

    var host: String {
      get throws {
        try serviceInfo.hostname
      }
    }

    var port: UInt16 {
      get throws {
        try serviceInfo.port
      }
    }

    var addresses: [Data] {
      get throws {
        // FIXME: quick and dirty way to preference IPv4 addresses
        try serviceInfo.addresses.sorted { lhs, rhs in
          let lhs = (try? AnySocketAddress(bytes: Array(lhs)).family) ?? sa_family_t(AF_UNSPEC)
          let rhs = (try? AnySocketAddress(bytes: Array(rhs)).family) ?? sa_family_t(AF_UNSPEC)
          return lhs < rhs
        }
      }
    }

    var firstAddress: Data {
      get throws {
        guard let address = try addresses.first else {
          throw Ocp1Error.serviceResolutionFailed
        }
        return address
      }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
      if lhs.deviceIdentifier == rhs.deviceIdentifier {
        let _lhs = try? lhs.serviceInfo.addresses
        let _rhs = try? rhs.serviceInfo.addresses
        return _lhs == _rhs
      } else {
        return false
      }
    }

    func hash(into hasher: inout Hasher) {
      deviceIdentifier.hash(into: &hasher)
      (try? serviceInfo.addresses).hash(into: &hasher)
    }
  }

  private final class DeviceConnection {
    let connection: Ocp1Connection
    var connectionStateMonitor: Task<(), Error>?

    init(
      deviceIdentifier: DeviceIdentifier,
      connection: Ocp1Connection,
      broker: OcaConnectionBroker
    ) {
      self.connection = connection
      connectionStateMonitor = Task { @OcaConnection [weak broker] in
        for try await connectionState in connection.connectionState {
          let event = Event(
            eventType: .connectionStateChanged(connectionState),
            deviceIdentifier: deviceIdentifier
          )
          broker?._eventsContinuation.yield(event)
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

  private final class BrowserMonitor {
    let browser: OcaNetworkAdvertisingServiceBrowser
    var browserMonitor: Task<(), Error>?

    init(serviceType: OcaNetworkAdvertisingServiceType, broker: OcaConnectionBroker) throws {
      #if canImport(Darwin)
      browser = try OcaNetServiceBrowser(serviceType: serviceType)
      #elseif canImport(dnssd)
      browser = try OcaDNSServiceBrowser(serviceType: serviceType)
      #else
      throw Ocp1Error.notImplemented
      #endif
      Task { try await browser.start() }
      browserMonitor = Task { [weak broker] in
        for try await result in browser.browseResults {
          try? await broker?._onBrowseResult(result)
        }
      }
    }

    deinit {
      try? browser.stop()
      browserMonitor?.cancel()
    }
  }

  private static let _defaultServiceTypes = Set([
    OcaNetworkAdvertisingServiceType.tcp,
    OcaNetworkAdvertisingServiceType.udp,
  ])

  /// An async sequence of events emitted by the connection broker.
  ///
  /// This sequence provides notifications about device lifecycle changes and connection state
  /// updates.
  /// Events are emitted when devices are discovered or removed from the network, and when
  /// connection
  /// states change for registered devices.
  ///
  /// - Returns: An async sequence of `Event` instances
  public let events: AsyncStream<Event>

  private var _browsers: [OcaNetworkAdvertisingServiceType: BrowserMonitor]!
  private var _devices = [DeviceIdentifier: DeviceInfo]()
  private var _connections = [DeviceIdentifier: DeviceConnection]()
  private let _connectionOptions: Ocp1ConnectionOptions
  private let _eventsContinuation: AsyncStream<Event>.Continuation

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

  private func _removeConnection(for device: DeviceIdentifier) -> DeviceConnection? {
    if let index = _connections.index(forKey: device) {
      let connection = _connections.values[index]
      _connections.remove(at: index)
      return connection
    } else {
      return nil
    }
  }

  private func _onBrowseResult(_ result: OcaNetworkAdvertisingServiceBrowserResult) async throws {
    var expiringConnection: DeviceConnection?

    let event = try await Event(browserResult: result) // will resolve
    let device = DeviceInfo(deviceIdentifier: event.deviceIdentifier, serviceInfo: result.info)

    switch event.eventType {
    case .deviceRemoved:
      expiringConnection = _removeConnection(for: event.deviceIdentifier)
    case .deviceAdded:
      if let existingDevice = _devices[event.deviceIdentifier],
         existingDevice != device,
         let existingConnection = _removeConnection(for: event.deviceIdentifier)
      {
        // notify connection layer of new address
        if let mutableConnection = existingConnection.connection as? Ocp1MutableConnection {
          mutableConnection.deviceAddress = try device.firstAddress
        }
      }
      // commit the new device
      _devices[event.deviceIdentifier] = device
    default:
      return
    }

    _eventsContinuation.yield(event)
    await expiringConnection?.expire()
  }

  /// Initializes a new connection broker with the specified connection options.
  ///
  /// The broker immediately starts discovering OCA devices on the network via DNS Service Discovery
  /// for both TCP and UDP service types. Device discovery runs continuously in the background.
  ///
  /// - Parameter connectionOptions: Configuration options for connections created by this broker.
  ///   Defaults to standard options if not specified.
  public init(
    connectionOptions: Ocp1ConnectionOptions = .init(),
    serviceTypes: Set<OcaNetworkAdvertisingServiceType>? = nil
  ) {
    _connectionOptions = connectionOptions

    // Create AsyncStream for events
    let (stream, continuation) = AsyncStream<Event>.makeStream()
    events = stream
    _eventsContinuation = continuation

    var browsers = [OcaNetworkAdvertisingServiceType: BrowserMonitor]()
    for serviceType in serviceTypes ?? Self._defaultServiceTypes {
      browsers[serviceType] = try! BrowserMonitor(serviceType: serviceType, broker: self)
    }
    _browsers = browsers
  }

  deinit {
    _eventsContinuation.finish()
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
    connect: Bool = false
  ) async throws {
    let deviceInfo = try _getDeviceInfo(for: device)

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

    let connection: Ocp1Connection

    switch deviceInfo.serviceType {
    case .tcp:
      connection = try await Ocp1TCPConnection(
        deviceAddress: deviceInfo.firstAddress,
        options: _connectionOptions
      )
    case .udp:
      connection = try await Ocp1UDPConnection(
        deviceAddress: deviceInfo.firstAddress,
        options: _connectionOptions
      )
    default:
      throw Ocp1Error.unknownServiceType
    }
    if connect { try await connection.connect() }
    _registerConnection(connection, for: device)
  }

  public func open(device: DeviceIdentifier) async throws {
    try await _open(device: device, connect: false)
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
    try await withDeviceConnection(device) { connection in
      try await connection.disconnect()
    }
    if retiring {
      _devices.removeValue(forKey: device)
    }
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
  public func withDeviceConnection<T>(
    _ device: DeviceIdentifier,
    body: (_ connection: Ocp1Connection) async throws -> T
  ) async throws -> T {
    let connection = try _getRegisteredConnection(for: device)
    return try await body(connection.connection)
  }

  public func withDeviceConnection<T>(
    _ device: DeviceIdentifier,
    body: (_ connection: Ocp1Connection) throws -> T
  ) throws -> T {
    let connection = try _getRegisteredConnection(for: device)
    return try body(connection.connection)
  }
}

extension OcaConnectionBroker.DeviceIdentifier {
  init(serviceInfo: any OcaNetworkAdvertisingServiceInfo) async throws {
    try await serviceInfo.resolve()

    let txtRecord = try serviceInfo.txtRecords

    guard let modelGUID = txtRecord["modelGUID"],
          let serialNumber = txtRecord["serialNumber"]
    else {
      throw Ocp1Error.serviceResolutionFailed
    }

    try self.init(
      serviceType: serviceInfo.serviceType,
      modelGUID: OcaModelGUID(modelGUID),
      serialNumber: OcaString(serialNumber),
      name: serviceInfo.name
    )
  }
}

extension OcaConnectionBroker.Event {
  init(browserResult: OcaNetworkAdvertisingServiceBrowserResult) async throws {
    let deviceIdentifier = try await OcaConnectionBroker
      .DeviceIdentifier(serviceInfo: browserResult.info)

    switch browserResult {
    case .added:
      self = .init(eventType: .deviceAdded, deviceIdentifier: deviceIdentifier)
    case .removed:
      self = .init(eventType: .deviceRemoved, deviceIdentifier: deviceIdentifier)
    }
  }
}

#endif
