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

public enum OcaSubscriptionManagerState: OcaUint8, Codable {
    case normal = 1
    case eventsDisabled = 2
}

open class OcaSubscriptionManager: OcaManager {
    override public class var classID: OcaClassID { OcaClassID("1.3.4") }
    override public class var classVersion: OcaClassVersionNumber { 3 }

    public static let NotificationsDisabledEventID = OcaEventID(defLevel: 3, eventIndex: 1)
    public static let SynchronizeStateEventID = OcaEventID(defLevel: 3, eventIndex: 2)

    @OcaProperty(propertyID: OcaPropertyID("3.1"))
    public var state: OcaProperty<OcaSubscriptionManagerState>.State

    convenience init() {
        self.init(objectNumber: OcaSubscriptionManagerONo)
    }

    public typealias AddSubscriptionParameters = OcaSubscription

    public struct RemoveSubscriptionParameters: Codable {
        public let event: OcaEvent
        public let subscriber: OcaMethod

        public init(event: OcaEvent, subscriber: OcaMethod) {
            self.event = event
            self.subscriber = subscriber
        }
    }

    public typealias AddPropertyChangeSubscriptionParameters = OcaPropertyChangeSubscription

    public struct RemovePropertyChangeSubscriptionParameters: Codable {
        public let emitter: OcaONo
        public let property: OcaPropertyID
        public let subscriber: OcaMethod

        public init(emitter: OcaONo, property: OcaPropertyID, subscriber: OcaMethod) {
            self.emitter = emitter
            self.property = property
            self.subscriber = subscriber
        }
    }

    func addSubscription(
        event: OcaEvent,
        subscriber: OcaMethod,
        subscriberContext: OcaBlob,
        notificationDeliveryMode: OcaNotificationDeliveryMode,
        destinationInformation: OcaNetworkAddress
    ) async throws {
        let params = AddSubscriptionParameters(
            event: event,
            subscriber: subscriber,
            subscriberContext: subscriberContext,
            notificationDeliveryMode: notificationDeliveryMode,
            destinationInformation: destinationInformation
        )
        try await sendCommandRrq(methodID: OcaMethodID("3.1"), parameters: params)
    }

    func removeSubscription(event: OcaEvent, subscriber: OcaMethod) async throws {
        let params = RemoveSubscriptionParameters(event: event, subscriber: subscriber)
        try await sendCommandRrq(methodID: OcaMethodID("3.2"), parameters: params)
    }

    func disableNotifications() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.3"))
    }

    func reenableNotifications() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.4"))
    }

    func addPropertyChangeSubscription(
        emitter: OcaONo,
        property: OcaPropertyID,
        subscriber: OcaMethod,
        subscriberContext: OcaBlob,
        notificationDeliveryMode: OcaNotificationDeliveryMode,
        destinationInformation: OcaNetworkAddress
    ) async throws {
        let params = AddPropertyChangeSubscriptionParameters(
            emitter: emitter,
            property: property,
            subscriber: subscriber,
            subscriberContext: subscriberContext,
            notificationDeliveryMode: notificationDeliveryMode,
            destinationInformation: destinationInformation
        )
        try await sendCommandRrq(methodID: OcaMethodID("3.5"), parameters: params)
    }

    func removePropertyChangeSubscription(
        emitter: OcaONo,
        property: OcaPropertyID,
        subscriber: OcaMethod
    ) async throws {
        let params = RemovePropertyChangeSubscriptionParameters(
            emitter: emitter,
            property: property,
            subscriber: subscriber
        )
        try await sendCommandRrq(methodID: OcaMethodID("3.6"), parameters: params)
    }

    func getMaximumSubscriberContextLength() async throws -> OcaUint16 {
        try await sendCommandRrq(methodID: OcaMethodID("3.7"))
    }

    public typealias AddSubscription2Parameters = OcaSubscription2
    public typealias RemoveSubscription2Parameters = OcaSubscription2
    public typealias AddPropertyChangeSubscription2Parameters = OcaPropertyChangeSubscription2
    public typealias RemovePropertyChangeSubscription2Parameters = OcaPropertyChangeSubscription2

    func addSubscription2(
        event: OcaEvent,
        notificationDeliveryMode: OcaNotificationDeliveryMode,
        destinationInformation: OcaNetworkAddress
    ) async throws {
        let params = AddSubscription2Parameters(
            event: event,
            notificationDeliveryMode: notificationDeliveryMode,
            destinationInformation: destinationInformation
        )
        try await sendCommandRrq(methodID: OcaMethodID("3.8"), parameters: params)
    }

    func removeSubscription2(
        event: OcaEvent,
        notificationDeliveryMode: OcaNotificationDeliveryMode,
        destinationInformation: OcaNetworkAddress
    ) async throws {
        let params = RemoveSubscription2Parameters(
            event: event,
            notificationDeliveryMode: notificationDeliveryMode,
            destinationInformation: destinationInformation
        )
        try await sendCommandRrq(methodID: OcaMethodID("3.9"), parameters: params)
    }

    func addPropertyChangeSubscription2(
        emitter: OcaONo,
        property: OcaPropertyID,
        notificationDeliveryMode: OcaNotificationDeliveryMode,
        destinationInformation: OcaNetworkAddress
    ) async throws {
        let params = AddPropertyChangeSubscription2Parameters(
            emitter: emitter,
            property: property,
            notificationDeliveryMode: notificationDeliveryMode,
            destinationInformation: destinationInformation
        )
        try await sendCommandRrq(methodID: OcaMethodID("3.10"), parameters: params)
    }

    func removePropertyChangeSubscription2(
        emitter: OcaONo,
        property: OcaPropertyID,
        notificationDeliveryMode: OcaNotificationDeliveryMode,
        destinationInformation: OcaNetworkAddress
    ) async throws {
        let params = RemovePropertyChangeSubscription2Parameters(
            emitter: emitter,
            property: property,
            notificationDeliveryMode: notificationDeliveryMode,
            destinationInformation: destinationInformation
        )
        try await sendCommandRrq(methodID: OcaMethodID("3.11"), parameters: params)
    }
}
