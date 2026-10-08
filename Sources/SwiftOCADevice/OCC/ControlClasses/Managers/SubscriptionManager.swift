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

@OcaDeviceClass
public class OcaSubscriptionManager: OcaManager {
  override open class var classID: OcaClassID { OcaClassID("1.3.4") }

  override open class var deviceEvents: [OcaDeviceEventDescriptor] {
    super.deviceEvents + [
      OcaDeviceEventDescriptor(
        eventID: SwiftOCA.OcaSubscriptionManager.NotificationsDisabledEventID,
        name: "NotificationsDisabled",
        eventDataType: OcaEmptyEventData.self
      ),
      OcaDeviceEventDescriptor(
        eventID: SwiftOCA.OcaSubscriptionManager.SynchronizeStateEventID,
        name: "SynchronizeState",
        eventDataType: OcaObjectListEventData.self
      ),
    ]
  }
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
    guard subscription.subscriberContext.count <= Int(Self.maximumSubscriberContextLength) else {
      throw Ocp1Error.status(.parameterOutOfRange)
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

  @OcaDeviceMethod(SwiftOCA.OcaSubscriptionManager.Methods.addSubscription, access: .read)
  private func addSubscription(
    event: OcaEvent,
    subscriber: OcaMethod,
    subscriberContext: OcaBlob,
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress,
    from controller: any OcaController
  ) async throws {
    let subscription = OcaSubscription(
      event: event,
      subscriber: subscriber,
      subscriberContext: subscriberContext,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    )
    try addSubscription(.subscription(subscription), for: controller)
  }

  @OcaDeviceMethod(SwiftOCA.OcaSubscriptionManager.Methods.removeSubscription, access: .read)
  private func removeSubscription(
    event: OcaEvent,
    subscriber: OcaMethod,
    from controller: any OcaController
  ) async throws {
    removeSubscription(event, subscriber: subscriber, for: controller)
  }

  @OcaDeviceMethod(
    SwiftOCA.OcaSubscriptionManager.Methods.addPropertyChangeSubscription,
    access: .read
  )
  private func addPropertyChangeSubscription(
    emitter: OcaONo,
    property: OcaPropertyID,
    subscriber: OcaMethod,
    subscriberContext: OcaBlob,
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress,
    from controller: any OcaController
  ) async throws {
    let subscription = OcaPropertyChangeSubscription(
      emitter: emitter,
      property: property,
      subscriber: subscriber,
      subscriberContext: subscriberContext,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    )
    try addSubscription(.propertyChangeSubscription(subscription), for: controller)
  }

  @OcaDeviceMethod(
    SwiftOCA.OcaSubscriptionManager.Methods.removePropertyChangeSubscription,
    access: .read
  )
  private func removePropertyChangeSubscription(
    emitter: OcaONo,
    property: OcaPropertyID,
    subscriber: OcaMethod,
    from controller: any OcaController
  ) async throws {
    removeSubscription(
      OcaEvent(emitterONo: emitter, eventID: OcaPropertyChangedEventID),
      subscriber: subscriber,
      for: controller
    )
  }

  @OcaDeviceMethod(SwiftOCA.OcaSubscriptionManager.Methods.disableNotifications, access: .write)
  private func disableNotifications(from controller: any OcaController) async throws {
    state = .eventsDisabled
    let event = OcaEvent(
      emitterONo: objectNumber,
      eventID: SwiftOCA.OcaSubscriptionManager.NotificationsDisabledEventID
    )
    try await deviceDelegate?.notifySubscribers(event)
  }

  @OcaDeviceMethod(SwiftOCA.OcaSubscriptionManager.Methods.addSubscription2, access: .read)
  private func addSubscription2(
    event: OcaEvent,
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress,
    from controller: any OcaController
  ) async throws {
    let subscription = OcaSubscription2(
      event: event,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    )
    try addSubscription(.subscription2(subscription), for: controller)
  }

  @OcaDeviceMethod(SwiftOCA.OcaSubscriptionManager.Methods.removeSubscription2, access: .read)
  private func removeSubscription2(
    event: OcaEvent,
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress,
    from controller: any OcaController
  ) async throws {
    let subscription = OcaSubscription2(
      event: event,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    )
    removeSubscription(.subscription2(subscription), for: controller)
  }

  @OcaDeviceMethod(
    SwiftOCA.OcaSubscriptionManager.Methods.addPropertyChangeSubscription2,
    access: .read
  )
  private func addPropertyChangeSubscription2(
    emitter: OcaONo,
    property: OcaPropertyID,
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress,
    from controller: any OcaController
  ) async throws {
    let subscription = OcaPropertyChangeSubscription2(
      emitter: emitter,
      property: property,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    )
    try addSubscription(.propertyChangeSubscription2(subscription), for: controller)
  }

  @OcaDeviceMethod(
    SwiftOCA.OcaSubscriptionManager.Methods.removePropertyChangeSubscription2,
    access: .read
  )
  private func removePropertyChangeSubscription2(
    emitter: OcaONo,
    property: OcaPropertyID,
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress,
    from controller: any OcaController
  ) async throws {
    let subscription = OcaPropertyChangeSubscription2(
      emitter: emitter,
      property: property,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    )
    removeSubscription(.propertyChangeSubscription2(subscription), for: controller)
  }

  // the model does not name the result
  @OcaDeviceMethod(SwiftOCA.OcaSubscriptionManager.Methods.addSubscription2List, access: .read)
  private func addSubscription2List(
    events: [OcaEvent],
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress,
    from controller: any OcaController
  ) async throws -> [OcaStatus] {

    return events.map { event in
      let returnedStatus: OcaStatus

      do {
        let subscription2 = OcaSubscription2(
          event: event,
          notificationDeliveryMode: notificationDeliveryMode,
          destinationInformation: destinationInformation
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

  @OcaDeviceMethod(SwiftOCA.OcaSubscriptionManager.Methods.removeSubscription2List, access: .read)
  private func removeSubscription2List(
    events: [OcaEvent],
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress,
    from controller: any OcaController
  ) async throws {
    for event in events {
      let subscription2 = OcaSubscription2(
        event: event,
        notificationDeliveryMode: notificationDeliveryMode,
        destinationInformation: destinationInformation
      )
      removeSubscription(.subscription2(subscription2), for: controller)
    }
  }

  // the model does not name the result
  @OcaDeviceMethod(
    SwiftOCA.OcaSubscriptionManager.Methods.addPropertyChangeSubscription2List,
    access: .read
  )
  private func addPropertyChangeSubscription2List(
    emitters: [OcaONo],
    properties: [OcaPropertyID],
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress,
    from controller: any OcaController
  ) async throws -> [OcaStatus] {

    guard emitters.count == properties.count else {
      throw Ocp1Error.status(.invalidRequest)
    }

    var returnedStatuses = [OcaStatus]()
    returnedStatuses.reserveCapacity(emitters.count)

    for i in 0..<emitters.count {
      let returnedStatus: OcaStatus

      do {
        let propertyChangeSubscription2 = OcaPropertyChangeSubscription2(
          emitter: emitters[i],
          property: properties[i],
          notificationDeliveryMode: notificationDeliveryMode,
          destinationInformation: destinationInformation
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

  @OcaDeviceMethod(
    SwiftOCA.OcaSubscriptionManager.Methods.removePropertyChangeSubscription2List,
    access: .read
  )
  private func removePropertyChangeSubscription2List(
    emitters: [OcaONo],
    properties: [OcaPropertyID],
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress,
    from controller: any OcaController
  ) async throws {

    guard emitters.count == properties.count else {
      throw Ocp1Error.status(.invalidRequest)
    }

    for i in 0..<emitters.count {
      let propertyChangeSubscription2 = OcaPropertyChangeSubscription2(
        emitter: emitters[i],
        property: properties[i],
        notificationDeliveryMode: notificationDeliveryMode,
        destinationInformation: destinationInformation
      )
      removeSubscription(.propertyChangeSubscription2(propertyChangeSubscription2), for: controller)
    }
  }

  func enqueueObjectChangedWhilstNotificationsDisabled(_ emitterONo: OcaONo) {
    objectsChangedWhilstNotificationsDisabled.insert(emitterONo)
  }

  @OcaDeviceMethod(SwiftOCA.OcaSubscriptionManager.Methods.reEnableNotifications, access: .write)
  private func reEnableNotifications(from controller: any OcaController) async throws {
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

  /// The longest EV1 subscriber context this device keeps, in bytes.
  public nonisolated static let maximumSubscriberContextLength: OcaUint16 = 4

  @OcaDeviceMethod(SwiftOCA.OcaSubscriptionManager.Methods.getMaximumSubscriberContextLength)
  private func getMaximumSubscriberContextLength(from controller: any OcaController) -> OcaUint16 {
    Self.maximumSubscriberContextLength
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    if controller.controlProtocol != .ocp1, Self.ev1MethodIDs.contains(command.methodID) {
      throw Ocp1Error.status(.notImplemented)
    }
    return try await super.handleCommand(command, from: controller)
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
