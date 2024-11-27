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
  var connectionState: Ocp1ConnectionState? {
    switch self {
    case .notConnected:
      .notConnected
    case .connectionTimeout:
      .connectionTimedOut
    default:
      nil
    }
  }
}

private extension Error {
  var ocp1ConnectionState: Ocp1ConnectionState {
    (self as? Ocp1Error)?.connectionState ?? .connectionFailed
  }

  var isRecoverableConnectionError: Bool {
    if let error = self as? Ocp1Error {
      switch error {
      case .missingKeepalive:
        fallthrough
      case .connectionTimeout:
        fallthrough
      case .notConnected:
        return true
      default:
        return false
      }
    } else if let error = self as? Errno {
      switch error {
      case .connectionAbort:
        fallthrough
      case .connectionReset:
        fallthrough
      case .connectionRefused:
        return true
      default:
        return false
      }
    } else {
      return false
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
    let monitor = Monitor(self)
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
      logger.trace("refreshing device tree")
      try? await refreshDeviceTree()
    }
  }

  func updateConnectionState(_ connectionState: Ocp1ConnectionState) {
    logger.trace("_updateConnectionState: \(_connectionState.value) => \(connectionState)")
    _connectionState.send(connectionState)
  }

  private func _didConnectDevice() async throws {
    if !isDatagram {
      // otherwise, set connected state when we receive first keepAlive PDU
      updateConnectionState(.connected)
    }

    _startMonitor()

    if heartbeatTime > .zero {
      // send keepalive to open UDP connection
      try await sendKeepAlive()
    }

    #if canImport(Combine) || canImport(OpenCombine)
    objectWillChange.send()
    #endif

    await refreshSubscriptions()
    await refreshCachedObjectProperties()
    await _refreshDeviceTreeWithPolicy()

    logger.info("connected to \(self)")
  }

  public func connect() async throws {
    logger.trace("connecting...")

    updateConnectionState(.connecting)

    do {
      try await _connectDeviceWithTimeout()
    } catch {
      logger.trace("connection failed: \(error)")
      updateConnectionState(error.ocp1ConnectionState)
      throw error
    }

    let connectionState = _connectionState.value
    if connectionState == .connecting {
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
    await removeSubscriptions()

    updateConnectionState(.notConnected)

    let clearObjectCache = !options.flags.contains(.retainObjectCacheAfterDisconnect)
    try await _disconnectDevice(clearObjectCache: clearObjectCache)
  }
}

// MARK: - reconnection handling

extension Ocp1Connection {
  enum ReconnectionPolicy {
    /// do not try to automatically reconnect on connection failure
    case noReconnect
    /// try to reconnect in the keepAlive monitor task
    case reconnectInMonitor
    /// try to reconnect before sending the next message
    case reconnectOnSend
  }

  ///
  /// Re-connection logic is as follows:
  ///
  /// * If the connection has a heartbeat, then automatic reconnection is only
  ///   managed in the / heartbeat task
  ///
  /// * If the connection does not have a heartbeat, than automatic
  ///   reconnection is managed when / sending a PDU
  ///
  private var _reconnectionPolicy: ReconnectionPolicy {
    if !options.flags.contains(.automaticReconnect) {
      .noReconnect
    } else if heartbeatTime == .zero {
      .reconnectOnSend
    } else {
      .reconnectInMonitor
    }
  }

  /// reconnect to the OCA device with exponential backoff, updating
  /// connectionState
  func reconnectDeviceWithBackoff() async throws {
    var lastError: Error?
    var backoff: Duration = options.reconnectPauseInterval

    updateConnectionState(.reconnecting)

    logger
      .trace(
        "reconnecting: pauseInterval \(options.reconnectPauseInterval) maxTries \(options.reconnectMaxTries) exponentialBackoffThreshold \(options.reconnectExponentialBackoffThreshold)"
      )

    for i in 0..<options.reconnectMaxTries {
      do {
        logger.trace("reconnection attempt \(i + 1)")
        try await _connectDeviceWithTimeout()
        try await _didConnectDevice()
        lastError = nil
        break
      } catch {
        lastError = error
        if options.reconnectExponentialBackoffThreshold.contains(i) {
          backoff *= 2
        }
        logger.trace("reconnection failed with \(error), sleeping for \(backoff)")
        try await Task.sleep(for: backoff)
      }
    }

    if let lastError {
      logger.trace("reconnection abandoned: \(lastError)")
      updateConnectionState(lastError.ocp1ConnectionState)
      throw lastError
    } else if !isDatagram && !isConnected {
      logger.trace("reconnection abandoned after too many tries")
      updateConnectionState(.notConnected)
      throw Ocp1Error.notConnected
    }
  }

  private var _needsReconnectOnSend: Bool {
    guard _reconnectionPolicy == .reconnectOnSend else { return false }

    switch _connectionState.value {
    case .notConnected:
      fallthrough
    case .connectionTimedOut:
      fallthrough
    case .connectionFailed:
      return true
    default:
      return false
    }
  }

  func willSendMessage() async throws {
    guard _needsReconnectOnSend else { return }
    try await reconnectDeviceWithBackoff()
  }

  func didSendMessage(error: Ocp1Error? = nil) async throws {
    if error == nil {
      lastMessageSentTime = Monitor.now
    }

    if _reconnectionPolicy != .reconnectInMonitor, let error,
       let connectionState = error.connectionState
    {
      logger
        .trace(
          "failed to send message: error \(error), new connection state \(connectionState); disconnecting"
        )
      if isConnected {
        updateConnectionState(connectionState)
        try await _disconnectDeviceAfterConnectionFailure()
      }
    }
  }

  func onMonitorError(_ error: Error) async throws {
    guard error.isRecoverableConnectionError else { return }

    logger.trace("expiring connection with policy \(_reconnectionPolicy), error \(error)")

    updateConnectionState(error.ocp1ConnectionState)

    if _reconnectionPolicy == .reconnectInMonitor {
      try await _disconnectDeviceAfterConnectionFailure()
      Task { try await reconnectDeviceWithBackoff() }
    }
  }
}
