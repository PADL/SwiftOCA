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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import Network
#if canImport(Security)
@preconcurrency import Security
#endif
@_spi(SwiftOCAPrivate)
import SwiftOCADevice
import SwiftOCASecure
@_spi(SwiftOCAPrivate)
import SwiftOCA

/// DTLS-secured OCP.1 datagram device endpoint. Sibling of
/// `Ocp1NWSecureTCPDeviceEndpoint`; Network.framework spells DTLS as TLS
/// options over UDP. PSKs come from the device's `OcaSecurityManager` at
/// endpoint start (runtime `AddPreSharedKey` updates require a restart).
@OcaDevice
public final class Ocp1NWSecureUDPDeviceEndpoint: Ocp1NWDatagramDeviceEndpoint {
  private let serverCredential: Ocp1TLSCredential?
  /// Non-nil enables mTLS.
  private let clientCertificateTrustRoots: Ocp1TLSTrustRoots?
  /// Pre-loaded at init so a bad CA bundle fails construction.
  private let preloadedClientAnchors: [SecCertificate]?
  private let clientCertificateValidator: Ocp1NWSecureTCPConnection
    .PeerCertificateValidator?
  private let revocation: Ocp1TLSRevocationOptions

  public init(
    port: UInt16,
    credential: Ocp1TLSCredential? = nil,
    clientCertificateTrustRoots: Ocp1TLSTrustRoots? = nil,
    clientCertificateValidator: Ocp1NWSecureTCPConnection.PeerCertificateValidator? = nil,
    revocation: Ocp1TLSRevocationOptions = .disabled,
    timeout: Duration = OcaDevice.DefaultTimeout,
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCASecureDevice.Ocp1NWSecureUDPDeviceEndpoint")
  ) async throws {
    if let credential {
      try credential.validate()
      try credential.validateAppleLoad()
    }
    let preloadedAnchors = try Ocp1NWSecureTCPConnection.loadAnchorCertificates(
      from: clientCertificateTrustRoots
    )
    serverCredential = credential
    self.clientCertificateTrustRoots = clientCertificateTrustRoots
    preloadedClientAnchors = preloadedAnchors
    self.clientCertificateValidator = clientCertificateValidator
    self.revocation = revocation
    try await super.init(port: port, timeout: timeout, device: device, logger: logger)
    if clientCertificateTrustRoots != nil {
      logger.info("\(type(of: self)) requires client certificates (mTLS)")
    }
  }

  override public nonisolated func peerIdentity(
    for connection: NWConnection
  ) -> OcaPeerIdentity? {
    Ocp1NWExtractPeerIdentity(from: connection)
  }

  override public func makeParameters() async -> NWParameters {
    let tls = NWProtocolTLS.Options()
    let sec = tls.securityProtocolOptions
    Ocp1TLSCredential.enforceMinimumTLSProtocol(sec)

    if let serverCredential {
      try? serverCredential.apply(to: sec)
    }
    if let securityManager = await device.securityManager {
      for identity in securityManager.preSharedKeyIdentities {
        Ocp1TLSCredential.configurePSK(sec, identity: identity, provider: securityManager)
      }
    }
    if let anchors = preloadedClientAnchors {
      sec_protocol_options_set_peer_authentication_required(sec, true)
      Ocp1NWSecureTCPConnection.installCustomTrustVerifyBlock(
        sec,
        anchors: anchors,
        revocation: revocation,
        peerValidator: clientCertificateValidator
      )
    }
    return NWParameters(dtls: tls, udp: NWProtocolUDP.Options())
  }

  override public nonisolated var controllerConnectionPrefix: String {
    OcaSecureUdpConnectionPrefix
  }

  override public nonisolated var controllerFlags: OcaControllerFlags {
    [.supportsLocking, .hasTransportLayerSecurity]
  }

  override public nonisolated var serviceType: OcaNetworkAdvertisingServiceType {
    .udpSecure
  }
}

#endif
