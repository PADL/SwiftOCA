//
// Copyright (c) 2024-2026 PADL Software Pty Ltd
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

#if canImport(SwiftMsQuicHelper)

import AsyncAlgorithms
import AsyncExtensions
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import SocketAddress
import SwiftMsQuicHelper
@_spi(SwiftOCAPrivate)
import SwiftOCA

@OcaDevice
public final class Ocp1QuicDeviceEndpoint: OcaDeviceEndpointPrivate,
  CustomStringConvertible
{
  typealias ControllerType = Ocp1QuicController

  public var controllers: [OcaController] {
    _controllers
  }

  let timeout: Duration
  let device: OcaDevice
  let logger: Logger
  nonisolated(unsafe) var enableMessageTracing = false

  private let address: any SocketAddress
  private let credential: Ocp1TLSCredential
  private var _controllers = [Ocp1QuicController]()

  private var registration: QuicRegistration?
  private var configuration: QuicConfiguration?
  private var listener: QuicListener?

  public init(
    address: any SocketAddress,
    credential: Ocp1TLSCredential,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.Ocp1QuicDeviceEndpoint")
  ) async throws {
    self.address = address
    self.credential = credential
    self.timeout = timeout
    self.device = device
    self.logger = logger
    try await device.add(endpoint: self)
  }

  public nonisolated var description: String {
    "\(type(of: self))(address: \((try? address.presentationAddress) ?? "<unknown>"), timeout: \(timeout))"
  }

  public nonisolated var port: UInt16 {
    (try? address.port) ?? 0
  }

  public func run() async throws {
    logger.info("starting \(type(of: self)) on \(address._presentationAddress)")

    let registration = try QuicRegistration(config: .init(
      appName: "SwiftOCADevice",
      executionProfile: .lowLatency
    ))
    self.registration = registration

    var settings = QuicSettings()
    settings.idleTimeoutMs = UInt64(timeout.components.seconds * 1000)
    settings.peerBidiStreamCount = 128
    settings.peerUnidiStreamCount = 128

    let configuration = try QuicConfiguration(
      registration: registration,
      alpnBuffers: ["oca"],
      settings: settings
    )
    self.configuration = configuration

    let credentialType: QuicCredentialType
    switch credential {
    #if canImport(Security)
    case .identity:
      // TODO: map SecIdentity to msquic credential
      credentialType = .none
    #endif
    case .certificateFile(let certPath, let keyPath):
      credentialType = .certificateFile(certPath: certPath, keyPath: keyPath)
    case .certificatePEM(let certificate, let privateKey):
      credentialType = .certificatePem(key: privateKey, cert: certificate, password: nil)
    case .pkcs12(let data, let password):
      credentialType = .certificatePkcs12(blob: data, password: password)
    }

    try configuration.loadCredential(.init(
      type: credentialType,
      flags: []
    ))

    let listener = try QuicListener(registration: registration)
    self.listener = listener

    nonisolated(unsafe) let config = configuration
    listener.onNewConnection { [weak self] _, info in
      guard let self else { return nil }

      let connection = try QuicConnection(
        handle: info.connection,
        configuration: config
      ) { [weak self] connection, stream, flags in
        guard let self else { return }
        await self.handlePeerStream(connection: connection, stream: stream, flags: flags)
      }

      Task { @OcaDevice [weak self] in
        guard let self else { return }
        let controller = Ocp1QuicController(
          endpoint: self,
          connection: connection
        )
        await controller.handle(for: self)
      }

      return connection
    }

    let quicAddress: QuicAddress
    if let port = try? address.port, port != 0 {
      quicAddress = QuicAddress(port: port)
    } else {
      quicAddress = QuicAddress(port: 0)
    }

    try listener.start(alpnBuffers: ["oca"], localAddress: quicAddress)

    repeat {
      try await Task.sleep(for: .seconds(1))
    } while !Task.isCancelled

    logger.info("\(type(of: self)) cancelled, stopping")
    await listener.stop()
    self.listener = nil
    self.configuration = nil
    self.registration = nil
    try await device.remove(endpoint: self)
  }

  public func setMessageTracingEnabled(to value: Bool) {
    enableMessageTracing = value
  }

  private func handlePeerStream(
    connection: QuicConnection,
    stream: QuicStream,
    flags: QuicStreamOpenFlags
  ) async {
    if let controller = _controllers.first(where: { $0.isConnection(connection) }) {
      await controller.addPeerStream(stream)
    }
  }

  func add(controller: ControllerType) async {
    _controllers.append(controller)
  }

  func remove(controller: ControllerType) async {
    _controllers.removeAll(where: { $0 == controller })
  }

  deinit {
    // QuicListener/Configuration/Registration handle cleanup in their own deinit
  }
}

#endif
