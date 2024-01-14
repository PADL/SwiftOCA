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

// FIXME: these don't appear to be available on non-Darwin platforms
let NSEC_PER_MSEC: UInt64 = 1_000_000
let NSEC_PER_SEC: UInt64 = 1_000_000_000

public protocol AES70DeviceEventDelegate: AnyObject, Sendable {
    func onEvent(
        _ event: OcaEvent,
        parameters: Data
    ) async
}

@globalActor
public actor AES70Device {
    public static let shared = AES70Device()

    public private(set) var rootBlock: OcaBlock<OcaRoot>!
    public private(set) var subscriptionManager: OcaSubscriptionManager!
    public private(set) var deviceManager: OcaDeviceManager!

    var objects = [OcaONo: OcaRoot]()
    var nextObjectNumber: OcaONo = OcaMaximumReservedONo + 1
    var endpoints = [AES70DeviceEndpoint]()
    var logger = Logger(label: "com.padl.SwiftOCADevice")

    private weak var eventDelegate: AES70DeviceEventDelegate?

    public func allocateObjectNumber() -> OcaONo {
        repeat {
            nextObjectNumber += 1
        } while objects[nextObjectNumber] != nil

        return nextObjectNumber - 1
    }

    public func initializeDefaultObjects(deviceManager: OcaDeviceManager? = nil) async throws {
        rootBlock = try await OcaBlock(
            objectNumber: OcaRootBlockONo,
            role: "",
            deviceDelegate: self,
            addToRootBlock: false
        )
        subscriptionManager = try await OcaSubscriptionManager(deviceDelegate: self)
        rootBlock.type = 1
        if let deviceManager {
            self.deviceManager = deviceManager
        } else {
            self.deviceManager = try await OcaDeviceManager(deviceDelegate: self)
        }
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
            logger
                .warning(
                    "attempted to register duplicate object \(object), existing object \(objects[object.objectNumber]!)"
                )
            throw Ocp1Error.status(.badONo)
        }
        objects[object.objectNumber] = object
        if addToRootBlock {
            precondition(object.objectNumber != OcaRootBlockONo)
            try rootBlock.add(actionObject: object)
        }
        if object is OcaManager, let deviceManager, deviceManager != object {
            let classIdentification = object.objectIdentification.classIdentification
            let managerDescriptor = OcaManagerDescriptor(
                objectNumber: object.objectNumber,
                name: object.description,
                classID: classIdentification.classID,
                classVersion: classIdentification.classVersion
            )
            deviceManager.managers.append(managerDescriptor)
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

            if let timeout, timeout > 0 {
                return try await withThrowingTimeout(seconds: timeout) {
                    try await object.handleCommand(command, from: controller)
                }
            } else {
                return try await object.handleCommand(command, from: controller)
            }
        } catch let Ocp1Error.status(status) {
            return .init(responseSize: 0, handle: command.handle, statusCode: status)
        } catch {
            logger
                .warning(
                    "failed to handle command \(command) from controller \(controller): \(error)"
                )
            return .init(responseSize: 0, handle: command.handle, statusCode: .deviceError)
        }
    }

    public func notifySubscribers(
        _ event: OcaEvent,
        parameters: Data
    ) async throws {
        // if we are using a custom device manager, it may set properties prior to the subscription
        // manager being initialized
        assert(deviceManager == nil || subscriptionManager != nil)
        guard let subscriptionManager else { return }

        if let eventDelegate {
            Task {
                await eventDelegate.onEvent(event, parameters: parameters)
            }
        }

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

    public func setEventDelegate(_ eventDelegate: AES70DeviceEventDelegate) {
        self.eventDelegate = eventDelegate
    }

    public func resolve<T: OcaRoot>(objectNumber: OcaONo) -> T? {
        objects[objectNumber] as? T
    }

    public func resolve<T: OcaRoot>(objectIdentification: OcaObjectIdentification) -> T? {
        guard let object: T = resolve(objectNumber: objectIdentification.oNo) else {
            return nil
        }

        var classID: OcaClassID? = objectIdentification.classIdentification.classID

        repeat {
            var classVersion = OcaRoot.classVersion

            repeat {
                let id = OcaClassIdentification(classID: classID!, classVersion: classVersion)

                if id == object.objectIdentification.classIdentification {
                    return object
                }

                classVersion = classVersion - 1
            } while classVersion != 0

            classID = classID?.parent
        } while classID != nil

        return nil
    }
}
