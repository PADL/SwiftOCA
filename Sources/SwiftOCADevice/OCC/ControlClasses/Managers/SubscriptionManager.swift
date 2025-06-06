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
import SwiftOCA

public class OcaSubscriptionManager: OcaManager {
  override open class var classID: OcaClassID { OcaClassID("1.3.4") }
  override open class var classVersion: OcaClassVersionNumber { 2 }

  @OcaDeviceProperty(propertyID: OcaPropertyID("3.1"))
  public var state: OcaSubscriptionManagerState = .normal

  private var objectsChangedWhilstNotificationsDisabled = Set<OcaONo>()

  /// note these functions don't need to be marked @OcaDevice because they do not
  /// mutate any state in the subscription manager, only the controller (which is
  /// the controller's responsibility to handle)

  private func addSubscription(
    _ subscription: SwiftOCA.OcaSubscriptionManager.AddSubscriptionParameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureWritable(by: controller, command: command)
    try await controller.addSubscription(.subscription(subscription))
  }

  private func removeSubscription(
    _ subscription: SwiftOCA.OcaSubscriptionManager.RemoveSubscriptionParameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureWritable(by: controller, command: command)
    try await controller.removeSubscription(
      subscription.event,
      property: nil,
      subscriber: subscription.subscriber
    )
  }

  private func addPropertyChangeSubscription(
    _ subscription: SwiftOCA.OcaSubscriptionManager.AddPropertyChangeSubscriptionParameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureWritable(by: controller, command: command)
    try await controller.addSubscription(.propertyChangeSubscription(subscription))
  }

  private func removePropertyChangeSubscription(
    _ subscription: SwiftOCA.OcaSubscriptionManager.RemovePropertyChangeSubscriptionParameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureWritable(by: controller, command: command)
    try await controller.removeSubscription(
      OcaEvent(emitterONo: subscription.emitter, eventID: OcaPropertyChangedEventID),
      property: subscription.property,
      subscriber: subscription.subscriber
    )
  }

  private func disableNotifications(
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureWritable(by: controller, command: command)
    state = .eventsDisabled
    let event = OcaEvent(
      emitterONo: objectNumber,
      eventID: SwiftOCA.OcaSubscriptionManager.NotificationsDisabledEventID
    )
    try await deviceDelegate?.notifySubscribers(event)
  }

  private func addSubscription2(
    _ subscription: SwiftOCA.OcaSubscriptionManager.AddSubscription2Parameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureWritable(by: controller, command: command)
    try await controller.addSubscription(.subscription2(subscription))
  }

  private func removeSubscription2(
    _ subscription: SwiftOCA.OcaSubscriptionManager.RemoveSubscription2Parameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureWritable(by: controller, command: command)
    try await controller.removeSubscription(.subscription2(subscription))
  }

  private func addPropertyChangeSubscription2(
    _ subscription: SwiftOCA.OcaSubscriptionManager.AddPropertyChangeSubscription2Parameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureWritable(by: controller, command: command)
    try await controller.addSubscription(.propertyChangeSubscription2(subscription))
  }

  private func removePropertyChangeSubscription2(
    _ subscription: SwiftOCA.OcaSubscriptionManager.RemovePropertyChangeSubscription2Parameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureWritable(by: controller, command: command)
    try await controller.removeSubscription(.propertyChangeSubscription2(subscription))
  }

  /// the following two functions, however, _do_ mutate state on the subscription manager
  /// and must run on the @OcaDevice global actor

  func enqueueObjectChangedWhilstNotificationsDisabled(_ emitterONo: OcaONo) {
    objectsChangedWhilstNotificationsDisabled.insert(emitterONo)
  }

  private func reenableNotifications(
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureWritable(by: controller, command: command)
    let event = OcaEvent(
      emitterONo: objectNumber,
      eventID: SwiftOCA.OcaSubscriptionManager.SynchronizeStateEventID
    )
    let parameters: Data = try Ocp1Encoder()
      .encode(
        OcaObjectListEventData(objectList: Array(objectsChangedWhilstNotificationsDisabled))
      )
    try await deviceDelegate?.notifySubscribers(event, parameters: parameters)
    objectsChangedWhilstNotificationsDisabled.removeAll()
    state = .normal
  }

