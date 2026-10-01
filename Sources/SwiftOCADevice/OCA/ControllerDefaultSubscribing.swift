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

extension OcaController {
  /// Sends the event for each of `subscriptions` it matches: those the subscription
  /// manager holds for this controller to the event's emitter.
  func notify(
    _ event: OcaEvent,
    parameters eventParameters: OcaEventParameters,
    subscriptions: Set<OcaSubscriptionManagerSubscription>
  ) async throws {
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

    for subscription in subscriptions {
      // subscriptions are kept per emitter, so an emitter's other events must not be
      // delivered to a controller that subscribed to only one of them
      guard subscription.event.eventID == event.eventID else {
        continue
      }
      guard subscription.property == nil || property == subscription.property else {
        continue
      }

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

        if subscription.notificationDeliveryMode == .lightweight {
          try await (self as! OcaControllerLightweightNotifying)
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
          eventData: try parameters()
        )
        if subscription.notificationDeliveryMode == .lightweight {
          try await (self as! OcaControllerLightweightNotifying)
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
