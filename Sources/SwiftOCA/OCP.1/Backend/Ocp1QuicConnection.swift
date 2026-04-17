//
// Copyright (c) 2024 PADL Software Pty Ltd
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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@preconcurrency import SwiftMsQuicHelper
import SocketAddress
import Synchronization

public final class Ocp1QuicConnection: Ocp1Connection {
  private let _address: String
  private let _port: UInt16
  private let _credential: Ocp1TLSCredential?

  private var _registration: QuicRegistration?
  private var _configuration: QuicConfiguration?
  private var _connection: QuicConnection?
  private var _stream: QuicStream?

  public init(
    address: String,
    port: UInt16,
    credential: Ocp1TLSCredential? = nil,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) {
    _address = address
    _port = port
    _credential = credential
    super.init(options: options)
  }

  override public func connectDevice() async throws {
    let registration = try QuicRegistration(config: .init(
      appName: "SwiftOCA",
      executionProfile: .lowLatency
    ))

    var settings = QuicSettings()
    settings.idleTimeoutMs = 30_000
    settings.keepAliveIntervalMs = 10_000
    settings.peerBidiStreamCount = 1

    let configuration = try QuicConfiguration(
      registration: registration,
      alpnBuffers: ["oca"],
      settings: settings
    )

    var credentialFlags: QuicCredentialFlags = [.client]
    if options.flags.contains(.disableCertificateVerification) {
      credentialFlags.insert(.noCertificateValidation)
    }

    let credentialType: QuicCredentialType
    if let _credential {
      switch _credential {
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
    } else {
      credentialType = .none
    }

    try configuration.loadCredential(.init(
      type: credentialType,
      flags: credentialFlags
    ))

    let connection = try QuicConnection(registration: registration)
    try await connection.start(
      configuration: configuration,
      serverName: _address,
      serverPort: _port
    )

    let stream = try connection.openStream()
    try await stream.start()

    _registration = registration
    _configuration = configuration
    _connection = connection
    _stream = stream

    try await super.connectDevice()
  }

  override public func disconnectDevice() async throws {
    if let stream = _stream {
      await stream.shutdown()
      _stream = nil
    }
    if let connection = _connection {
      await connection.shutdown()
      _connection = nil
    }
    _configuration = nil
    _registration = nil
    try await super.disconnectDevice()
  }

  override public func read(_ length: Int) async throws -> Data {
    guard let stream = _stream else {
      throw Ocp1Error.notConnected
    }

    var result = Data()
    for try await chunk in stream.receive {
      result.append(chunk)
      if result.count >= length {
        break
      }
    }

    guard result.count >= length else {
      throw Ocp1Error.notConnected
    }
    return result.prefix(length)
  }

  override public func write(_ data: Data) async throws -> Int {
    guard let stream = _stream else {
      throw Ocp1Error.notConnected
    }
    try await stream.send(data)
    return data.count
  }

  override public nonisolated var connectionPrefix: String {
    "\(OcaQuicConnectionPrefix)/\(_address):\(_port)"
  }

  override public var isDatagram: Bool { false }

  override public var heartbeatTime: Duration { .seconds(0) }

  override public var localAddress: Data? { nil }
}

#endif
