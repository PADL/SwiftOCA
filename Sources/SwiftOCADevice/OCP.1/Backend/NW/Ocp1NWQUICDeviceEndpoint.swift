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

#if canImport(Network)

import AsyncExtensions
import Foundation
import Logging
import Network
import SocketAddress
import Synchronization
@_spi(SwiftOCAPrivate)
import SwiftOCA

@available(macOS 14.0, iOS 17.0, *)
@OcaDevice
public final class Ocp1NWQUICDeviceEndpoint: OcaDeviceEndpointPrivate,
  OcaBonjourRegistrableDeviceEndpoint,
  CustomStringConvertible
{
  typealias ControllerType = Ocp1NWQUICController

  public var controllers: [OcaController] {
    _controllers
  }

  let timeout: Duration
  let device: OcaDevice
  let logger: Logger
  nonisolated(unsafe) var enableMessageTracing = false

  private var _controllers = [Ocp1NWQUICController]()
  private let _listener: NWListener
  private let _queue: DispatchQueue
  private let _port: UInt16
  #if canImport(dnssd)
  private var _endpointRegistrarTask: Task<(), Error>?
  #endif

  /// Create a QUIC device endpoint.
  ///
  /// - Parameters:
  ///   - port: The port to listen on (0 for ephemeral).
  ///   - credential: QUIC credential (`.identity` or `.psk`).
  ///   - timeout: Idle/heartbeat timeout.
  ///   - device: The OCA device to attach to.
  ///   - logger: Logger instance.
  public init(
    port: UInt16,
    credential: Ocp1TLSCredential,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1NWQUICDeviceEndpoint")
  ) async throws {
    self._port = port
    self.timeout = timeout
    self.device = device
    self.logger = logger
    self._queue = DispatchQueue(
      label: "com.padl.SwiftOCADevice.Ocp1NWQUICDeviceEndpoint",
      attributes: .concurrent
    )

    let options = NWProtocolQUIC.Options(alpn: ["oca"])
    options.idleTimeout = Int(timeout.seconds)
    credential.apply(to: options.securityProtocolOptions)
    let parameters = NWParameters(quic: options)
    parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
      host: .ipv6(.any),
      port: NWEndpoint.Port(integerLiteral: port)
    )

    _listener = try NWListener(using: parameters)

    try await device.add(endpoint: self)
  }

  public nonisolated var description: String {
    "\(type(of: self))(port: \(_port), timeout: \(timeout))"
  }

  public func run() async throws {
    logger.info("starting \(type(of: self)) on port \(_port)")

    return try await withCheckedThrowingContinuation { continuation in
      let resumed = Mutex(false)

      _listener.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          if _port != 0 {
            #if canImport(dnssd)
            Task { try await self.runBonjourEndpointRegistrar(for: self.device) }
            #endif
          }
        case let .failed(error):
          self.logger.critical("listener failed: \(error)")
          resumed.withLock {
            guard !$0 else { return }
            $0 = true
            continuation.resume(throwing: error)
          }
        case .cancelled:
          resumed.withLock {
            guard !$0 else { return }
            $0 = true
            continuation.resume(returning: ())
          }
        default:
          break
        }
      }

      _listener.newConnectionHandler = { [weak self] nwConnection in
        guard let self else { return }
        Task {
          do {
            let controller = try await Ocp1NWQUICController(
              endpoint: self,
              connection: nwConnection,
              queue: self._queue
            )
            await controller.handle(for: self)
          } catch {
            self.logger.error("failed to create controller: \(error)")
          }
        }
      }

      _listener.start(queue: _queue)
    }
  }

  public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    .quic
  }

  public nonisolated var port: UInt16 {
    _listener.port?.rawValue ?? _port
  }

  func add(controller: ControllerType) async {
    _controllers.append(controller)
  }

  func remove(controller: ControllerType) async {
    _controllers.removeAll(where: { $0 == controller })
  }
}

#endif
