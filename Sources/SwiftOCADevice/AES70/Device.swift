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

@_spi(Private) @_implementationOnly
import func FlyingSocks.withThrowingTimeout
import Foundation
import SwiftOCA

public protocol AES70Device: Actor {
    var controllers: [AES70Controller] { get }

    var rootBlock: OcaBlock<OcaRoot>! { get }
    var subscriptionManager: OcaSubscriptionManager! { get }
    var deviceManager: OcaDeviceManager! { get }

    var objects: [OcaONo: OcaRoot] { get }

    func register(
        object: OcaRoot,
        addToRootBlock: Bool
    ) throws

    func allocateObjectNumber() -> OcaONo
}

protocol AES70DevicePrivate: AES70Device {
    var objects: [OcaONo: OcaRoot] { get set }
    var nextObjectNumber: OcaONo { get set }
}

public extension AES70Device {
    func register(object: OcaRoot) throws {
        try register(object: object, addToRootBlock: true)
    }

    func notifySubscribers(
        _ event: OcaEvent,
        parameters: Data
    ) async throws {
        switch subscriptionManager.state {
        case .eventsDisabled:
            subscriptionManager.objectsChangedWhilstNotificationsDisabled.insert(event.emitterONo)
        case .normal:
            await withTaskGroup(of: Void.self) { taskGroup in
                for controller in self.controllers {
                    let controller = controller as! AES70ControllerPrivate

                    taskGroup.addTask {
                        try? await controller.notifySubscribers(
                            event,
                            parameters: parameters
                        )
                    }
                }
            }
        }
    }

    func notifySubscribers(_ event: OcaEvent) async throws {
        try await notifySubscribers(event, parameters: Data())
    }
}

extension AES70DevicePrivate {
    public func allocateObjectNumber() -> OcaONo {
        defer { nextObjectNumber += 1 }
        return nextObjectNumber
    }

    public func register(object: OcaRoot, addToRootBlock: Bool = true) throws {
        precondition(
            object.objectNumber != OcaInvalidONo,
            "cannot register object with invalid ONo"
        )
        guard objects[object.objectNumber] == nil else {
            throw Ocp1Error.status(.badONo)
        }
        objects[object.objectNumber] = object
        if addToRootBlock {
            precondition(object.objectNumber != OcaRootBlockONo)
            try rootBlock.add(member: object)
        }
    }

    func handleCommand(
        _ command: Ocp1Command,
        timeout: TimeInterval? = nil,
        from controller: any AES70Controller
    ) async -> Ocp1Response {
        do {
            let object = objects[command.targetONo]
            guard let object else {
                throw Ocp1Error.status(.badONo)
            }

            if let timeout {
                return try await withThrowingTimeout(seconds: timeout) {
                    try await object.handleCommand(command, from: controller)
                }
            } else {
                return try await object.handleCommand(command, from: controller)
            }
        } catch let Ocp1Error.status(status) {
            return .init(responseSize: 0, handle: command.handle, statusCode: status)
        } catch {
            return .init(responseSize: 0, handle: command.handle, statusCode: .deviceError)
        }
    }
}
