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
@preconcurrency
import Foundation
import Logging
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#endif
import SystemPackage

private extension Ocp1Error {
  var ocp1ConnectionState: Ocp1ConnectionState? {
    switch self {
    case .notConnected:
      .notConnected
    case .connectionTimeout:
      .connectionTimedOut
    default:
      nil
    }
  }

  var _isRecoverableConnectionError: Bool {
    switch self {
    case .missingKeepalive:
      fallthrough
    case .connectionTimeout:
      fallthrough
    case .notConnected:
      return true
    default:
      return false
    }
  }
}

private extension Errno {
  var _isRecoverableConnectionError: Bool {
    switch self {
    case .badFileDescriptor:
      fallthrough
    case .brokenPipe:
      fallthrough
    case .socketShutdown:
      fallthrough
    case .connectionAbort:
      fallthrough
    case .connectionReset:
      fallthrough
    case .connectionRefused:
      return true
    default:
      return false
    }
  }
}

private extension Error {
  var ocp1ConnectionState: Ocp1ConnectionState {
    (self as? Ocp1Error)?.ocp1ConnectionState ?? .connectionFailed
  }

  var _isRecoverableConnectionError: Bool {
    if let error = self as? Ocp1Error {
      error._isRecoverableConnectionError
    } else if let error = self as? Errno {
      error._isRecoverableConnectionError
    } else {
      false
    }
  }
}

private extension Ocp1ConnectionState {
  var error: Ocp1Error? {
    switch self {
    case .notConnected:
      fallthrough
    case .connectionFailed:
      return .notConnected
    case .connectionTimedOut:
      return .connectionTimeout
    default:
      return nil
    }
  }
}

// MARK: - monitor task management

extension Ocp1Connection {
  /// start receiveMessages/keepAlive monitor task
  private func _startMonitor() {
    connectionID &+= 1
    let monitor = Monitor(self, id: connectionID)
    monitorTask = Task {
      try await monitor.run()
    }
    self.monitor = monitor
  }

  /// stop receiveMessages/keepAlive monitor task
  private func _stopMonitor() {
    if let monitor {
      monitor.stop()
      self.monitor = nil
    }
    if let monitorTask {
      monitorTask.cancel()
      self.monitorTask = nil
    }
  }
}

// MARK: - connection handling

extension Ocp1Connection {
  /// refresh the device tree if the .refreshDeviceTreeOnConnection flag is set
  private func _refreshDeviceTreeWithPolicy() async {
    if options.flags.contains(.refreshDeviceTreeOnConnection) {
      logger.debug("refreshing device tree")
      try? await refreshDeviceTree()
    }
  }

  /// refresh any existing subscriptions if the .refreshSubscriptionsOnReconnection flag is set
  private func _refreshSubscriptionsWithPolicy() async {
    if options.flags.contains(.refreshSubscriptionsOnReconnection) {
      logger.debug("refreshing subscriptions")
      await refreshSubscriptions()
      await refreshCachedObjectProperties()
    }
  }

  /// refresh per policy in connection option flags
  private func _refreshWithPolicy(isReconnecting: Bool) async throws {
    if isReconnecting {
      await _refreshSubscriptionsWithPolicy()
    }

    await _refreshDeviceTreeWithPolicy()
  }

  /// wrapper to update the connection state, logging the old and new connection states
  private func _updateConnectionState(_ connectionState: Ocp1ConnectionState) {
    logger.trace("_updateConnectionState: \(_connectionState.value) => \(connectionState)")
    _connectionState.send(connectionState)
    #if canImport(Combine) || canImport(OpenCombine)
    objectWillChange.send()
    #endif
  }

  /// update the device connection state, called from the connection (for
  /// stream connections) or the monitor task (for datagram connections)
  func onConnectionOpen() {
    logger.info("connected to \(self)")
    _updateConnectionState(.connected)
  }

  /// for datagram connections, ensure the timeout is at least twice the heartbeat time
  private var _connectionTimeout: Duration {
    let timeout = options.connectionTimeout

    if isDatagram, timeout < heartbeatTime * 2 {
      return heartbeatTime * 2
    } else {
      return timeout
    }
  }

  private func _suspendUntilReconnected() async throws {
    do {
      try await withThrowingTimeout(of: _connectionTimeout) { [self] in
        for await connectionState in _connectionState {
          if connectionState == .connected {
            return
          } else if connectionState == .reconnecting {
            continue
          } else {
            throw connectionState.error ?? .notConnected
          }
        }
      }
    } catch Ocp1Error.responseTimeout {
      throw Ocp1Error.connectionTimeout
    }
  }

  /// `_didConnectDevice()` is to be called subsequent to `_connectDeviceWithTimeout()`
  private func _didConnectDevice(isReconnecting: Bool) async throws {
    _startMonitor()

    if heartbeatTime > .zero {
      // send keepalive, necessary to open UDP connection
      try await sendKeepAlive()
    }

    if isDatagram {
      if isReconnecting {
        // wait for monitor task to receive a packet from the device
        try await _suspendUntilReconnected()
      }
    } else {
      // for stream connections, mark the connection as open immediately
      onConnectionOpen()
    }

    try await _refreshWithPolicy(isReconnecting: isReconnecting)
  }

