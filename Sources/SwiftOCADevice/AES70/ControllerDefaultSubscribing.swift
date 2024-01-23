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

public protocol AES70ControllerDefaultSubscribing: AES70Controller {
    var subscriptions: [OcaONo: NSMutableSet] { get set }
}

public protocol AES70ControllerLightweightNotifying: AES70ControllerDefaultSubscribing {
    func sendMessage(
        _ message: Ocp1Message,
        type messageType: OcaMessageType,
        to destinationAddress: OcaNetworkAddress
    ) async throws
}

public extension AES70ControllerDefaultSubscribing {
    /// subscriptions are stored keyed by the emitter object number (the object that emits the
    /// event)
    /// each object has a set of subscriptions, note that EV1 and EV2 subscriptions are independent,
    /// i.e. a controller could subscribe to some events with EV1 and others with EV2 (although this
    /// would certainly be unusual). Hence when looking for a matching subscription, we compare the
    /// event ID, the property (in the case it is a property changed event), the subscriber, and the
    /// version.
    private func findSubscriptions(
        _ event: OcaEvent,
        property: OcaPropertyID? = nil,
        subscriber: OcaMethod? = nil,
        version: OcaSubscriptionManagerSubscription.EventVersion
    ) -> [OcaSubscriptionManagerSubscription] {
        precondition(property == nil || event.eventID == OcaPropertyChangedEventID)
        guard let subscriptions = subscriptions[event.emitterONo] else {
            return []
        }
        return subscriptions.filter {
            let subscription = $0 as! OcaSubscriptionManagerSubscription
            return subscription.event == event &&
                (subscriber == nil ? true : subscription.subscriber == subscriber) &&
                subscription.property == property &&
                subscription.version == version
        } as! [OcaSubscriptionManagerSubscription]
    }

    private func hasSubscription(
        _ event: OcaEvent,
        property: OcaPropertyID? = nil,
        subscriber: OcaMethod? = nil,
        version: OcaSubscriptionManagerSubscription.EventVersion
    ) -> Bool {
        findSubscriptions(
            event,
            property: property,
            subscriber: subscriber,
            version: version
        ).count > 0
    }

    private func hasSubscription(
        _ subscription: OcaSubscriptionManagerSubscription
    ) -> Bool {
        hasSubscription(
            subscription.event,
            subscriber: subscription.subscriber,
            version: subscription.version
        )
    }

    func addSubscription(
        _ subscription: OcaSubscriptionManagerSubscription
    ) async throws {
        guard !hasSubscription(subscription) else {
            throw Ocp1Error.alreadySubscribedToEvent
        }
        guard self is AES70ControllerLightweightNotifying ||
            subscription.notificationDeliveryMode == .normal
        else {
            // only controllers implementing AES70ControllerLightweightNotifying support
            // lightweight/fast notifications
            throw Ocp1Error.status(.parameterError)
        }
        var subscriptions = subscriptions[subscription.event.emitterONo]
        if subscriptions == nil {
            subscriptions = NSMutableSet(object: subscription)
            self.subscriptions[subscription.event.emitterONo] = subscriptions
        } else {
            subscriptions?.add(subscription)
        }
    }

    func removeSubscription(
        _ subscription: OcaSubscriptionManagerSubscription
    ) async throws {
        subscriptions[subscription.event.emitterONo]?.remove(subscription)
    }

    func removeSubscription(
        _ event: OcaEvent,
        property: OcaPropertyID?,
        subscriber: OcaMethod
    ) async throws {
        for subscription in findSubscriptions(event, subscriber: subscriber, version: .ev1) {
            subscriptions[event.emitterONo]?.remove(subscription)
        }
    }

    func notifySubscribers(
        _ event: OcaEvent,
        parameters: Data
    ) async throws {
        guard let subscriptions = subscriptions[event.emitterONo] else {
            return
        }

        let property: OcaPropertyID?

        if event.eventID == OcaPropertyChangedEventID {
            property = try Ocp1Decoder().decode(OcaPropertyID.self, from: parameters)
        } else {
            property = nil
        }

        for subscription in subscriptions {
            let subscription = subscription as! OcaSubscriptionManagerSubscription

            guard subscription.property == nil || property == subscription.property else {
                continue
            }

            switch subscription.version {
            case .ev1:
                let eventData = Ocp1EventData(
                    event: subscription.event,
                    eventParameters: parameters
                )
                let ntfParams = Ocp1NtfParams(
                    parameterCount: 2,
                    context: subscription.subscriberContext,
                    eventData: eventData
                )
                let notification = Ocp1Notification1(
                    targetONo: subscription.event.emitterONo,
                    methodID: subscription.subscriber!.methodID,
                    parameters: ntfParams
                )

                if subscription.notificationDeliveryMode == .lightweight {
                    try await (self as! AES70ControllerLightweightNotifying)
                        .sendMessage(
                            notification,
                            type: .ocaNtf1,
                            to: subscription.destinationInformation
                        )
                } else {
                    try await sendMessage(notification, type: .ocaNtf1)
                }
            case .ev2:
                let notification = Ocp1Notification2(
                    event: subscription.event,
                    notificationType: .event,
                    data: parameters
                )
                if subscription.notificationDeliveryMode == .lightweight {
                    try await (self as! AES70ControllerLightweightNotifying)
                        .sendMessage(
                            notification,
                            type: .ocaNtf2,
                            to: subscription.destinationInformation
                        )
                } else {
                    try await sendMessage(notification, type: .ocaNtf2)
                }
            }
        }
    }
}
