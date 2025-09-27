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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

private let subscriber = OcaMethod(oNo: 1055, methodID: OcaMethodID("1.1"))

public extension Ocp1Connection {
  /// a token that can be used by the client to unsubscribe
  final class SubscriptionCancellable: Hashable, Sendable, CustomStringConvertible {
    public static func == (
      lhs: Ocp1Connection.SubscriptionCancellable,
      rhs: Ocp1Connection.SubscriptionCancellable
    ) -> Bool {
      if let lhsLabel = lhs.label, let rhsLabel = rhs.label {
        lhsLabel == rhsLabel && lhs.event == rhs.event
      } else {
        lhs === rhs
      }
    }

    public func hash(into hasher: inout Hasher) {
      if let label {
        label.hash(into: &hasher)
        event.hash(into: &hasher)
      } else {
        ObjectIdentifier(self).hash(into: &hasher)
      }
    }

    // an optional label (reverse-DNS naming style recommended). Non-anonymous cancellables
    // are equal if their addresses equal; named cancellables are equal if their label and
    // events are equal.

    public let label: String?
    public let event: OcaEvent
    public let callback: OcaSubscriptionCallback

    init(label: String?, event: OcaEvent, callback: @escaping OcaSubscriptionCallback) {
      self.label = label
      self.event = event
      self.callback = callback
    }

    public var description: String {
      if let label {
        "event: \(event), label: \(label)"
      } else {
        "event: \(event)"
      }
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
    label: String? = nil,
    event: OcaEvent,
    callback: @escaping OcaSubscriptionCallback
  ) async throws -> SubscriptionCancellable {
    let cancellable = SubscriptionCancellable(label: label, event: event, callback: callback)
    if let eventSubscriptions = subscriptions[event] {
      precondition(!eventSubscriptions.subscriptions.isEmpty)
      if eventSubscriptions.subscriptions.contains(cancellable) {
        throw Ocp1Error.alreadySubscribedToEvent
      }
      eventSubscriptions.subscriptions.insert(cancellable)
    } else {
      let eventSubscriptions = EventSubscriptions()
      eventSubscriptions.subscriptions.insert(cancellable)
      subscriptions[event] = eventSubscriptions

      // Use batching for subscription changes to reduce network traffic
      await batchSubscriptionChange(event: event, changeType: .add)
      logger.trace("addSubscription: batched new OCA subscription for \(event)")
    }
    logger.trace("addSubscription: added \(cancellable) to subscription set")

    return cancellable
  }

  func removeSubscription(_ cancellable: SubscriptionCancellable) async throws {
    guard let eventSubscriptions = subscriptions[cancellable.event],
          eventSubscriptions.subscriptions.contains(cancellable)
    else {
      throw Ocp1Error.notSubscribedToEvent
    }

    eventSubscriptions.subscriptions.remove(cancellable)
    logger.trace("removeSubscription: removed \(cancellable) from subscription set")
    if eventSubscriptions.subscriptions.isEmpty {
      subscriptions[cancellable.event] = nil
      // Use batching for subscription changes to reduce network traffic
      await batchSubscriptionChange(event: cancellable.event, changeType: .remove)
      logger.trace("removeSubscription: batched OCA subscription removal for \(cancellable.event)")
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
      await withTaskGroup(of: Void.self, returning: Void.self) { taskGroup in
        for subscription in subscriptions {
          taskGroup.addTask {
            try? await subscription.callback(event, parameters)
          }
        }
      }
    }
  }

  // MARK: - Subscription Batching

  private func batchSubscriptionChange(event: OcaEvent, changeType: SubscriptionChangeType) async {
    pendingSubscriptionChanges[event] = changeType

    // Cancel existing batch task and start a new one with debouncing
    subscriptionBatchTask?.cancel()
    subscriptionBatchTask = Task {
      try? await Task.sleep(for: .milliseconds(50)) // 50ms debounce window

      guard !Task.isCancelled else { return }
      await processBatchedSubscriptionChanges()
    }
  }

  private func processBatchedSubscriptionChanges() async {
    let changes = pendingSubscriptionChanges
    pendingSubscriptionChanges.removeAll()

    guard !changes.isEmpty else { return }

    // Processing batched subscription changes

    // Process changes in parallel with controlled concurrency
    await withTaskGroup(of: Void.self) { taskGroup in
      var concurrentTasks = 0
      let maxConcurrentTasks = 5 // Limit concurrent subscription operations

      for (event, changeType) in changes {
        // Wait if we've reached max concurrent tasks
        if concurrentTasks >= maxConcurrentTasks {
          await taskGroup.next()
          concurrentTasks -= 1
        }

        taskGroup.addTask { [self] in
          do {
            switch changeType {
            case .add:
              try await subscriptionManager.addSubscription(
                event: event,
                subscriber: subscriber,
                subscriberContext: OcaBlob(),
                notificationDeliveryMode: .normal,
                destinationInformation: OcaNetworkAddress()
              )
            // Processed batched add subscription
            case .remove:
              try await subscriptionManager.removeSubscription(
                event: event,
                subscriber: subscriber
              )
              // Processed batched remove subscription
            }
          } catch {
            // Failed to process subscription change - error ignored
          }
        }
        concurrentTasks += 1
      }

      // Wait for remaining tasks
      while concurrentTasks > 0 {
        await taskGroup.next()
        concurrentTasks -= 1
      }
    }
  }
}
