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

public enum OcaSubscriptionManagerState: OcaUint8, Codable, Sendable, CaseIterable {
  case normal = 1
  case eventsDisabled = 2
}

open class OcaSubscriptionManager: OcaManager, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.3.4") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  public static let NotificationsDisabledEventID = OcaEventID(defLevel: 3, eventIndex: 1)
  public static let SynchronizeStateEventID = OcaEventID(defLevel: 3, eventIndex: 2)

  @OcaProperty(propertyID: OcaPropertyID("3.1"))
  public var state: OcaProperty<OcaSubscriptionManagerState>.PropertyValue

  convenience init() {
    self.init(objectNumber: OcaSubscriptionManagerONo)
  }

  public typealias AddSubscriptionParameters = OcaSubscription

  public struct RemoveSubscriptionParameters: OcaParametersReflectable {
    public let event: OcaEvent
    public let subscriber: OcaMethod

    public init(event: OcaEvent, subscriber: OcaMethod) {
      self.event = event
      self.subscriber = subscriber
    }
  }

  public typealias AddPropertyChangeSubscriptionParameters = OcaPropertyChangeSubscription

  public struct RemovePropertyChangeSubscriptionParameters: OcaParametersReflectable {
    public let emitter: OcaONo
    public let property: OcaPropertyID
    public let subscriber: OcaMethod

    public init(emitter: OcaONo, property: OcaPropertyID, subscriber: OcaMethod) {
      self.emitter = emitter
      self.property = property
      self.subscriber = subscriber
    }
  }

  public static let addSubscription = OcaMethodDescriptor<AddSubscriptionParameters, Void>(
    "3.1",
    name: "AddSubscription"
  )

  func addSubscription(
    event: OcaEvent,
    subscriber: OcaMethod,
    subscriberContext: OcaBlob,
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress
  ) async throws {
    try await invoke(Self.addSubscription, .init(
      event: event,
      subscriber: subscriber,
      subscriberContext: subscriberContext,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    ))
  }

  public static let removeSubscription = OcaMethodDescriptor<RemoveSubscriptionParameters, Void>(
    "3.2",
    name: "RemoveSubscription"
  )

  func removeSubscription(event: OcaEvent, subscriber: OcaMethod) async throws {
    try await invoke(Self.removeSubscription, .init(event: event, subscriber: subscriber))
  }

  public static let disableNotifications =
    OcaMethodDescriptor<Void, Void>("3.3", name: "DisableNotifications")

  func disableNotifications() async throws {
    try await invoke(Self.disableNotifications)
  }

  public static let reenableNotifications =
    OcaMethodDescriptor<Void, Void>("3.4", name: "ReEnableNotifications")

  func reenableNotifications() async throws {
    try await invoke(Self.reenableNotifications)
  }

  public static let addPropertyChangeSubscription =
    OcaMethodDescriptor<AddPropertyChangeSubscriptionParameters, Void>(
      "3.5",
      name: "AddPropertyChangeSubscription"
    )

  func addPropertyChangeSubscription(
    emitter: OcaONo,
    property: OcaPropertyID,
    subscriber: OcaMethod,
    subscriberContext: OcaBlob,
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress
  ) async throws {
    try await invoke(Self.addPropertyChangeSubscription, .init(
      emitter: emitter,
      property: property,
      subscriber: subscriber,
      subscriberContext: subscriberContext,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    ))
  }

  public static let removePropertyChangeSubscription =
    OcaMethodDescriptor<RemovePropertyChangeSubscriptionParameters, Void>(
      "3.6",
      name: "RemovePropertyChangeSubscription"
    )

  func removePropertyChangeSubscription(
    emitter: OcaONo,
    property: OcaPropertyID,
    subscriber: OcaMethod
  ) async throws {
    try await invoke(Self.removePropertyChangeSubscription, .init(
      emitter: emitter,
      property: property,
      subscriber: subscriber
    ))
  }

  public static let getMaximumSubscriberContextLength = OcaMethodDescriptor<Void, OcaUint16>(
    "3.7",
    name: "GetMaximumSubscriberContextLength",
    resultNames: ["Max"]
  )

  func getMaximumSubscriberContextLength() async throws -> OcaUint16 {
    try await invoke(Self.getMaximumSubscriberContextLength)
  }

  public typealias AddSubscription2Parameters = OcaSubscription2
  public typealias RemoveSubscription2Parameters = OcaSubscription2
  public typealias AddPropertyChangeSubscription2Parameters = OcaPropertyChangeSubscription2
  public typealias RemovePropertyChangeSubscription2Parameters = OcaPropertyChangeSubscription2

  public static let addSubscription2 = OcaMethodDescriptor<AddSubscription2Parameters, Void>(
    "3.8",
    name: "AddSubscription2"
  )

  func addSubscription2(
    event: OcaEvent,
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress
  ) async throws {
    try await invoke(Self.addSubscription2, .init(
      event: event,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    ))
  }

  public static let removeSubscription2 = OcaMethodDescriptor<RemoveSubscription2Parameters, Void>(
    "3.9",
    name: "RemoveSubscription2"
  )

  func removeSubscription2(
    event: OcaEvent,
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress
  ) async throws {
    try await invoke(Self.removeSubscription2, .init(
      event: event,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    ))
  }

  public static let addPropertyChangeSubscription2 =
    OcaMethodDescriptor<AddPropertyChangeSubscription2Parameters, Void>(
      "3.10",
      name: "AddPropertyChangeSubscription2"
    )

  func addPropertyChangeSubscription2(
    emitter: OcaONo,
    property: OcaPropertyID,
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress
  ) async throws {
    try await invoke(Self.addPropertyChangeSubscription2, .init(
      emitter: emitter,
      property: property,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    ))
  }

  public static let removePropertyChangeSubscription2 =
    OcaMethodDescriptor<RemovePropertyChangeSubscription2Parameters, Void>(
      "3.11",
      name: "RemovePropertyChangeSubscription2"
    )

  func removePropertyChangeSubscription2(
    emitter: OcaONo,
    property: OcaPropertyID,
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress
  ) async throws {
    try await invoke(Self.removePropertyChangeSubscription2, .init(
      emitter: emitter,
      property: property,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    ))
  }

  public typealias AddSubscription2ListParameters = OcaSubscription2List
  public typealias RemoveSubscription2ListParameters = OcaSubscription2List
  public typealias AddPropertyChangeSubscription2ListParameters = OcaPropertyChangeSubscription2List
  public typealias RemovePropertyChangeSubscription2ListParameters =
    OcaPropertyChangeSubscription2List

  public static let addSubscription2List =
    OcaMethodDescriptor<AddSubscription2ListParameters, [OcaStatus]>(
      "3.12",
      name: "AddSubscription2List",
      resultNames: ["Statuses"]
    )

  func addSubscription2List(
    events: [OcaEvent],
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress
  ) async throws -> [OcaStatus] {
    try await invoke(Self.addSubscription2List, .init(
      events: events,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    ))
  }

  public static let removeSubscription2List =
    OcaMethodDescriptor<RemoveSubscription2ListParameters, Void>(
      "3.13",
      name: "RemoveSubscription2List"
    )

  func removeSubscription2List(
    events: [OcaEvent],
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress
  ) async throws {
    try await invoke(Self.removeSubscription2List, .init(
      events: events,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    ))
  }

  public static let addPropertyChangeSubscription2List =
    OcaMethodDescriptor<AddPropertyChangeSubscription2ListParameters, [OcaStatus]>(
      "3.14",
      name: "AddPropertyChangeSubscription2List",
      resultNames: ["Statuses"]
    )

  func addPropertyChangeSubscription2List(
    emitters: [OcaONo],
    properties: [OcaPropertyID],
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress
  ) async throws -> [OcaStatus] {
    try await invoke(Self.addPropertyChangeSubscription2List, .init(
      emitters: emitters,
      properties: properties,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    ))
  }

  public static let removePropertyChangeSubscription2List =
    OcaMethodDescriptor<RemovePropertyChangeSubscription2ListParameters, Void>(
      "3.15",
      name: "RemovePropertyChangeSubscription2List"
    )

  func removePropertyChangeSubscription2List(
    emitters: [OcaONo],
    properties: [OcaPropertyID],
    notificationDeliveryMode: OcaNotificationDeliveryMode,
    destinationInformation: OcaNetworkAddress
  ) async throws {
    try await invoke(Self.removePropertyChangeSubscription2List, .init(
      emitters: emitters,
      properties: properties,
      notificationDeliveryMode: notificationDeliveryMode,
      destinationInformation: destinationInformation
    ))
  }
}
