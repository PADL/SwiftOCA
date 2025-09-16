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

import AsyncAlgorithms
import AsyncExtensions
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import SwiftOCA

@OcaDevice
public final class OcaLocalDeviceEndpoint: OcaDeviceEndpointPrivate {
  typealias ControllerType = OcaLocalController

  let timeout: Duration = .zero
  let device: OcaDevice
  let logger: Logger

  public var controllers: [OcaController] {
    [controller]
  }

  /// channel for receiving requests from the in-process controller
  let requestChannel = AsyncChannel<Data>()
  /// channel for sending responses to the in-process controller
  let responseChannel = AsyncChannel<Data>()

  private var controller: OcaLocalController!

  func add(controller: ControllerType) async {}

  func remove(controller: ControllerType) async {}

  public init(
    device: OcaDevice = OcaDevice.shared,
    logger: Logger = Logger(label: "com.padl.SwiftOCADevice.OcaLocalDeviceEndpoint")
  ) async throws {
    self.device = device
    self.logger = logger

    controller = await OcaLocalController(endpoint: self)
    try await device.add(endpoint: self)
  }

  public func run() async throws {
    await controller.handle(for: self)
    try await device.remove(endpoint: self)
  }
}
