//
//  Device.swift
//
//  Copyright (c) 2022 Simon Whitty. All rights reserved.
//  Portions Copyright (c) 2023 PADL Software Pty Ltd. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import AsyncAlgorithms
import AsyncExtensions
import Foundation
import SwiftOCA

public enum OcaSubscriptionManagerSubscription: Codable {
    case subscription(OcaSubscription)
    case propertyChangeSubscription(OcaPropertyChangeSubscription)
    case subscription2(OcaSubscription2)
    case propertyChangeSubscription2(OcaPropertyChangeSubscription2)

    public enum EventVersion: OcaUint8 {
        case ev1 = 1
        case ev2 = 2
    }

    var version: EventVersion {
        switch self {
        case .subscription:
            fallthrough
        case .propertyChangeSubscription:
            return .ev1
        case .subscription2:
            fallthrough
        case .propertyChangeSubscription2:
            return .ev2
        }
    }

    var event: OcaEvent {
        switch self {
        case let .subscription(subscription):
            return subscription.event
        case let .subscription2(subscription):
            return subscription.event
        case let .propertyChangeSubscription(propertyChangeSubscription):
            return OcaEvent(
                emitterONo: propertyChangeSubscription.emitter,
                eventID: OcaPropertyChangedEventID
            )
        case let .propertyChangeSubscription2(propertyChangeSubscription):
            return OcaEvent(
                emitterONo: propertyChangeSubscription.emitter,
                eventID: OcaPropertyChangedEventID
            )
        }
    }

    var property: OcaPropertyID? {
        switch self {
        case .subscription:
            fallthrough
        case .subscription2:
            return nil
        case let .propertyChangeSubscription(propertyChangeSubscription):
            return propertyChangeSubscription.property
        case let .propertyChangeSubscription2(propertyChangeSubscription):
            return propertyChangeSubscription.property
        }
    }

    var subscriber: OcaMethod {
        switch self {
        case let .subscription(subscription):
            return subscription.subscriber
        case let .subscription2(subscription):
            return subscription.subscriber
        case let .propertyChangeSubscription(propertyChangeSubscription):
            return propertyChangeSubscription.subscriber
        case let .propertyChangeSubscription2(propertyChangeSubscription):
            return propertyChangeSubscription.subscriber
        }
    }

    var subscriberContext: OcaBlob {
        switch self {
        case let .subscription(subscription):
            return subscription.subscriberContext
        case .subscription2:
            return LengthTaggedData()
        case let .propertyChangeSubscription(propertyChangeSubscription):
            return propertyChangeSubscription.subscriberContext
        case .propertyChangeSubscription2:
            return LengthTaggedData()
        }
    }
}

public protocol AES70Controller: Actor {
    func addSubscription(
        _ subscription: OcaSubscriptionManagerSubscription
    ) async throws

    func removeSubscription(
        _ event: OcaEvent,
        property: OcaPropertyID?,
        subscriber: OcaMethod,
        version: OcaSubscriptionManagerSubscription.EventVersion
    ) async throws
}

protocol AES70ControllerPrivate: AES70Controller {
    var subscriptions: [OcaONo: NSMutableSet] { get set }

    func sendMessages(
        _ messages: AnyAsyncSequence<Ocp1Message>,
        type messageType: OcaMessageType
    ) async throws
}

extension AES70ControllerPrivate {
    private func findSubscription(
        _ event: OcaEvent,
        property: OcaPropertyID? = nil,
        subscriber: OcaMethod? = nil,
        version: OcaSubscriptionManagerSubscription.EventVersion
    ) -> OcaSubscriptionManagerSubscription? {
        precondition(property == nil || event.eventID == OcaPropertyChangedEventID)
        guard let subscriptions = subscriptions[event.emitterONo] else {
            return nil
        }
        return subscriptions.first(where: {
            let subscription = $0 as! OcaSubscriptionManagerSubscription
            return subscription.event == event &&
                (subscriber == nil ? true : subscription.subscriber == subscriber) &&
                subscription.property == property &&
                subscription.version == version
        }) as? OcaSubscriptionManagerSubscription
    }

