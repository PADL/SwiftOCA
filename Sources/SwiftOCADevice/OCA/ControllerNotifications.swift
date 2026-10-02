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
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
@_spi(SwiftOCAPrivate)
import SwiftOCA

/// A controller that can be sent a notification somewhere other than down its own
/// connection, which a subscription asking for lightweight delivery needs.
public protocol OcaControllerLightweightNotifying: OcaController {
  func sendMessage(
    _ message: Ocp1Message,
    type messageType: OcaMessageType,
    to destinationAddress: OcaNetworkAddress
  ) async throws
}

/// A notification built for a controller, ready to be sent to it.
private struct OcaNotificationMessage: Sendable {
  let message: any Ocp1Message
  let type: OcaMessageType
  /// Where a lightweight notification is to go; nil for the controller's own connection.
  let destination: OcaNetworkAddress?
}

extension OcaController {
  /// One notification for each of `subscriptions` that the event matches.
  fileprivate nonisolated func notifications(
    of event: OcaEvent,
    parameters eventParameters: OcaEventParameters,
    subscriptions: Set<OcaSubscriptionManagerSubscription>
  ) throws -> [OcaNotificationMessage] {
    let property = eventParameters.propertyID
    let format = controlProtocol.parameterFormat
    // encoded once, for the first subscription that is delivered
    var encoded: OcaEncodedEventData?
    func parameters() throws -> OcaEncodedEventData {
      if let encoded { return encoded }
      let eventData = try eventParameters.encodedEventData(as: format)
      encoded = eventData
      return eventData
    }

    var notifications = [OcaNotificationMessage]()
    for subscription in subscriptions {
      // subscriptions are kept per emitter, so an emitter's other events must not be
      // delivered to a controller that subscribed to only one of them
      guard subscription.event.eventID == event.eventID else {
        continue
      }
      guard subscription.property == nil || property == subscription.property else {
        continue
      }
      let destination = subscription.notificationDeliveryMode == .lightweight
        ? subscription.destinationInformation : nil

      switch subscription.version {
      case .ev1:
        guard format == .ocp1 else {
          // EV1 subscriptions are refused on OCP.2, so this cannot arise
          throw Ocp1Error.unsupportedControlProtocol
        }
        let eventData = Ocp1EventData(
          event: subscription.event,
          eventParameters: try parameters().data
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
        notifications.append(.init(message: notification, type: .ocaNtf1, destination: destination))
      case .ev2:
        let notification = Ocp1Notification2(
          event: subscription.event,
          notificationType: .event,
          eventData: try parameters()
        )
        notifications.append(.init(message: notification, type: .ocaNtf2, destination: destination))
      }
    }
    return notifications
  }

  /// Sends the event for each of `subscriptions` it matches, each in a PDU of its own.
  func notify(
    _ event: OcaEvent,
    parameters eventParameters: OcaEventParameters,
    subscriptions: Set<OcaSubscriptionManagerSubscription>
  ) async throws {
    let notifications = try notifications(
      of: event,
      parameters: eventParameters,
      subscriptions: subscriptions
    )
    for notification in notifications {
      if let destination = notification.destination {
        try await (self as! OcaControllerLightweightNotifying)
          .sendMessage(notification.message, type: notification.type, to: destination)
      } else {
        try await sendMessage(notification.message, type: notification.type)
      }
    }
  }
}

/// Notifications pending for a device's controllers while a scope is open: see
/// `OcaDevice.withCoalescedNotifications`. Part of the device's own state.
struct OcaPendingNotifications: Sendable {
  /// What a controller is due: batches of messages of one type, in the order raised.
  private struct Pending: Sendable {
    weak var controller: (any OcaController)?
    var batches = [(type: OcaMessageType, messages: [any Ocp1Message])]()

    mutating func append(_ notification: OcaNotificationMessage) {
      // a PDU holds messages of one type, and can count no more than this many
      if let last = batches.indices.last, batches[last].type == notification.type,
         batches[last].messages.count < Int(OcaUint16.max)
      {
        batches[last].messages.append(notification.message)
      } else {
        batches.append((notification.type, [notification.message]))
      }
    }
  }

  private var pending = [Pending]()

  var isEmpty: Bool { pending.isEmpty }

  private mutating func index(of controller: any OcaController) -> Int {
    if let index = pending.firstIndex(where: { $0.controller === controller }) { return index }
    pending.append(Pending(controller: controller))
    return pending.endIndex - 1
  }

  /// Adds the event's notifications for the controller. Lightweight ones are not added:
  /// true is returned if there are any, for the caller to send.
  mutating func push(
    _ event: OcaEvent,
    parameters: OcaEventParameters,
    subscriptions: Set<OcaSubscriptionManagerSubscription>,
    for controller: any OcaController
  ) throws -> Bool {
    var lightweight = false
    let notifications = try controller.notifications(
      of: event,
      parameters: parameters,
      subscriptions: subscriptions
    )
    var index: Int?
    for notification in notifications {
      if notification.destination == nil {
        if index == nil { index = self.index(of: controller) }
        pending[index!].append(notification)
      } else {
        lightweight = true
      }
    }
    return lightweight
  }

  /// Removes and returns what is pending.
  mutating func pop() -> OcaPendingNotifications {
    defer { pending = [] }
    return self
  }

  /// Sends each controller that is still there what is pending for it.
  func send(logger: Logger) async {
    guard !pending.isEmpty else { return }
    await withDiscardingTaskGroup { group in
      for entry in pending {
        guard let controller = entry.controller else { continue }
        let batches = entry.batches
        group.addTask {
          do {
            for batch in batches {
              try await controller.sendMessages(batch.messages, type: batch.type)
            }
          } catch Ocp1Error.notConnected {
            // a controller on its way out
          } catch {
            logger.warning("failed to notify \(controller): \(error)")
          }
        }
      }
    }
  }
}
