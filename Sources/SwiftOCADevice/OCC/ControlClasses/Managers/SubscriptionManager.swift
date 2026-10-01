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

  /// A controller and its subscriptions to the events of one object, for as long as an
  /// event is being sent to it.
  struct Subscriber: Sendable {
    let controller: any OcaController
    let subscriptions: Set<OcaSubscriptionManagerSubscription>
  }

  /// What is kept of a subscriber. The controller is not owned: one that has gone,
  /// however it went, is no subscriber, and nothing here keeps it or what it refers to
  /// alive.
  private struct Entry {
    weak var controller: (any OcaController)?
    var subscriptions: Set<OcaSubscriptionManagerSubscription>
  }

  /// Every subscription there is: by the object whose events it is to, then by the
  /// controller that holds it. Nothing else records who subscribes to what, so an
  /// event's subscribers are read from here and no controller is asked.
  private var subscribers = [OcaONo: [ObjectIdentifier: Entry]]()

  /// The controllers subscribed to the emitter's events, each with its subscriptions.
  /// What was kept for a controller that has since gone is dropped as it is come upon.
  func subscribers(to emitterONo: OcaONo) -> [Subscriber] {
    guard let entries = subscribers[emitterONo] else { return [] }
    var live = [Subscriber]()
    live.reserveCapacity(entries.count)
    for (id, entry) in entries {
      if let controller = entry.controller {
        live.append(Subscriber(controller: controller, subscriptions: entry.subscriptions))
      } else {
        remove(id, from: emitterONo)
      }
    }
    return live
  }

  private func remove(_ id: ObjectIdentifier, from emitterONo: OcaONo) {
    subscribers[emitterONo]?[id] = nil
    if subscribers[emitterONo]?.isEmpty == true { subscribers[emitterONo] = nil }
  }

  /// The controller's subscriptions to the emitter's events. A controller is known by
  /// its identity, which a later one may be given once it has gone; what was kept for
  /// the one that went is not the later one's, and is dropped here.
  private func subscriptions(
    of controller: any OcaController,
    to emitterONo: OcaONo
  ) -> Set<OcaSubscriptionManagerSubscription> {
    let id = ObjectIdentifier(controller)
    guard let entry = subscribers[emitterONo]?[id] else { return [] }
    guard entry.controller != nil else {
      remove(id, from: emitterONo)
      return []
    }
    return entry.subscriptions
  }

  /// Whether the controller holds any subscription to the emitter's events.
  public func isSubscribed(
    _ controller: any OcaController,
    toEventsFrom emitterONo: OcaONo
  ) -> Bool {
    !subscriptions(of: controller, to: emitterONo).isEmpty
  }

  /// Subscriptions are kept per emitter. EV1 and EV2 subscriptions are independent: a
  /// controller could subscribe to some events with EV1 and others with EV2, unusual as
  /// that would be. So a matching subscription is one with the same event, property (for
  /// a property changed event), subscriber and version.
  private static func find(
    _ event: OcaEvent,
    property: OcaPropertyID? = nil,
    subscriber: OcaMethod? = nil,
    version: OcaSubscriptionManagerSubscription.EventVersion,
    in subscriptions: Set<OcaSubscriptionManagerSubscription>
  ) -> [OcaSubscriptionManagerSubscription] {
    precondition(property == nil || event.eventID == OcaPropertyChangedEventID)
    return subscriptions.filter { subscription in
      subscription.event == event &&
        (subscriber == nil ? true : subscription.subscriber == subscriber) &&
        subscription.property == property &&
        subscription.version == version
    }
  }

  /// Subscribes the controller, as its commands to this object do. A controller within
  /// the device's own process can be subscribed here without sending itself a command.
  public func addSubscription(
    _ subscription: OcaSubscriptionManagerSubscription,
    for controller: any OcaController
  ) throws {
    let emitterONo = subscription.event.emitterONo
    var subscriptions = subscriptions(of: controller, to: emitterONo)
    guard Self.find(
      subscription.event,
      subscriber: subscription.subscriber,
      version: subscription.version,
      in: subscriptions
    ).isEmpty else {
      throw Ocp1Error.alreadySubscribedToEvent(subscription.event)
    }
    guard controller is OcaControllerLightweightNotifying ||
      subscription.notificationDeliveryMode == .normal
    else {
      // only controllers implementing OcaControllerLightweightNotifying support
      // lightweight/fast notifications
      throw Ocp1Error.status(.parameterError)
    }
    subscriptions.insert(subscription)
    subscribers[emitterONo, default: [:]][ObjectIdentifier(controller)] =
      Entry(controller: controller, subscriptions: subscriptions)
  }

  public func removeSubscription(
    _ subscription: OcaSubscriptionManagerSubscription,
    for controller: any OcaController
  ) {
    remove([subscription], of: controller, from: subscription.event.emitterONo)
  }

  private func removeSubscription(
    _ event: OcaEvent,
    subscriber: OcaMethod,
    for controller: any OcaController
  ) {
    let subscriptions = Self.find(
      event,
      subscriber: subscriber,
      version: .ev1,
      in: subscriptions(of: controller, to: event.emitterONo)
    )
    remove(subscriptions, of: controller, from: event.emitterONo)
  }

  /// Nothing is kept for a controller with no subscription to an emitter, nor for an
  /// emitter nobody subscribes to: what is here is who to notify.
  private func remove(
    _ removed: [OcaSubscriptionManagerSubscription],
    of controller: any OcaController,
    from emitterONo: OcaONo
  ) {
    let subscriptions = subscriptions(of: controller, to: emitterONo).subtracting(removed)
    let id = ObjectIdentifier(controller)
    if subscriptions.isEmpty {
      remove(id, from: emitterONo)
    } else {
      subscribers[emitterONo]?[id]?.subscriptions = subscriptions
    }
  }

  /// Drops every subscription the controller holds, as when its connection has gone.
  public func removeSubscriptions(of controller: any OcaController) {
    let id = ObjectIdentifier(controller)
    for emitterONo in subscribers.keys where subscribers[emitterONo]?[id] != nil {
      remove(id, from: emitterONo)
    }
  }

  private func addSubscription(
    _ subscription: SwiftOCA.OcaSubscriptionManager.AddSubscriptionParameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureReadable(by: controller, command: command)
    try addSubscription(.subscription(subscription), for: controller)
  }

  private func removeSubscription(
    _ subscription: SwiftOCA.OcaSubscriptionManager.RemoveSubscriptionParameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureReadable(by: controller, command: command)
    removeSubscription(subscription.event, subscriber: subscription.subscriber, for: controller)
  }

  private func addPropertyChangeSubscription(
    _ subscription: SwiftOCA.OcaSubscriptionManager.AddPropertyChangeSubscriptionParameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureReadable(by: controller, command: command)
    try addSubscription(.propertyChangeSubscription(subscription), for: controller)
  }

  private func removePropertyChangeSubscription(
    _ subscription: SwiftOCA.OcaSubscriptionManager.RemovePropertyChangeSubscriptionParameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureReadable(by: controller, command: command)
    removeSubscription(
      OcaEvent(emitterONo: subscription.emitter, eventID: OcaPropertyChangedEventID),
      subscriber: subscription.subscriber,
      for: controller
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
    try await ensureReadable(by: controller, command: command)
    try addSubscription(.subscription2(subscription), for: controller)
  }

  private func removeSubscription2(
    _ subscription: SwiftOCA.OcaSubscriptionManager.RemoveSubscription2Parameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureReadable(by: controller, command: command)
    removeSubscription(.subscription2(subscription), for: controller)
  }

  private func addPropertyChangeSubscription2(
    _ subscription: SwiftOCA.OcaSubscriptionManager.AddPropertyChangeSubscription2Parameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureReadable(by: controller, command: command)
    try addSubscription(.propertyChangeSubscription2(subscription), for: controller)
  }

  private func removePropertyChangeSubscription2(
    _ subscription: SwiftOCA.OcaSubscriptionManager.RemovePropertyChangeSubscription2Parameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureReadable(by: controller, command: command)
    removeSubscription(.propertyChangeSubscription2(subscription), for: controller)
  }

  private func addSubscription2List(
    _ subscription: SwiftOCA.OcaSubscriptionManager.AddSubscription2ListParameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws -> [OcaStatus] {
    try await ensureReadable(by: controller, command: command)

    return subscription.events.map { event in
      let returnedStatus: OcaStatus

      do {
        let subscription2 = OcaSubscription2(
          event: event,
          notificationDeliveryMode: subscription.notificationDeliveryMode,
          destinationInformation: subscription.destinationInformation
        )
        try addSubscription(.subscription2(subscription2), for: controller)
        returnedStatus = .ok
      } catch Ocp1Error.alreadySubscribedToEvent(_) {
        returnedStatus = .invalidRequest
      } catch let Ocp1Error.status(status) {
        returnedStatus = status
      } catch {
        returnedStatus = .deviceError
      }

      return returnedStatus
    }
  }

  private func removeSubscription2List(
    _ subscription: SwiftOCA.OcaSubscriptionManager.RemoveSubscription2ListParameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureReadable(by: controller, command: command)
    for event in subscription.events {
      let subscription2 = OcaSubscription2(
        event: event,
        notificationDeliveryMode: subscription.notificationDeliveryMode,
        destinationInformation: subscription.destinationInformation
      )
      removeSubscription(.subscription2(subscription2), for: controller)
    }
  }

  private func addPropertyChangeSubscription2List(
    _ subscription: SwiftOCA.OcaSubscriptionManager.AddPropertyChangeSubscription2ListParameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws -> [OcaStatus] {
    try await ensureReadable(by: controller, command: command)

    guard subscription.emitters.count == subscription.properties.count else {
      throw Ocp1Error.status(.invalidRequest)
    }

    var returnedStatuses = [OcaStatus]()
    returnedStatuses.reserveCapacity(subscription.emitters.count)

    for i in 0..<subscription.emitters.count {
      let returnedStatus: OcaStatus

      do {
        let propertyChangeSubscription2 = OcaPropertyChangeSubscription2(
          emitter: subscription.emitters[i],
          property: subscription.properties[i],
          notificationDeliveryMode: subscription.notificationDeliveryMode,
          destinationInformation: subscription.destinationInformation
        )
        try addSubscription(.propertyChangeSubscription2(propertyChangeSubscription2), for: controller)
        returnedStatus = .ok
      } catch Ocp1Error.alreadySubscribedToEvent(_) {
        returnedStatus = .invalidRequest
      } catch let Ocp1Error.status(status) {
        returnedStatus = status
      } catch {
        returnedStatus = .deviceError
      }

      returnedStatuses.append(returnedStatus)
    }

    return returnedStatuses
  }

  private func removePropertyChangeSubscription2List(
    _ subscription: SwiftOCA.OcaSubscriptionManager.RemovePropertyChangeSubscription2ListParameters,
    from controller: any OcaController,
    command: Ocp1Command
  ) async throws {
    try await ensureReadable(by: controller, command: command)

    guard subscription.emitters.count == subscription.properties.count else {
      throw Ocp1Error.status(.invalidRequest)
    }

    for i in 0..<subscription.emitters.count {
      let propertyChangeSubscription2 = OcaPropertyChangeSubscription2(
        emitter: subscription.emitters[i],
        property: subscription.properties[i],
        notificationDeliveryMode: subscription.notificationDeliveryMode,
        destinationInformation: subscription.destinationInformation
      )
      removeSubscription(.propertyChangeSubscription2(propertyChangeSubscription2), for: controller)
    }
  }

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
    let parameters = OcaObjectListEventData(
      objectList: Array(objectsChangedWhilstNotificationsDisabled)
    )
    objectsChangedWhilstNotificationsDisabled.removeAll()
    // notifications must be back on before SynchronizeState is emitted: while they are
    // off the event saying what changed is itself queued as another change, not sent
    state = .normal
    try await deviceDelegate?.notifySubscribers(event, eventData: parameters)
  }

  /// EV1 subscription methods; OCP.2 supports only EV2 (AES70-4 6.3.6.1)
  private static let ev1MethodIDs: Set<OcaMethodID> = [
    OcaMethodID("3.1"), OcaMethodID("3.2"), OcaMethodID("3.5"), OcaMethodID("3.6"),
  ]

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    if controller.controlProtocol != .ocp1, Self.ev1MethodIDs.contains(command.methodID) {
      throw Ocp1Error.status(.notImplemented)
    }

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
      return try controller.encodeResponse(maximumSubscriberContextLength, name: "Max")
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
    case OcaMethodID("3.12"):
      let subscription: SwiftOCA.OcaSubscriptionManager
        .AddSubscription2ListParameters = try decodeCommand(command)
      return try await controller.encodeResponse(
        addSubscription2List(subscription, from: controller, command: command),
        name: "Statuses" // name not in AES70-2023 model
      )
    case OcaMethodID("3.13"):
      let subscription: SwiftOCA.OcaSubscriptionManager
        .RemoveSubscription2ListParameters = try decodeCommand(command)
      try await removeSubscription2List(subscription, from: controller, command: command)
      return Ocp1Response()
    case OcaMethodID("3.14"):
      let subscription: SwiftOCA.OcaSubscriptionManager
        .AddPropertyChangeSubscription2ListParameters = try decodeCommand(command)
      return try await controller.encodeResponse(
        addPropertyChangeSubscription2List(subscription, from: controller, command: command),
        name: "Statuses" // name not in AES70-2023 model
      )
    case OcaMethodID("3.15"):
      let subscription: SwiftOCA.OcaSubscriptionManager
        .RemovePropertyChangeSubscription2ListParameters = try decodeCommand(command)
      try await removePropertyChangeSubscription2List(
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
      role: "SubscriptionManager",
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
