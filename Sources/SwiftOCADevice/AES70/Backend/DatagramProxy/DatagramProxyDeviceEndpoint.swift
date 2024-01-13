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

import AsyncAlgorithms
import AsyncExtensions
import Foundation
import Logging
import SwiftOCA

@AES70Device
public class DatagramProxyDeviceEndpoint<T: Equatable & Hashable>: AES70DeviceEndpointPrivate {
    public typealias PeerMessagePDU = (T, [UInt8])

    public var controllers: [AES70Controller] {
        _controllers.map(\.1)
    }

    typealias ControllerType = DatagramProxyController<T>

    let timeout: TimeInterval
    let outputStream: AsyncStream<PeerMessagePDU>.Continuation
    let logger = Logger(label: "com.padl.SwiftOCADevice.DatagramProxyDeviceEndpoint")

    private var _controllers = [T: ControllerType]()
    private let inputStream: AsyncStream<PeerMessagePDU>

    public init(
        timeout: TimeInterval,
        inputStream: AsyncStream<PeerMessagePDU>,
        outputStream: AsyncStream<PeerMessagePDU>.Continuation
    ) async throws {
        self.timeout = timeout
        self.inputStream = inputStream
        self.outputStream = outputStream

        try await AES70Device.shared.add(endpoint: self)
    }

    public func run() async throws {
        repeat {
            for await messagePdu in inputStream {
                let controller = controller(for: messagePdu.0)
                do {
                    let messages = try await controller.decodeMessages(from: messagePdu.1)
                    for (message, rrq) in messages {
                        try await controller.handle(
                            for: self,
                            message: message,
                            rrq: rrq
                        )
                    }
                } catch {
                    await unlockAndRemove(controller: controller)
                }
            }
            if Task.isCancelled {
                logger.info("\(type(of: self)) cancelled, stopping")
                break
            }
        } while true
    }

    private func controller(for peerID: T) -> ControllerType {
        var controller: ControllerType!

        controller = _controllers[peerID]
        if controller == nil {
            controller = DatagramProxyController(with: peerID, endpoint: self)
            logger.info("datagram proxy controller added", controller: controller)
            _controllers[peerID] = controller
        }

        return controller
    }

    // only needed for stream-oriented controllers
    func add(controller: ControllerType) async {}

    func remove(controller: ControllerType) async {
        _controllers[controller.peerID] = nil
    }
}
