//
// Copyright (c) 2024-2025 PADL Software Pty Ltd
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

import SwiftOCA

public struct OcaControllerFlags: OptionSet, Sendable {
  public typealias RawValue = UInt32

  public let rawValue: RawValue

  public init(rawValue: RawValue) { self.rawValue = rawValue }

  public static let supportsLocking = Self(rawValue: 1 << 0)
  /// Set by TLS-wrapping controllers.
  public static let hasTransportLayerSecurity = Self(rawValue: 1 << 1)
  public static let isLocal = Self(rawValue: 1 << 2)
}

public protocol OcaController: Actor {
  nonisolated var flags: OcaControllerFlags { get }

  /// Authenticated peer identity; `.anonymous` for plaintext transports.
  /// Privileged checks MUST consult this — `.hasTransportLayerSecurity`
  /// only proves *some* trusted peer is on the wire, not which.
  nonisolated var peerIdentity: OcaPeerIdentity { get }

  /// The control protocol this controller speaks; notifications and responses are
  /// encoded to match. Fixed for the controller's lifetime — it comes from the
  /// endpoint that accepted it — so it is `nonisolated` and needs no synchronisation.
  nonisolated var controlProtocol: OcaControlProtocol { get }

  func sendMessages(
    _ messages: [Ocp1Message],
    type messageType: OcaMessageType
  ) async throws

  /// Whether an event the controller's subscriptions match is to be encoded and sent
  /// to it. A controller in the device's own process may instead act on the event here,
  /// its parameters not yet encoded, and return false. Called on the notifying task.
  nonisolated func isNotifiable(event: OcaEvent, parameters: OcaEventParameters) -> Bool
}

public extension OcaController {
  nonisolated var peerIdentity: OcaPeerIdentity { .anonymous }

  nonisolated func isNotifiable(event: OcaEvent, parameters: OcaEventParameters) -> Bool { true }

  nonisolated var controlProtocol: OcaControlProtocol { .ocp1 }

  func sendMessage(
    _ messages: Ocp1Message,
    type messageType: OcaMessageType
  ) async throws {
    try await sendMessages([messages], type: messageType)
  }
}
