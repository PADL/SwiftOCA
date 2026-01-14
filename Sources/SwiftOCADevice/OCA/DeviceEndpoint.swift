//
// Copyright (c) 2023 PADL Software Pty Ltd
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

enum OcaMessageDirection {
  case tx
  case rx
}

protocol OcaDeviceEndpointPrivate: OcaDeviceEndpoint {
  associatedtype ControllerType: Ocp1ControllerInternal

  var device: OcaDevice { get }
  var timeout: Duration { get }

  nonisolated var logger: Logger { get }
  nonisolated var enableMessageTracing: Bool { get }

  func add(controller: ControllerType) async
  func remove(controller: ControllerType) async
}

extension OcaDeviceEndpointPrivate {
  func unlockAndRemove(controller: ControllerType) async {
    Task { await device.eventDelegate?.onControllerExpiry(controller) }
    Task {
      for dataset in await device.objects.values.compactMap({
        $0 as? OcaDataset
      }) {
        await dataset.expireIOSessionHandles(controller: controller)
      }
    }
    await device.unlockAll(controller: controller)
    await remove(controller: controller)
    try? await controller.close()
  }

  func handle(messagePduData: [UInt8], from controller: ControllerType) async throws {
    let messageList = try await controller.decodeMessages(from: messagePduData)
    try await controller.handle(for: self, messageList: messageList)
  }

  func handle(messagePduData: Data, from controller: ControllerType) async throws {
    try await handle(messagePduData: Array(messagePduData), from: controller)
  }
}