  override public func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.1"):
      let subscription: SwiftOCA.OcaSubscriptionManager
        .AddSubscriptionParameters = try decodeCommand(command)
      try await addSubscription(subscription, from: controller, command: command)
      return Ocp1Response()
    case OcaMethodID("3.2"):
      let subscription: SwiftOCA.OcaSubscriptionManager
        .RemoveSubscriptionParameters = try decodeCommand(command)
      try await removeSubscription(subscription, from: controller, command: command)
      return Ocp1Response()
    case OcaMethodID("3.3"):
      try decodeNullCommand(command)
      try await disableNotifications(from: controller, command: command)
      return Ocp1Response()
    case OcaMethodID("3.4"):
      try decodeNullCommand(command)
      try await reenableNotifications(from: controller, command: command)
      return Ocp1Response()
    case OcaMethodID("3.5"):
      let subscription: SwiftOCA.OcaSubscriptionManager
        .AddPropertyChangeSubscriptionParameters = try decodeCommand(command)
      try await addPropertyChangeSubscription(
        subscription,
        from: controller,
        command: command
      )
      return Ocp1Response()
    case OcaMethodID("3.6"):
      let subscription: SwiftOCA.OcaSubscriptionManager
        .RemovePropertyChangeSubscriptionParameters = try decodeCommand(command)
      try await removePropertyChangeSubscription(
        subscription,
        from: controller,
        command: command
      )
      return Ocp1Response()
    case OcaMethodID("3.7"):
      try decodeNullCommand(command)
      // Returns maximum byte length of payload of EV1 subscriber context parameter that this
      // device supports
      let maximumSubscriberContextLength = OcaUint16(4)
      return try encodeResponse(maximumSubscriberContextLength)
    case OcaMethodID("3.8"):
      let subscription: SwiftOCA.OcaSubscriptionManager
        .AddSubscription2Parameters = try decodeCommand(command)
      try await addSubscription2(subscription, from: controller, command: command)
      return Ocp1Response()
    case OcaMethodID("3.9"):
      let subscription: SwiftOCA.OcaSubscriptionManager
        .RemoveSubscription2Parameters = try decodeCommand(command)
      try await removeSubscription2(subscription, from: controller, command: command)
      return Ocp1Response()
    case OcaMethodID("3.10"):
      let subscription: SwiftOCA.OcaSubscriptionManager
        .AddPropertyChangeSubscription2Parameters = try decodeCommand(command)
      try await addPropertyChangeSubscription2(
        subscription,
        from: controller,
        command: command
      )
      return Ocp1Response()
    case OcaMethodID("3.11"):
      let subscription: SwiftOCA.OcaSubscriptionManager
        .RemovePropertyChangeSubscription2Parameters = try decodeCommand(command)
      try await removePropertyChangeSubscription2(
        subscription,
        from: controller,
        command: command
      )
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }

  public convenience init(deviceDelegate: OcaDevice? = nil) async throws {
    try await self.init(
      objectNumber: OcaSubscriptionManagerONo,
      role: "Subscription Manager",
      deviceDelegate: deviceDelegate,
      addToRootBlock: true
    )
  }
}

public enum OcaSubscriptionManagerSubscription: Codable, Equatable, Hashable, Sendable {
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
      subscription.event
    case let .subscription2(subscription):
      subscription.event
    case let .propertyChangeSubscription(propertyChangeSubscription):
      OcaEvent(
        emitterONo: propertyChangeSubscription.emitter,
        eventID: OcaPropertyChangedEventID
      )
    case let .propertyChangeSubscription2(propertyChangeSubscription):
      OcaEvent(
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

  var subscriber: OcaMethod? {
    switch self {
    case let .subscription(subscription):
      subscription.subscriber
    case .subscription2:
      nil
    case let .propertyChangeSubscription(propertyChangeSubscription):
      propertyChangeSubscription.subscriber
    case .propertyChangeSubscription2:
      nil
    }
  }

  var subscriberContext: OcaBlob {
    switch self {
    case let .subscription(subscription):
      subscription.subscriberContext
    case .subscription2:
      LengthTaggedData16()
    case let .propertyChangeSubscription(propertyChangeSubscription):
      propertyChangeSubscription.subscriberContext
    case .propertyChangeSubscription2:
      LengthTaggedData16()
    }
  }

  var notificationDeliveryMode: OcaNotificationDeliveryMode {
    switch self {
    case let .subscription(subscription):
      subscription.notificationDeliveryMode
    case let .subscription2(subscription):
      subscription.notificationDeliveryMode
    case let .propertyChangeSubscription(propertyChangeSubscription):
      propertyChangeSubscription.notificationDeliveryMode
    case let .propertyChangeSubscription2(propertyChangeSubscription):
      propertyChangeSubscription.notificationDeliveryMode
    }
  }

  var destinationInformation: OcaNetworkAddress {
    switch self {
    case let .subscription(subscription):
      subscription.destinationInformation
    case let .subscription2(subscription):
      subscription.destinationInformation
    case let .propertyChangeSubscription(propertyChangeSubscription):
      propertyChangeSubscription.destinationInformation
    case let .propertyChangeSubscription2(propertyChangeSubscription):
      propertyChangeSubscription.destinationInformation
    }
  }
}
