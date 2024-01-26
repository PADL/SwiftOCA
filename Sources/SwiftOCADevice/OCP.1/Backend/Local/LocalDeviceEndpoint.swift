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
import Foundation
import Logging
import SwiftOCA

@OcaDevice
public final class OcaLocalDeviceEndpoint: OcaDeviceEndpointPrivate {
    typealias ControllerType = OcaLocalController

    let logger = Logger(label: "com.padl.SwiftOCADevice.OcaLocalDeviceEndpoint")
    let timeout: Duration = .zero
    let device: OcaDevice

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
        device: OcaDevice = OcaDevice.shared
    ) async throws {
        self.device = device
        controller = await OcaLocalController(endpoint: self)
        try await device.add(endpoint: self)
    }

    public func run() async {
        await controller.handle(for: self)
    }
}
