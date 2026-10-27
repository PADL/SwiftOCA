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
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
#endif
import SocketAddress
import SwiftOCA

public protocol OcaDeviceEndpoint: AnyObject, Sendable {
  var controllers: [OcaController] { get async }
  /// The address the endpoint is bound to; DNS-SD announces its services only on the interface
  /// holding it (every interface for a wildcard, none for loopback or a non-IP address).
  nonisolated var address: any SocketAddress { get }
}

public extension OcaDeviceEndpoint {
  /// No socket address (an all-zero one, which DNS-SD does not announce): the default for an
  /// endpoint that is not bound to a socket, such as a Mach port or an in-process endpoint.
  nonisolated var address: any SocketAddress { sockaddr_storage() }
}

package enum OcaMessageDirection {
  case tx
  case rx
}

package protocol OcaDeviceEndpointPrivate: OcaDeviceEndpoint {
  associatedtype ControllerType: OcaControllerInternal

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
