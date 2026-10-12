//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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
import Logging
import SwiftOCA

public protocol OcaDeviceEndpoint: AnyObject, Sendable {
  var controllers: [OcaController] { get async }
}

package enum OcaMessageDirection {
  case tx
  case rx
}

package protocol OcaDeviceEndpointPrivate: OcaDeviceEndpoint {
  associatedtype ControllerType: Ocp1ControllerInternal

  nonisolated var device: OcaDevice { get }
  nonisolated var timeout: Duration { get }

  nonisolated var logger: Logger { get }
  nonisolated var enableMessageTracing: Bool { get }

  /// The control protocol controllers on this endpoint speak. Defaults to OCP.1.
  nonisolated var controlProtocol: OcaControlProtocol { get }

  /// Largest PDU accepted from a controller. Override to
  /// narrow it: the default lets a peer buffer 16 MB before a PDU is framed.
  nonisolated var maximumPduSize: Int { get }

  @OcaDevice
  func add(controller: ControllerType) async
  @OcaDevice
  func remove(controller: ControllerType) async
}

extension OcaDeviceEndpointPrivate {
  package nonisolated var controlProtocol: OcaControlProtocol { .ocp1 }

  package nonisolated var maximumPduSize: Int { OcaControlProtocol.defaultMaximumPduSize }

  package func unlockAndRemove(controller: ControllerType) async {
    await controller.cancelKeepAlive()

    await device.expire(controller: controller)
    await remove(controller: controller)
    try? await controller.close()
  }

  package func handle(messagePduData: Data, from controller: ControllerType) async throws {
    try controlProtocol.validatePacketPdu(messagePduData, maximumPduSize: maximumPduSize)
    let messageList = try await controller.decodeMessages(from: messagePduData)
    try await controller.handle(for: self, messageList: messageList)
  }

  package func handle(messagePduData: [UInt8], from controller: ControllerType) async throws {
    try await handle(messagePduData: Data(messagePduData), from: controller)
  }
}

/// How many controllers a datagram endpoint keeps at once. Each one is made by a single
/// datagram, so without a cap one spoofed packet per source address grows the table.
package let OcaMaximumDatagramControllers = 64

/// Admits new peers to a datagram endpoint's controller table. Once it is full, the
/// KeepAlive-only controller silent longest makes way for a newcomer; one that has
/// issued a command never does, and with none to evict the newcomer is refused.
@OcaDevice
package final class OcaDatagramControllerAdmission {
  private var isFull = false
  private var evicted = 0
  private var refused = 0

  package nonisolated init() {}

  /// Whether `peer` may have a controller, an old one having been evicted for it if the
  /// table was full. Logs once when the table fills and once, with totals, when a
  /// newcomer next finds room; evictions are logged at debug.
  package func admit<Endpoint: OcaDeviceEndpointPrivate>(
    peer: String,
    to endpoint: Endpoint,
    among controllers: some Sequence<Endpoint.ControllerType>
  ) async -> Bool where Endpoint.ControllerType: Ocp1ControllerDatagramSemantics {
    if await endpoint.controllers.count < OcaMaximumDatagramControllers {
      if isFull {
        endpoint.logger.info(
          "datagram controller table has room again; evicted \(evicted) and refused \(refused) peers while full"
        )
        (isFull, evicted, refused) = (false, 0, 0)
      }
      return true
    }
    if !isFull {
      isFull = true
      endpoint.logger.warning(
        "datagram controller table full (\(OcaMaximumDatagramControllers)); evicting KeepAlive-only peers for newcomers, refusing newcomers otherwise"
      )
    }
    guard let victim = await Self.keepAliveOnlyControllerSilentLongest(among: controllers) else {
      refused += 1
      return false
    }
    endpoint.logger.debug("evicting datagram controller \(victim.identifier) for \(peer)")
    await endpoint.unlockAndRemove(controller: victim)
    evicted += 1
    // choosing the victim suspended, so another newcomer may have taken the place
    guard await endpoint.controllers.count < OcaMaximumDatagramControllers else {
      refused += 1
      return false
    }
    return true
  }

  private static func keepAliveOnlyControllerSilentLongest<
    Controller: Ocp1ControllerInternal & Ocp1ControllerDatagramSemantics
  >(among controllers: some Sequence<Controller>) async -> Controller? {
    var victim: (controller: Controller, silentSince: ContinuousClock.Instant)?
    for controller in controllers {
      guard await !controller.hasReceivedCommand else { continue }
      let silentSince = await controller.lastMessageReceivedTime
      if let victim, victim.silentSince <= silentSince { continue }
      victim = (controller, silentSince)
    }
    return victim?.controller
  }
}
