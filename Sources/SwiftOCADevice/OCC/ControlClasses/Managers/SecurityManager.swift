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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftOCA
import Synchronization

open class OcaSecurityManager: OcaManager {
  override open class var classID: OcaClassID { OcaClassID("1.3.2") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var secureControlData: OcaBoolean = false

  /// Mutex-backed so the OpenSSL PSK callback can read synchronously from
  /// outside the actor. OCA add/delete paths take the same lock.
  ///
  /// Runtime mutations (via `AddPreSharedKey` / `DeletePreSharedKey`) take
  /// effect immediately for backends that read PSKs per handshake (OpenSSL
  /// on Linux). On Apple, Network.framework bakes the PSK set into static
  /// listener config at bind time, so runtime changes require an endpoint
  /// restart — see `Ocp1NWSecureTCPDeviceEndpoint` /
  /// `Ocp1NWSecureUDPDeviceEndpoint`.
  package nonisolated let _preSharedKeys = Mutex<[OcaString: Data]>([:])

  /// Register a PSK without going through OCA command authorization;
  /// intended for static configuration at device startup.
  public func loadPreSharedKey(identity: OcaString, key: Data) throws {
    try _add(identity: identity, key: key, mustExist: false)
  }

  /// Mirrored from `SwiftOCASecure.OcaMinimumPreSharedKeyLength`;
  /// SwiftOCADevice doesn't depend on SwiftOCASecure.
  private static let minimumPreSharedKeyLength: Int = 16

  /// Wipe a PSK `Data` in place. Caller MUST hold exclusive ownership of
  /// the Data — pull the slot out of the dict via `removeValue` first, and
  /// keep the PSK provider's read callback under the same lock so no
  /// concurrent reference can exist. Without exclusive ownership, Swift's
  /// COW will silently redirect `resetBytes` to a fresh copy.
  private static func _zero(_ key: inout Data) {
    let count = key.count
    guard count > 0 else { return }
    key.resetBytes(in: 0..<count)
  }

  private func _add(identity: OcaString, key: Data, mustExist: Bool) throws {
    guard !identity.isEmpty else {
      throw Ocp1Error.status(.parameterError)
    }
    guard key.count >= Self.minimumPreSharedKeyLength else {
      throw Ocp1Error.status(.parameterError)
    }
    // Defensive copy: caller's `Data` may share storage we can't see,
    // and COW would otherwise redirect our future wipe to a fresh copy.
    // `Data(count:)` is uniquely owned at insertion.
    var owned = Data(count: key.count)
    owned.withUnsafeMutableBytes { dst in
      key.withUnsafeBytes { src in
        if let dp = dst.baseAddress, let sp = src.baseAddress {
          dp.copyMemory(from: sp, byteCount: key.count)
        }
      }
    }
    try _preSharedKeys.withLock { dict in
      guard (dict[identity] != nil) == mustExist else {
        throw Ocp1Error.status(.parameterError)
      }
      // Replace: take exclusive ownership of the prior key before wiping
      // so `_zero` hits the stored buffer, not a COW copy.
      if var prior = dict.removeValue(forKey: identity) {
        Self._zero(&prior)
      }
      dict[identity] = owned
    }
  }

  private func _delete(identity: OcaString) throws {
    try _preSharedKeys.withLock { dict in
      guard var removed = dict.removeValue(forKey: identity) else {
        throw Ocp1Error.status(.parameterError)
      }
      Self._zero(&removed)
    }
  }

  /// PSKs and security state must never traverse a plaintext connection.
  override open func ensureReadable(
    by controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    guard controller.flags.contains(.hasTransportLayerSecurity) else {
      throw Ocp1Error.status(.notImplemented)
    }
    try await super.ensureReadable(by: controller, command: command)
  }

  /// Write access denied unconditionally; PSK add/change/delete scaffolding
  /// is in place but disabled until admin role gating is implemented.
  /// Subclasses introducing ACLs MUST consult `controller.peerIdentity` and
  /// reject `.anonymous` — `.hasTransportLayerSecurity` only proves *some*
  /// trusted peer is on the wire, not which principal.
  override open func ensureWritable(
    by controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    throw Ocp1Error.status(.permissionDenied)
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.1"):
      try decodeNullCommand(command)
      try await ensureWritable(by: controller, command: command)
      secureControlData = true
      return Ocp1Response()
    case OcaMethodID("3.2"):
      try decodeNullCommand(command)
      try await ensureWritable(by: controller, command: command)
      secureControlData = false
      return Ocp1Response()
    case OcaMethodID("3.3"):
      let params: SwiftOCA.OcaSecurityManager
        .AddPreSharedKeyParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try _add(identity: params.identity, key: Data(params.key), mustExist: true)
      return Ocp1Response()
    case OcaMethodID("3.4"):
      let params: SwiftOCA.OcaSecurityManager
        .AddPreSharedKeyParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try _add(identity: params.identity, key: Data(params.key), mustExist: false)
      return Ocp1Response()
    case OcaMethodID("3.5"):
      let identity: OcaString = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try _delete(identity: identity)
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }

  public convenience init(
    deviceDelegate: OcaDevice? = nil,
    preSharedKeys: [OcaString: OcaBlob] = [:]
  ) async throws {
    try await self.init(
      objectNumber: OcaSecurityManagerONo,
      role: "Security Manager",
      deviceDelegate: deviceDelegate,
      addToRootBlock: true
    )
    for (identity, key) in preSharedKeys {
      try loadPreSharedKey(identity: identity, key: Data(key))
    }
  }
}
