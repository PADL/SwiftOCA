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
  /// connect to the OCA device, throwing `Ocp1Error.connectionTimeout` if it times out
  private func _connectDeviceWithTimeout() async throws {
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

  private func _refreshDeviceTreeWithPolicy() async {
    if options.flags.contains(.refreshDeviceTreeOnConnection) {
      logger.debug("refreshing device tree")
      try? await refreshDeviceTree()
    }
  }

  private func _refreshSubscriptionsWithPolicy() async {
    if options.flags.contains(.refreshSubscriptionsOnReconnection) {
      logger.debug("refreshing subscriptions")
      await refreshSubscriptions()
      await refreshCachedObjectProperties()
    }
  }

  private func _updateConnectionState(_ connectionState: Ocp1ConnectionState) {
    logger.trace("_updateConnectionState: \(_connectionState.value) => \(connectionState)")
    _connectionState.send(connectionState)
  }

  func markConnectionConnected() {
    logger.info("connected to \(self)")
    _updateConnectionState(.connected)
    #if canImport(Combine) || canImport(OpenCombine)
    objectWillChange.send()
    #endif
  }

  private func _didConnectDevice() async throws {
    if heartbeatTime > .zero {
      // send keepalive to open UDP connection
      try await sendKeepAlive()
    }

    await _refreshSubscriptionsWithPolicy()
    await _refreshDeviceTreeWithPolicy()
  }

  public func connect() async throws {
    guard !isConnecting else { throw Ocp1Error.connectionAlreadyInProgress }

    _updateConnectionState(.connecting)

    do {
      try await _connectDeviceWithTimeout()
    } catch {
      logger.debug("connection failed: \(error)")
      _updateConnectionState(error.ocp1ConnectionState)
      throw error
    }

    let connectionState = _connectionState.value
    if connectionState == .connecting {
      _startMonitor()
      if !isDatagram { markConnectionConnected() }
      try await _didConnectDevice()
    } else if connectionState != .connected {
      logger.trace("connection failed whilst attempting to connect: \(connectionState)")
      throw connectionState.error ?? .notConnected
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
    _updateConnectionState(.reconnecting)

    logger
      .trace(
        "reconnecting: pauseInterval \(options.reconnectPauseInterval) maxTries \(options.reconnectMaxTries) exponentialBackoffThreshold \(options.reconnectExponentialBackoffThreshold)"
      )

    do {
      try await _withExponentialBackoffPolicy {
        try await _connectDeviceWithTimeout()
        _startMonitor()
        if !isDatagram {
          markConnectionConnected()
          try await _didConnectDevice()
        }
      }

      // for datagram connections, the connection isn't truly open until we have sent a keepAlive
      // packet and received a response. restart the exponential backoff policy awaiting a PDU.
      if isDatagram {
        try await _withExponentialBackoffPolicy {
          switch _connectionState.value {
          case .connected:
            return
          case .reconnecting:
            try await _didConnectDevice()
            throw Ocp1Error.missingKeepalive
          default:
            throw Ocp1Error.connectionTimeout
          }
        }
      }
    } catch {
      _updateConnectionState(error.ocp1ConnectionState)
      throw error
    }

    if !isConnected {
      logger.trace("reconnection abandoned after too many tries")
      _updateConnectionState(.connectionTimedOut)
      throw Ocp1Error.connectionTimeout
    }
  }

  func onMonitorError(id: Int, _ error: Error) async throws {
    logger.trace("monitor task \(id) error: \(error)")

    if _connectionState.value != .notConnected {
      // don't update connection state if we were explicitly disconnected
      _updateConnectionState(error.ocp1ConnectionState)
    }

    if _automaticReconnect, error._isRecoverableConnectionError {
      try await _disconnectDeviceAfterConnectionFailure()
      Task.detached { try await self.reconnectDeviceWithBackoff() }
    }
  }
}
