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

public class OcaSubscriptionManager: OcaManager {
    override public class var classID: OcaClassID { OcaClassID("1.3.4") }
    override public class var classVersion: OcaClassVersionNumber { 2 }

    @OcaDeviceProperty(propertyID: OcaPropertyID("3.1"))
    public var state: OcaSubscriptionManagerState = .normal

    var objectsChangedWhilstNotificationsDisabled = Set<OcaONo>()

    func addSubscription(
        _ subscription: SwiftOCA.OcaSubscriptionManager.AddSubscriptionParameters,
        from controller: any AES70Controller
    ) async throws {
        try await ensureWritable(by: controller)
        try await controller.addSubscription(.subscription(subscription))
    }

    func removeSubscription(
        _ subscription: SwiftOCA.OcaSubscriptionManager.RemoveSubscriptionParameters,
        from controller: any AES70Controller
    ) async throws {
        try await ensureWritable(by: controller)
        try await controller.removeSubscription(
            subscription.event,
            property: nil,
            subscriber: subscription.subscriber,
            version: .ev1
        )
    }

    func addPropertyChangeSubscription(
        _ subscription: SwiftOCA.OcaSubscriptionManager.AddPropertyChangeSubscriptionParameters,
        from controller: any AES70Controller
    ) async throws {
        try await ensureWritable(by: controller)
        try await controller.addSubscription(.propertyChangeSubscription(subscription))
    }

    func removePropertyChangeSubscription(
        _ subscription: SwiftOCA.OcaSubscriptionManager.RemovePropertyChangeSubscriptionParameters,
        from controller: any AES70Controller
    ) async throws {
        try await ensureWritable(by: controller)
        try await controller.removeSubscription(
            OcaEvent(emitterONo: subscription.emitter, eventID: OcaPropertyChangedEventID),
            property: subscription.property,
            subscriber: subscription.subscriber,
            version: .ev1
        )
    }

    func disableNotifications(from controller: any AES70Controller) async throws {
        try await ensureWritable(by: controller)
        state = .eventsDisabled
        let event = OcaEvent(
            emitterONo: objectNumber,
            eventID: SwiftOCA.OcaSubscriptionManager.NotificationsDisabledEventID
        )
        try await deviceDelegate?.notifySubscribers(event)
    }

    func reenableNotifications(from controller: any AES70Controller) async throws {
        try await ensureWritable(by: controller)
        let event = OcaEvent(
            emitterONo: objectNumber,
            eventID: SwiftOCA.OcaSubscriptionManager.SynchronizeStateEventID
        )
        let parameters = try Ocp1BinaryEncoder()
            .encode(Array(objectsChangedWhilstNotificationsDisabled))
        try await deviceDelegate?.notifySubscribers(event, parameters: parameters)
        objectsChangedWhilstNotificationsDisabled.removeAll()
        state = .normal
    }

    func addSubscription2(
        _ subscription: SwiftOCA.OcaSubscriptionManager.AddSubscription2Parameters,
        from controller: any AES70Controller
    ) async throws {
        try await ensureWritable(by: controller)
        try await controller.addSubscription(.subscription2(subscription))
    }

    func removeSubscription2(
        _ subscription: SwiftOCA.OcaSubscriptionManager.RemoveSubscription2Parameters,
        from controller: any AES70Controller
    ) async throws {
        try await ensureWritable(by: controller)
        try await controller.removeSubscription(
            subscription.event,
            property: nil,
            subscriber: subscription.subscriber,
            version: .ev2
        )
    }

    func addPropertyChangeSubscription2(
        _ subscription: SwiftOCA.OcaSubscriptionManager.AddPropertyChangeSubscription2Parameters,
        from controller: any AES70Controller
    ) async throws {
        try await ensureWritable(by: controller)
        try await controller.addSubscription(.propertyChangeSubscription2(subscription))
    }

    func removePropertyChangeSubscription2(
        _ subscription: SwiftOCA.OcaSubscriptionManager.RemovePropertyChangeSubscription2Parameters,
        from controller: any AES70Controller
    ) async throws {
        try await ensureWritable(by: controller)
        try await controller.removeSubscription(
            OcaEvent(emitterONo: subscription.emitter, eventID: OcaPropertyChangedEventID),
            property: subscription.property,
            subscriber: subscription.subscriber,
            version: .ev2
        )
    }

    override public func handleCommand(
        _ command: Ocp1Command,
        from controller: any AES70Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("3.1"):
            let subscription: SwiftOCA.OcaSubscriptionManager
                .AddSubscriptionParameters = try decodeCommand(command)
            try await addSubscription(subscription, from: controller)
            return Ocp1Response()
        case OcaMethodID("3.2"):
            let subscription: SwiftOCA.OcaSubscriptionManager
                .RemoveSubscriptionParameters = try decodeCommand(command)
            try await removeSubscription(subscription, from: controller)
            return Ocp1Response()
        case OcaMethodID("3.3"):
            try await disableNotifications(from: controller)
            return Ocp1Response()
        case OcaMethodID("3.4"):
            try await reenableNotifications(from: controller)
            return Ocp1Response()
        case OcaMethodID("3.5"):
            let subscription: SwiftOCA.OcaSubscriptionManager
                .AddPropertyChangeSubscriptionParameters = try decodeCommand(command)
            try await addPropertyChangeSubscription(subscription, from: controller)
            return Ocp1Response()
        case OcaMethodID("3.6"):
            let subscription: SwiftOCA.OcaSubscriptionManager
                .RemovePropertyChangeSubscriptionParameters = try decodeCommand(command)
            try await removePropertyChangeSubscription(subscription, from: controller)
            return Ocp1Response()
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }

    public convenience init(deviceDelegate: AES70Device? = nil) async throws {
        try await self.init(
            objectNumber: OcaSubscriptionManagerONo,
            role: "Subscription Manager",
            deviceDelegate: deviceDelegate,
            addToRootBlock: true
        )
    }
}
