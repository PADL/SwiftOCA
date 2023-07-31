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

    typealias AddSubscriptionParameters = OcaSubscription

    struct RemoveSubscriptionParameters: Codable {
        let event: OcaEvent
        let subscriber: OcaMethod
    }

    func addSubscription(
        _ subscription: AddSubscriptionParameters,
        from controller: AES70OCP1Controller
    ) async throws {
        try await ensureWritable(by: controller)
        try await controller.addSubscription(subscription)
    }

    func removeSubscription(
        _ subscription: RemoveSubscriptionParameters,
        from controller: AES70OCP1Controller
    ) async throws {
        try await ensureWritable(by: controller)
        try await controller.removeSubscription(
            subscription.event,
            subscriber: subscription.subscriber
        )
    }

    func disableNotifications(from controller: AES70OCP1Controller) async throws {
        try await ensureWritable(by: controller)
        await controller.disableNotifications()
    }

    func reenableNotifications(from controller: AES70OCP1Controller) async throws {
        try await ensureWritable(by: controller)
        await controller.enableNotifications()
    }

    override public func handleCommand(
        _ command: Ocp1Command,
        from controller: AES70OCP1Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("3.1"):
            let subscription: AddSubscriptionParameters = try decodeCommand(command)
            try await addSubscription(subscription, from: controller)
            return Ocp1Response()
        case OcaMethodID("3.2"):
            let subscription: RemoveSubscriptionParameters = try decodeCommand(command)
            try await removeSubscription(subscription, from: controller)
            return Ocp1Response()
        case OcaMethodID("3.3"):
            try await disableNotifications(from: controller)
            return Ocp1Response()
        case OcaMethodID("3.4"):
            try await reenableNotifications(from: controller)
            return Ocp1Response()
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }

    public convenience init(deviceDelegate: AES70OCP1Device? = nil) async throws {
        try await self.init(
            objectNumber: OcaSubscriptionManagerONo,
            role: "Subscription Manager",
            deviceDelegate: deviceDelegate,
            addToRootBlock: true
        )
    }
}
