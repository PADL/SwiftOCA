//
// Copyright (c) 2026 PADL Software Pty Ltd
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

#if canImport(Network)

import AsyncExtensions
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import Network
@_spi(SwiftOCAPrivate)
import SwiftOCA
import Synchronization

/// Base class for OCP.1 datagram device endpoints on Network.framework.
/// NWListener demuxes inbound UDP datagrams to per-peer NWConnections;
/// concrete subclasses supply the NWParameters (plain UDP, or DTLS via
/// `NWProtocolTLS.Options`) and controller metadata.
@OcaDevice
open class Ocp1NWDatagramDeviceEndpoint: OcaDeviceEndpointPrivate,
  OcaBonjourRegistrableDeviceEndpoint,
  CustomStringConvertible
{
  package typealias ControllerType = Ocp1NWDatagramController

  open var controllers: [OcaController] { _controllers }

  package let timeout: Duration
  package let device: OcaDevice
  package nonisolated let logger: Logger
  package nonisolated(unsafe) var enableMessageTracing = false

  private let _port: NWEndpoint.Port
  private let _boundPort = Mutex<UInt16>(0)
  private var listener: NWListener?
  private let queue: DispatchQueue
  private var _controllers: [Ocp1NWDatagramController] = []
  private var _boundWaiters: [CheckedContinuation<UInt16, Error>] = []
  #if canImport(dnssd)
  private var _endpointRegistrarTask: Task<(), Error>?
  #endif

  // MARK: - Subclass hooks

  /// NWParameters for the listener; DTLS subclasses supply non-nil TLS
  /// options. Async so subclasses can await device state when building.
  open func makeParameters() async -> NWParameters {
    fatalError("makeParameters() must be implemented by a concrete subclass")
  }

  open nonisolated var controllerConnectionPrefix: String {
    fatalError("controllerConnectionPrefix must be implemented by a concrete subclass")
  }

  open nonisolated var controllerFlags: OcaControllerFlags {
    .supportsLocking
  }

  open nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    fatalError("serviceType must be implemented by a concrete subclass")
  }

  // MARK: - Lifecycle

  public init(
    port: UInt16,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1NWDatagramDeviceEndpoint")
  ) async throws {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
      throw Ocp1Error.status(.parameterError)
    }
    _port = nwPort
    self.timeout = timeout
    self.device = device
    self.logger = logger
    queue = DispatchQueue(label: "com.padl.SwiftOCADevice.NWListener.udp.\(port)")
    try await device.add(endpoint: self)
  }

  public nonisolated var description: String {
    "\(type(of: self))(port: \(_port.rawValue), timeout: \(timeout))"
  }

  public nonisolated var port: UInt16 {
    let bound = _boundPort.withLock { $0 }
    return bound != 0 ? bound : _port.rawValue
  }

  /// Suspends until the listener has bound and returns the OS-assigned port
  /// (useful when the endpoint was constructed with `port: 0`).
  public func awaitBoundPort() async throws -> UInt16 {
    let snapshot = _boundPort.withLock { $0 }
    if snapshot != 0 { return snapshot }
    return try await withCheckedThrowingContinuation { continuation in
      _boundWaiters.append(continuation)
    }
  }

  private func _resolveBoundPort(_ result: Result<UInt16, Error>) {
    if case let .success(port) = result {
      _boundPort.withLock { $0 = port }
      #if canImport(dnssd)
      if _endpointRegistrarTask == nil {
        _endpointRegistrarTask = makeBonjourRegistrarTask(for: device)
      }
      #endif
    }
    let waiters = _boundWaiters
    _boundWaiters.removeAll()
    for continuation in waiters {
      continuation.resume(with: result)
    }
  }

  open func run() async throws {
    let listener = try await NWListener(using: makeParameters(), on: _port)
    self.listener = listener
    let connections = AsyncStream<NWConnection>.makeStream()
    let listenerState = AsyncStream<NWListener.State>.makeStream()

    listener.stateUpdateHandler = { state in
      listenerState.continuation.yield(state)
    }
    listener.newConnectionHandler = { connection in
      connections.continuation.yield(connection)
    }
    listener.start(queue: queue)
    logger.info("starting \(type(of: self)) on port \(_port.rawValue)")

    // Bonjour registration is wired up in `_resolveBoundPort` once the
    // OS-assigned port is known — DNS-SD silently rejects port 0.

    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { [weak self, logger] in
          for await state in listenerState.stream {
            switch state {
            case .ready:
              if let port = listener.port {
                await self?._resolveBoundPort(.success(port.rawValue))
              }
            case let .failed(error):
              logger.critical("listener failed: \(error)")
              await self?._resolveBoundPort(.failure(error))
              throw error
            case .cancelled:
              return
            default:
              break
            }
          }
        }
        group.addTask { [weak self] in
          guard let self else { return }
          await self.acceptLoop(connections: connections.stream)
        }
        try await group.next()
        group.cancelAll()
      }
    } catch {
      logger.critical("server error: \(error)")
      listener.cancel()
      throw error
    }

    listener.cancel()
    self.listener = nil
    try? await device.remove(endpoint: self)
  }

  private func acceptLoop(connections: AsyncStream<NWConnection>) async {
    await withDiscardingTaskGroup { group in
      for await connection in connections {
        group.addTask { [weak self] in
          guard let self else { return }
          await self.run(connection: connection)
        }
      }
    }
  }

  private func run(connection: NWConnection) async {
    let connectionLogger = logger
    let controller = Ocp1NWDatagramController(endpoint: self, connection: connection)
    let endpointRef = self
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        if let identity = endpointRef.peerIdentity(for: connection) {
          controller.setPeerIdentity(identity)
        }
      case let .failed(error):
        connectionLogger.warning("connection \(connection.endpoint) failed: \(error)")
      default:
        break
      }
    }
    connection.start(queue: queue)
    await controller.handle(for: self)
  }

  /// See `Ocp1NWStreamDeviceEndpoint.peerIdentity(for:)`.
  open nonisolated func peerIdentity(for connection: NWConnection) -> OcaPeerIdentity? {
    nil
  }

  package func add(controller: Ocp1NWDatagramController) async {
    _controllers.append(controller)
  }

  package func remove(controller: Ocp1NWDatagramController) async {
    _controllers.removeAll(where: { $0 === controller })
  }

  deinit {
    #if canImport(dnssd)
    _endpointRegistrarTask?.cancel()
    #endif
    listener?.cancel()
  }
}

/// Plaintext OCP.1 UDP device endpoint via Network.framework.
@OcaDevice
public final class Ocp1NWUDPDeviceEndpoint: Ocp1NWDatagramDeviceEndpoint {
  override public func makeParameters() async -> NWParameters {
    NWParameters(dtls: nil, udp: NWProtocolUDP.Options())
  }

  override public nonisolated var controllerConnectionPrefix: String {
    OcaUdpConnectionPrefix
  }

  override public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    .udp
  }
}

#endif
