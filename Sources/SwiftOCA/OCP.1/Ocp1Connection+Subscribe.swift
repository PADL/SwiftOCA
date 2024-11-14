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

public extension Ocp1Connection {
  /// a token that can be used by the client to unsubscribe
  final class SubscriptionCancellable: Hashable, Sendable {
    public static func == (
      lhs: Ocp1Connection.SubscriptionCancellable,
      rhs: Ocp1Connection.SubscriptionCancellable
    ) -> Bool {
      lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
      ObjectIdentifier(self).hash(into: &hasher)
    }

    let event: OcaEvent
    let callback: OcaSubscriptionCallback

    init(event: OcaEvent, callback: @escaping OcaSubscriptionCallback) {
      self.event = event
      self.callback = callback
    }
  }

  func isSubscribed(event: OcaEvent) -> Bool {
    subscriptions[event] != nil
  }

  func isSubscribed(_ cancellable: SubscriptionCancellable) -> Bool {
    guard let eventSubscriptions = subscriptions[cancellable.event] else { return false }
    return eventSubscriptions.subscriptions.contains(cancellable)
  }

  func addSubscription(
    event: OcaEvent,
    callback: @escaping OcaSubscriptionCallback
  ) async throws -> SubscriptionCancellable {
    let cancellable = SubscriptionCancellable(event: event, callback: callback)
    if let eventSubscriptions = subscriptions[event] {
      if eventSubscriptions.subscriptions.contains(cancellable) {
        throw Ocp1Error.alreadySubscribedToEvent
      }
      eventSubscriptions.subscriptions.insert(cancellable)
    } else {
      let eventSubscriptions = EventSubscriptions()
      eventSubscriptions.subscriptions.insert(cancellable)
      subscriptions[event] = eventSubscriptions

      try await subscriptionManager.addSubscription(
        event: event,
        subscriber: subscriber,
        subscriberContext: OcaBlob(),
        notificationDeliveryMode: .normal,
        destinationInformation: OcaNetworkAddress()
      )
    }

    return cancellable
  }

  func removeSubscription(_ cancellable: SubscriptionCancellable) async throws {
    guard let eventSubscriptions = subscriptions[cancellable.event],
          eventSubscriptions.subscriptions.contains(cancellable)
    else {
      throw Ocp1Error.notSubscribedToEvent
    }

    eventSubscriptions.subscriptions.remove(cancellable)
    if eventSubscriptions.subscriptions.isEmpty {
      try await subscriptionManager.removeSubscription(
        event: cancellable.event,
        subscriber: subscriber
      )
    }
  }

  internal func removeSubscriptions() async {
    await withTaskGroup(of: Void.self, returning: Void.self) { taskGroup in
      for event in subscriptions.keys {
        taskGroup.addTask { [self] in
          try? await subscriptionManager.removeSubscription(event: event, subscriber: subscriber)
        }
      }
    }
    subscriptions.removeAll()
  }

  internal func refreshSubscriptions() async {
    await withTaskGroup(of: Void.self, returning: Void.self) { taskGroup in
      for event in subscriptions.keys {
        taskGroup.addTask { [self] in
          try? await subscriptionManager.addSubscription(
            event: event,
            subscriber: subscriber,
            subscriberContext: OcaBlob(),
            notificationDeliveryMode: .normal,
            destinationInformation: OcaNetworkAddress()
          )
        }
      }
    }
  }

  internal func notifySubscribers(of event: OcaEvent, with parameters: Data) {
    guard let eventSubscriptions = subscriptions[event],
          !eventSubscriptions.subscriptions.isEmpty
    else {
      return
    }

    let subscriptions = eventSubscriptions.subscriptions

    Task {
      for subscription in subscriptions {
        try await subscription.callback(event, parameters)
      }
    }
  }
}