  /// connect to the OCA device, throwing `Ocp1Error.connectionTimeout` if it times out
  private func _connectDeviceWithTimeout() async throws {
    do {
      try await withThrowingTimeout(of: isDatagram ? .zero : _connectionTimeout) {
        try await self.connectDevice()
      }
    } catch Ocp1Error.responseTimeout {
      throw Ocp1Error.connectionTimeout
    }

    let connectionState = _connectionState.value

    switch connectionState {
    case .connecting:
      fallthrough
    case .reconnecting:
      try await _didConnectDevice(isReconnecting: connectionState == .reconnecting)
    case .connected:
      break
    default:
      logger.trace("connection failed whilst attempting to connect: \(connectionState)")
      throw connectionState.error!
    }
  }

  public func connect() async throws {
    if isConnected {
      throw Ocp1Error.alreadyConnected
    } else if isConnecting {
      throw Ocp1Error.connectionAlreadyInProgress
    }
    _updateConnectionState(.connecting)
    do {
      try await _connectDeviceWithTimeout()
    } catch {
      logger.debug("connection failed: \(error)")
      _updateConnectionState(error.ocp1ConnectionState)
      throw error
    }
  }

  var isConnecting: Bool {
    _connectionState.value == .connecting || _connectionState.value == .reconnecting
  }

  public var isConnected: Bool {
    _connectionState.value == .connected
  }
}

// MARK: - disconnection handling

extension Ocp1Connection {
  private func _disconnectDevice(clearObjectCache: Bool) async throws {
    _stopMonitor()

    try await disconnectDevice()

    if clearObjectCache {
      await self.clearObjectCache()
    }

    #if canImport(Combine) || canImport(OpenCombine)
    objectWillChange.send()
    #endif

    logger.info("disconnected from \(self)")
  }

  /// disconnect from the OCA device, retaining the object cache
  private func _disconnectDeviceAfterConnectionFailure() async throws {
    try await _disconnectDevice(clearObjectCache: false)
  }

  public func disconnect() async throws {
    // explicitly checking for isConnected allows disconnect() to also
    // asynchronously cancel a reconnection
    if isConnected {
      await removeSubscriptions()
    }

    _updateConnectionState(.notConnected)

    let clearObjectCache = !options.flags.contains(.retainObjectCacheAfterDisconnect)
    try await _disconnectDevice(clearObjectCache: clearObjectCache)
  }
}

// MARK: - reconnection handling

extension Ocp1Connection {
  private var _automaticReconnect: Bool {
    options.flags.contains(.automaticReconnect)
  }

  private func _withExponentialBackoffPolicy(
    _ body: () async throws -> ()
  ) async throws {
    var lastError: Error?
    var backoff: Duration = options.reconnectPauseInterval

    for i in 0..<options.reconnectMaxTries {
      do {
        logger.trace("reconnecting: attempt \(i + 1)")
        try await body()
        lastError = nil
        break
      } catch {
        lastError = error
        if options.reconnectExponentialBackoffThreshold.contains(i) {
          backoff *= 2
        }
        logger.trace("reconnection failed with \(error), sleeping for \(backoff)")
        try await Task.sleep(for: backoff)
        // check for asynchronous explicit disconnection and break
        if _connectionState.value == .notConnected {
          logger.debug("reconnection cancelled")
          throw CancellationError()
        }
      }
    }

    if let lastError {
      logger.debug("reconnection abandoned: \(lastError)")
      throw lastError
    }
  }

  /// reconnect to the OCA device with exponential backoff, updating
  /// connectionState
  func reconnectDeviceWithBackoff() async throws {
    logger.info("started reconnection task")

    if isConnected {
      throw Ocp1Error.alreadyConnected
    } else if _connectionState.value == .connecting {
      throw Ocp1Error.connectionAlreadyInProgress
    } else if _connectionState.value != .reconnecting {
      throw _connectionState.value.error!
    }

    logger
      .trace(
        "reconnecting: pauseInterval \(options.reconnectPauseInterval) maxTries \(options.reconnectMaxTries) exponentialBackoffThreshold \(options.reconnectExponentialBackoffThreshold)"
      )

    try await _withExponentialBackoffPolicy {
      try await _connectDeviceWithTimeout()
    }

    if !isConnected {
      logger.trace("reconnection abandoned after too many tries")
      _updateConnectionState(.connectionTimedOut)
      throw Ocp1Error.connectionTimeout
    }
  }

  func onMonitorError(id: Int, _ error: Error) async throws {
    logger.trace("monitor task \(id) error: \(error)")

    let reconnectDevice: Bool

    if _connectionState.value != .notConnected {
      // don't update connection state if we were explicitly disconnected
      reconnectDevice = _automaticReconnect && error._isRecoverableConnectionError
      if reconnectDevice {
        _updateConnectionState(.reconnecting)
      } else {
        _updateConnectionState(error.ocp1ConnectionState)
      }
      try await _disconnectDeviceAfterConnectionFailure()
    } else {
      reconnectDevice = false
    }

    if reconnectDevice {
      precondition(_connectionState.value == .reconnecting)
      Task.detached { try await self.reconnectDeviceWithBackoff() }
    }
  }
}
