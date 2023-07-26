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

public enum OcaNotificationDeliveryMode: OcaUint8, Codable, Sendable {
    case reliable = 1
    case fast = 2
}

public struct OcaEventID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let defLevel: OcaUint16
    public let eventIndex: OcaUint16

    init(_ string: OcaString) {
        let s = string.split(separator: ".", maxSplits: 1).map { OcaUint16($0)! }
        defLevel = s[0]
        eventIndex = s[1]
    }

    public init(defLevel: OcaUint16, eventIndex: OcaUint16) {
        self.defLevel = defLevel
        self.eventIndex = eventIndex
    }

    public var description: String {
        "\(defLevel).\(eventIndex)"
    }
}

public struct OcaEvent: Codable, Hashable, Equatable, Sendable {
    public let emitterONo: OcaONo
    public let eventID: OcaEventID

    public init(emitterONo: OcaONo, eventID: OcaEventID) {
        self.emitterONo = emitterONo
        self.eventID = eventID
    }
}

public enum OcaPropertyChangeType: OcaUint8, Codable, Equatable {
    case currentChanged = 1
    case minChanged = 2
    case maxChanged = 3
    case itemAdded = 4
    case itemChanged = 5
    case itemDeleted = 6
}

public struct OcaPropertyChangedEventData<T: Codable>: Codable {
    public let propertyID: OcaPropertyID
    public let propertyValue: T
    public let changeType: OcaPropertyChangeType

    public init(
        propertyID: OcaPropertyID,
        propertyValue: T,
        changeType: OcaPropertyChangeType
    ) {
        self.propertyID = propertyID
        self.propertyValue = propertyValue
        self.changeType = changeType
    }
}

public let OcaPropertyChangedEventID = OcaEventID(defLevel: 1, eventIndex: 1)

public struct OcaSubscription: Codable, Equatable, Hashable {
    public let event: OcaEvent
    public let subscriber: OcaMethod
    public let subscriberContext: OcaBlob
    public let notificationDeliveryMode: OcaNotificationDeliveryMode
    public let destinationInformation: OcaNetworkAddress

    public init(
        event: OcaEvent,
        subscriber: OcaMethod,
        subscriberContext: OcaBlob,
        notificationDeliveryMode: OcaNotificationDeliveryMode,
        destinationInformation: OcaNetworkAddress
    ) {
        self.event = event
        self.subscriber = subscriber
        self.subscriberContext = subscriberContext
        self.notificationDeliveryMode = notificationDeliveryMode
        self.destinationInformation = destinationInformation
    }
}
