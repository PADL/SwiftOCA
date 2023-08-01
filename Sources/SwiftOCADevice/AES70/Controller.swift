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

public protocol AES70Controller: Actor {
    func addSubscription(
        _ subscription: OcaSubscription
    ) async throws

    func removeSubscription(
        _ event: OcaEvent,
        subscriber: OcaMethod
    ) async throws

    func disableNotifications()
    func enableNotifications()
}

protocol AES70ControllerPrivate: AES70Controller {
    var subscriptions: [OcaONo: NSMutableSet] { get set }

    func sendMessages(
        _ messages: AnyAsyncSequence<Ocp1Message>,
        type messageType: OcaMessageType
    ) async throws
}

extension AES70ControllerPrivate {
    func findSubscription(
        _ event: OcaEvent,
        subscriber: OcaMethod? = nil
    ) -> OcaSubscription? {
        guard let subscriptions = subscriptions[event.emitterONo] else {
            return nil
        }
        return subscriptions.first(where: {
            let subscription = $0 as! OcaSubscription
            return subscription.event == event &&
                subscriber == nil ? true : subscription.subscriber == subscriber
        }) as? OcaSubscription
    }

    public func hasSubscription(_ subscription: OcaSubscription) -> Bool {
        findSubscription(
            subscription.event,
            subscriber: subscription.subscriber
        ) != nil
    }

    public func addSubscription(
        _ subscription: OcaSubscription
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
        subscriber: OcaMethod
    ) async throws {
        guard let subscription = findSubscription(event, subscriber: subscriber)
        else {
            return
        }

        subscriptions[event.emitterONo]?.remove(subscription)
    }

    func notifySubscribers1(
        _ event: OcaEvent,
        parameters: Data
    ) async throws {
        guard let subscription = findSubscription(event) else {
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

    // for EV2 event type support, but how do we signal this?
    func notifySubscribers2(
        _ event: OcaEvent,
        parameters: Data
    ) async throws {
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
