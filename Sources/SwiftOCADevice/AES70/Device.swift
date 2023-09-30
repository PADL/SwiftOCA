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

import Foundation
import SwiftOCA

// FIXME: these don't appear to be available on non-Darwin platforms
let NSEC_PER_MSEC: UInt64 = 1_000_000
let NSEC_PER_SEC: UInt64 = 1_000_000_000

@globalActor
public actor AES70Device {
    public static let shared = AES70Device()

    public private(set) var rootBlock: OcaBlock<OcaRoot>!
    public private(set) var subscriptionManager: OcaSubscriptionManager!
    public private(set) var deviceManager: OcaDeviceManager!

    var objects = [OcaONo: OcaRoot]()
    var nextObjectNumber: OcaONo = OcaMaximumReservedONo + 1
    var endpoints = [AES70DeviceEndpoint]()

    public func allocateObjectNumber() -> OcaONo {
        repeat {
            nextObjectNumber += 1
        } while objects[nextObjectNumber] != nil

        return nextObjectNumber - 1
    }

    public func initializeDefaultObjects() async throws {
        rootBlock = try await OcaBlock(
            objectNumber: OcaRootBlockONo,
            deviceDelegate: self,
            addToRootBlock: false
        )
        rootBlock.type = 1
        subscriptionManager = try await OcaSubscriptionManager(deviceDelegate: self)
        deviceManager = try await OcaDeviceManager(deviceDelegate: self)
    }

    public func add(endpoint: AES70DeviceEndpoint) async throws {
        endpoints.append(endpoint)
    }

    public func unlockAll(controller: AES70Controller) {
        objects.values.forEach {
            try? $0.unlock(controller: controller)
        }
    }

    public func register(object: OcaRoot, addToRootBlock: Bool = true) async throws {
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
            try await rootBlock.add(actionObject: object)
        }
    }

    public func handleCommand(
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

    public func notifySubscribers(
        _ event: OcaEvent,
        parameters: Data
    ) async throws {
        assert(subscriptionManager != nil)
        switch subscriptionManager.state {
        case .eventsDisabled:
            subscriptionManager.objectsChangedWhilstNotificationsDisabled.insert(event.emitterONo)
        case .normal:
            await withTaskGroup(of: Void.self) { taskGroup in
                for endpoint in self.endpoints {
                    for controller in await endpoint.controllers {
                        let controller = controller as! AES70ControllerDefaultSubscribing

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
    }

    func notifySubscribers(_ event: OcaEvent) async throws {
        try await notifySubscribers(event, parameters: Data())
    }
}
