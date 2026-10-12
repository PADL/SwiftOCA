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

  /// The most subscriptions one controller may hold by its commands, over every emitter.
  /// In-process callers are not held to it: an NMOS bridge subscribes to every property.
  package nonisolated static let maximumSubscriptionsPerController = 4096

  /// How many subscriptions the controller holds, over every emitter. This walks every
  /// emitter, so a command counts once and not for each subscription it adds.
  func subscriptionCount(for controller: any OcaController) -> Int {
    let id = ObjectIdentifier(controller)
    return subscribers.values.reduce(0) { count, entries in
      guard let entry = entries[id], entry.controller === controller else { return count }
      return count + entry.subscriptions.count
    }
  }

  /// What is kept of the controller's subscriptions to the emitter. A controller is known by
  /// its identity, which a later one may be given once it has gone; what was kept for
  /// the one that went is not the later one's, and is dropped here.
  private func entry(for controller: any OcaController, to emitterONo: OcaONo) -> Entry? {
    let id = ObjectIdentifier(controller)
    guard let entry = subscribers[emitterONo]?[id] else { return nil }
    guard entry.controller != nil else {
      remove(id, from: emitterONo)
      return nil
    }
    return entry
  }

  /// Whether the controller holds any subscription to the emitter's events.
  public func isSubscribed(
    _ controller: any OcaController,
    toEventsFrom emitterONo: OcaONo
  ) -> Bool {
    entry(for: controller, to: emitterONo) != nil
  }

  /// Subscribes the controller, as its commands to this object do. A controller within
  /// the device's own process can be subscribed here without sending itself a command.
  /// One the controller already holds (see `canonicalized()`) throws
  /// `alreadySubscribedToEvent`. The caller is trusted: neither the emitter nor
  /// `maximumSubscriptionsPerController` is checked, as they are for a command.
  public func addSubscription(
    _ subscription: OcaSubscriptionManagerSubscription,
    for controller: any OcaController
  ) throws {
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
    guard held(subscription, by: controller) == nil else {
      throw Ocp1Error.alreadySubscribedToEvent(subscription.event)
    }
    subscribers[subscription.event.emitterONo, default: [:]][
      ObjectIdentifier(controller),
      default: Entry(controller: controller, subscriptions: [])
    ].subscriptions.insert(subscription)
  }

  /// Removes the controller's subscription with the same `canonicalized()` form as
  /// `subscription`, if it holds one. Nothing is kept for a controller with no
  /// subscription to an emitter, nor for an emitter nobody subscribes to.
  public func removeSubscription(
    _ subscription: OcaSubscriptionManagerSubscription,
    for controller: any OcaController
  ) {
    let emitterONo = subscription.event.emitterONo
    let id = ObjectIdentifier(controller)
    guard let held = held(subscription, by: controller) else { return }
    subscribers[emitterONo]?[id]?.subscriptions.remove(held)
    if subscribers[emitterONo]?[id]?.subscriptions.isEmpty == true {
      remove(id, from: emitterONo)
    }
  }

  /// Drops every subscription the controller holds, as when its connection has gone.
  public func removeSubscriptions(of controller: any OcaController) {
    let id = ObjectIdentifier(controller)
    for emitterONo in subscribers.keys where subscribers[emitterONo]?[id] != nil {
      remove(id, from: emitterONo)
    }
  }

  /// The controller's subscription with the same `canonicalized()` form as `subscription`.
  /// The search is of its subscriptions to one emitter, which are few.
  private func held(
    _ subscription: OcaSubscriptionManagerSubscription,
    by controller: any OcaController
  ) -> OcaSubscriptionManagerSubscription? {
    let canonical = subscription.canonicalized()
    return entry(for: controller, to: subscription.event.emitterONo)?
      .subscriptions.first { $0.canonicalized() == canonical }
  }

  /// Subscribes the controller on its command. One to an object that is not there is
  /// refused, then one over `maximumSubscriptionsPerController`, then one it already
  /// holds. `count` is how many it holds, taken once a command.
  private func addSubscription(
    _ subscription: OcaSubscriptionManagerSubscription,
    from controller: any OcaController,
    holding count: Int? = nil
  ) async throws {
    // the one await comes first, so the count, the search and the insert are one turn
    guard let _: OcaRoot = await deviceDelegate?
      .resolve(objectNumber: subscription.event.emitterONo)
    else {
      throw Ocp1Error.status(.badONo)
    }
    // before the search for a duplicate, so a long list from a controller at the limit
    // searches nothing
    guard (count ?? subscriptionCount(for: controller)) < Self.maximumSubscriptionsPerController
    else {
      throw Ocp1Error.status(.outOfMemory)
    }
    do {
      try addSubscription(subscription, for: controller)
    } catch Ocp1Error.alreadySubscribedToEvent(_) {
      throw Ocp1Error.status(.invalidRequest)
    }
  }

  /// Statuses for a list of subscriptions, each added as its own command would be.
  private func addSubscriptions(
    _ subscriptions: [OcaSubscriptionManagerSubscription],
    from controller: any OcaController
  ) async -> [OcaStatus] {
    var statuses = [OcaStatus]()
    statuses.reserveCapacity(subscriptions.count)
    var count = subscriptionCount(for: controller)
    for subscription in subscriptions {
      do {
        try await addSubscription(subscription, from: controller, holding: count)
        count += 1
        statuses.append(.ok)
      } catch let Ocp1Error.status(status) {
        statuses.append(status)
      } catch {
        statuses.append(.deviceError)
      }
    }
    return statuses
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
    try await addSubscription(.subscription(subscription), from: controller)
  }

  @OcaDeviceMethod(SwiftOCA.OcaSubscriptionManager.Methods.removeSubscription, access: .read)
  private func removeSubscription(
    event: OcaEvent,
    subscriber: OcaMethod,
    from controller: any OcaController
  ) async throws {
    // EV1 subscriptions are told apart by event and subscriber alone (see canonicalized())
    let subscription = OcaSubscription(
      event: event,
      subscriber: subscriber,
      subscriberContext: OcaBlob(),
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )
    removeSubscription(.subscription(subscription), for: controller)
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
    try await addSubscription(.propertyChangeSubscription(subscription), from: controller)
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
    let subscription = OcaPropertyChangeSubscription(
      emitter: emitter,
      property: property,
      subscriber: subscriber,
      subscriberContext: OcaBlob(),
      notificationDeliveryMode: .normal,
      destinationInformation: OcaNetworkAddress()
    )
    removeSubscription(.propertyChangeSubscription(subscription), for: controller)
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
    try await addSubscription(.subscription2(subscription), from: controller)
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
    try await addSubscription(.propertyChangeSubscription2(subscription), from: controller)
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
    let subscriptions = events.map { event in
      OcaSubscriptionManagerSubscription.subscription2(OcaSubscription2(
        event: event,
        notificationDeliveryMode: notificationDeliveryMode,
        destinationInformation: destinationInformation
      ))
    }
    return await addSubscriptions(subscriptions, from: controller)
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

    let subscriptions = zip(emitters, properties).map { emitter, property in
      OcaSubscriptionManagerSubscription.propertyChangeSubscription2(
        OcaPropertyChangeSubscription2(
          emitter: emitter,
          property: property,
          notificationDeliveryMode: notificationDeliveryMode,
          destinationInformation: destinationInformation
        )
      )
    }
    return await addSubscriptions(subscriptions, from: controller)
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

  /// A subscription is told apart by what its remove method names; `canonicalized()` drops
  /// the rest. EV1 drops the context, delivery mode and destination; EV2 drops the
  /// destination of normal delivery, which goes down the controller's own connection.
  func canonicalized() -> Self {
    switch self {
    case let .subscription(subscription):
      .subscription(OcaSubscription(
        event: subscription.event,
        subscriber: subscription.subscriber,
        subscriberContext: OcaBlob(),
        notificationDeliveryMode: .normal,
        destinationInformation: OcaNetworkAddress()
      ))
    case let .propertyChangeSubscription(subscription):
      .propertyChangeSubscription(OcaPropertyChangeSubscription(
        emitter: subscription.emitter,
        property: subscription.property,
        subscriber: subscription.subscriber,
        subscriberContext: OcaBlob(),
        notificationDeliveryMode: .normal,
        destinationInformation: OcaNetworkAddress()
      ))
    case let .subscription2(subscription) where subscription.notificationDeliveryMode == .normal:
      .subscription2(OcaSubscription2(
        event: subscription.event,
        notificationDeliveryMode: .normal,
        destinationInformation: OcaNetworkAddress()
      ))
    case let .propertyChangeSubscription2(subscription)
      where subscription.notificationDeliveryMode == .normal:
      .propertyChangeSubscription2(OcaPropertyChangeSubscription2(
        emitter: subscription.emitter,
        property: subscription.property,
        notificationDeliveryMode: .normal,
        destinationInformation: OcaNetworkAddress()
      ))
    case .subscription2, .propertyChangeSubscription2:
      self
    }
  }
}