    private func hasSubscription(
        _ event: OcaEvent,
        property: OcaPropertyID? = nil,
        subscriber: OcaMethod? = nil,
        version: OcaSubscriptionManagerSubscription.EventVersion
    ) -> Bool {
        findSubscription(
            event,
            property: property,
            subscriber: subscriber,
            version: version
        ) != nil
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

    public func addSubscription(
        _ subscription: OcaSubscriptionManagerSubscription
    ) async throws {
        guard !hasSubscription(subscription) else {
            throw Ocp1Error.alreadySubscribedToEvent
        }
        var subscriptions = subscriptions[subscription.event.emitterONo]
        if subscriptions == nil {
            subscriptions = NSMutableSet(object: subscription)
            self.subscriptions[subscription.event.emitterONo] = subscriptions
        } else {
            subscriptions?.add(subscription)
        }
    }

    public func removeSubscription(
        _ event: OcaEvent,
        property: OcaPropertyID?,
        subscriber: OcaMethod,
        version: OcaSubscriptionManagerSubscription.EventVersion
    ) async throws {
        guard let subscription = findSubscription(event, subscriber: subscriber, version: version)
        else {
            return
        }

        subscriptions[event.emitterONo]?.remove(subscription)
    }

    func notifySubscribers1(
        _ event: OcaEvent,
        parameters: Data
    ) async throws {
        guard let subscription = findSubscription(event, version: .ev1) else {
            return
        }

        let eventData = Ocp1EventData(event: event, eventParameters: parameters)
        let ntfParams = Ocp1NtfParams(
            parameterCount: 2,
            context: subscription.subscriberContext,
            eventData: eventData
        )
        let notification = Ocp1Notification1(
            targetONo: subscription.event.emitterONo,
            methodID: subscription.subscriber.methodID,
            parameters: ntfParams
        )

        try await sendMessage(notification, type: .ocaNtf1)
    }

    func notifyPropertyChangeSubscribers1(
        _ emitter: OcaONo,
        property: OcaPropertyID,
        parameters: Data
    ) async throws {
        let event = OcaEvent(emitterONo: emitter, eventID: OcaPropertyChangedEventID)

        guard let subscription = findSubscription(event, property: property, version: .ev1) else {
            return
        }

        let eventData = Ocp1EventData(event: event, eventParameters: parameters)
        let ntfParams = Ocp1NtfParams(
            parameterCount: 2,
            context: subscription.subscriberContext,
            eventData: eventData
        )
        let notification = Ocp1Notification1(
            targetONo: subscription.event.emitterONo,
            methodID: subscription.subscriber.methodID,
            parameters: ntfParams
        )

        try await sendMessage(notification, type: .ocaNtf1)
    }

    func notifySubscribers2(
        _ event: OcaEvent,
        parameters: Data
    ) async throws {
        guard hasSubscription(event, version: .ev2) else {
            return
        }

        let notification = Ocp1Notification2(
            event: event,
            notificationType: .event,
            data: parameters
        )
        try await sendMessage(notification, type: .ocaNtf2)
    }

    func notifyPropertyChangeSubscribers2(
        _ emitter: OcaONo,
        property: OcaPropertyID,
        parameters: Data
    ) async throws {
        let event = OcaEvent(emitterONo: emitter, eventID: OcaPropertyChangedEventID)

        guard hasSubscription(event, property: property, version: .ev2) else {
            return
        }

        let notification = Ocp1Notification2(
            event: event,
            notificationType: .event,
            data: parameters
        )
        try await sendMessage(notification, type: .ocaNtf2)
    }

    func sendMessage(
        _ message: Ocp1Message,
        type messageType: OcaMessageType
    ) async throws {
        let sequence: AsyncSyncSequence<[Ocp1Message]> = [message].async
        try await sendMessages(sequence.eraseToAnyAsyncSequence(), type: messageType)
    }
}
