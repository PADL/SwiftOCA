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

extension AES70OCP1Connection {
    @MainActor
    func isSubscribed(event: OcaEvent,
                      callback: @escaping AES70SubscriptionCallback) -> Bool {
        guard let callbacks = subscribers[event] else {
            return false
        }
        return callbacks.contains(callback)
    }
    
    @MainActor
    @discardableResult
    private func addSubscriber(event: OcaEvent,
                               callback: @escaping AES70SubscriptionCallback,
                               addIfUnsubscribed: Bool) -> Bool {
        if let callbacks = subscribers[event] {
            callbacks.add(callback)
        } else if addIfUnsubscribed {
            subscribers[event] = NSMutableSet(object: callback)
        } else {
            return false
        }
        
        return true
    }
    
    @MainActor
    private func removeSubscriber(event: OcaEvent,
                                  callback: @escaping AES70SubscriptionCallback,
                                  lastSubscriber: inout Bool) throws {
        guard let callbacks = subscribers[event] else {
            throw Ocp1Error.status(.parameterError)
        }
        
        guard callbacks.contains(callback) else {
            throw Ocp1Error.status(.parameterError)
        }
        callbacks.remove(callback)
        
        lastSubscriber = callbacks.count == 0
    }
    
    @MainActor
    func addSubscription(event: OcaEvent,
                         callback: @escaping AES70SubscriptionCallback) async throws {
        if addSubscriber(event: event, callback: callback, addIfUnsubscribed: false) {
            return
        }
        
        try await subscriptionManager.addSubscription(event: event,
                                                      subscriber: subscriber,
                                                      subscriberContext: OcaBlob(),
                                                      notificationDeliveryMode: .reliable,
                                                      destinationInformation: OcaNetworkAddress())
        
        // handle the caller removing the subscription before the subscription request is processed
        if !isSubscribed(event: event, callback: callback) {
            throw Ocp1Error.callbackRemovedBeforeSubscribed
        }
        
        addSubscriber(event: event, callback: callback, addIfUnsubscribed: true)
    }
    
    @MainActor
    func removeSubscription(event: OcaEvent,
                            callback: @escaping AES70SubscriptionCallback) async throws {
        var lastSubscriber: Bool = false
        try removeSubscriber(event: event, callback: callback, lastSubscriber: &lastSubscriber)
        
        if lastSubscriber {
            try await removeSubscription(event: event)
        }
    }
    
    @MainActor
    public func removeSubscription(event: OcaEvent) async throws {
        try await subscriptionManager.removeSubscription(event: event, subscriber: subscriber)
        subscribers[event] = nil
    }
    
    @MainActor
    public func removeSubscriptions() async throws {
        for event in subscribers.keys {
            _ = try await removeSubscription(event: event)
        }
    }
    
    @MainActor
    func refreshSubscriptions() async throws {
        for event in subscribers.keys {
            try await subscriptionManager.addSubscription(event: event,
                                                          subscriber: subscriber,
                                                          subscriberContext: OcaBlob(),
                                                          notificationDeliveryMode: .reliable,
                                                          destinationInformation: OcaNetworkAddress())
        }
    }
}
