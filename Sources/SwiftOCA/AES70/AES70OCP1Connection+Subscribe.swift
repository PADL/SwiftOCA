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

private let subscriber = OcaMethod(oNo: 1055, methodID: OcaMethodID("1.1"))

/// Note – these aren't made @MainActor becasue we probably want to run them in the background

extension AES70OCP1Connection {
    func isSubscribed(event: OcaEvent) async -> Bool {
        let isSubscribedTask = Task { @MainActor in
            subscriptions[event] != nil
        }

        switch await isSubscribedTask.result {
        case let .success(value):
            return value
        case .failure:
            return false
        }
    }

    func addSubscription(
        event: OcaEvent,
        callback: @escaping AES70SubscriptionCallback
    ) async throws {
        if await subscriptions[event] != nil {
            throw Ocp1Error.alreadySubscribedToEvent
        }

        Task { @MainActor in
            subscriptions[event] = callback
        }

        try await subscriptionManager.addSubscription(
            event: event,
            subscriber: subscriber,
            subscriberContext: OcaBlob(),
            notificationDeliveryMode: .reliable,
            destinationInformation: OcaNetworkAddress()
        )
    }

    func removeSubscription(event: OcaEvent) async throws {
        try await subscriptionManager.removeSubscription(event: event, subscriber: subscriber)
        Task { @MainActor in
            subscriptions[event] = nil
        }
    }

    func removeSubscriptions() async throws {
        for event in await subscriptions.keys {
            _ = try await removeSubscription(event: event)
        }
    }

    func refreshSubscriptions() async throws {
        for event in await subscriptions.keys {
            try await subscriptionManager.addSubscription(
                event: event,
                subscriber: subscriber,
                subscriberContext: OcaBlob(),
                notificationDeliveryMode: .reliable,
                destinationInformation: OcaNetworkAddress()
            )
        }
    }
}
