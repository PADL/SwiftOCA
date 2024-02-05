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

public enum OcaNotificationDeliveryMode: OcaUint8, Codable, Sendable {
    case normal = 1
    case lightweight = 2
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

public enum OcaPropertyChangeType: OcaUint8, Codable, Equatable, Sendable {
    case currentChanged = 1
    case minChanged = 2
    case maxChanged = 3
    case itemAdded = 4
    case itemChanged = 5
    case itemDeleted = 6
}

public struct OcaPropertyChangedEventData<T: Codable & Sendable>: Codable, Sendable {
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

public struct OcaMediaConnectorStatusChangedEventData: Codable, Sendable {
    public let connectorStatus: OcaMediaConnectorStatus

    public init(connectorStatus: OcaMediaConnectorStatus) {
        self.connectorStatus = connectorStatus
    }
}

public struct OcaTaskStateChangedEventData: Codable, Sendable {
    public let taskID: OcaTaskID
    public let programID: OcaLibVolIdentifier
    public let status: OcaTaskStatus

    public init(taskID: OcaTaskID, programID: OcaLibVolIdentifier, status: OcaTaskStatus) {
        self.taskID = taskID
        self.programID = programID
        self.status = status
    }
}

public typealias OcaMediaConnectorElement = OcaBitSet16

public struct OcaMediaSourceConnectorChangedEventData: Codable, Sendable {
    public let sourceConnector: OcaMediaSourceConnector
    public let changeType: OcaPropertyChangeType
    public let changedElement: OcaMediaConnectorElement

    public init(
        sourceConnector: OcaMediaSourceConnector,
        changeType: OcaPropertyChangeType,
        changedElement: OcaMediaConnectorElement
    ) {
        self.sourceConnector = sourceConnector
        self.changeType = changeType
        self.changedElement = changedElement
    }
}

public struct OcaMediaSinkConnectorChangedEventData: Codable, Sendable {
    public let sinkConnector: OcaMediaSinkConnector
    public let changeType: OcaPropertyChangeType
    public let changedElement: OcaMediaConnectorElement

    public init(
        sinkConnector: OcaMediaSinkConnector,
        changeType: OcaPropertyChangeType,
        changedElement: OcaMediaConnectorElement
    ) {
        self.sinkConnector = sinkConnector
        self.changeType = changeType
        self.changedElement = changedElement
    }
}

public struct OcaObjectListEventData: Codable, Sendable {
    public let objectList: OcaList<OcaONo>

    public init(objectList: OcaList<OcaONo>) {
        self.objectList = objectList
    }
}

public struct OcaObservationEventData: Codable, Sendable {
    public let reading: OcaFloat64

    public init(reading: OcaFloat64) {
        self.reading = reading
    }
}

public struct OcaObservationListEventData: Codable, Sendable {
    public let reading: OcaList<OcaFloat64>

    public init(reading: OcaList<OcaFloat64>) {
        self.reading = reading
    }
}

public enum OcaGrouperStatusChangeType: OcaUint8, Codable, Equatable, Sendable {
    case citizenAdded = 1
    case citizenDeleted = 2
    case citizenConnectionLost = 3
    case citizenConnectionReEstablished = 4
    case citizenError = 5
    case enrollment = 6
    case unEnrollment = 7
}

public struct OcaGrouperStatusChangeEventData: Codable, Sendable {
    public let groupIndex: OcaUint16
    public let citizenIndex: OcaUint16
    public let changeType: OcaGrouperStatusChangeType

    public init(
        groupIndex: OcaUint16,
        citizenIndex: OcaUint16,
        changeType: OcaGrouperStatusChangeType
    ) {
        self.groupIndex = groupIndex
        self.citizenIndex = citizenIndex
        self.changeType = changeType
    }
}

public let OcaGrouperStatusChangeEventID = OcaEventID(defLevel: 3, eventIndex: 1)

public struct OcaSubscription: Ocp1ParametersReflectable, Codable, Equatable, Hashable, Sendable {
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

public struct OcaPropertyChangeSubscription: Ocp1ParametersReflectable, Codable, Equatable,
    Hashable,
    Sendable
{
    public let emitter: OcaONo
    public let property: OcaPropertyID
    public let subscriber: OcaMethod
    public let subscriberContext: OcaBlob
    public let notificationDeliveryMode: OcaNotificationDeliveryMode
    public let destinationInformation: OcaNetworkAddress

    public init(
        emitter: OcaONo,
        property: OcaPropertyID,
        subscriber: OcaMethod,
        subscriberContext: OcaBlob,
        notificationDeliveryMode: OcaNotificationDeliveryMode,
        destinationInformation: OcaNetworkAddress
    ) {
        self.emitter = emitter
        self.property = property
        self.subscriber = subscriber
        self.subscriberContext = subscriberContext
        self.notificationDeliveryMode = notificationDeliveryMode
        self.destinationInformation = destinationInformation
    }
}

public struct OcaSubscription2: Ocp1ParametersReflectable, Codable, Equatable, Hashable, Sendable {
    public let event: OcaEvent
    public let notificationDeliveryMode: OcaNotificationDeliveryMode
    public let destinationInformation: OcaNetworkAddress

    public init(
        event: OcaEvent,
        notificationDeliveryMode: OcaNotificationDeliveryMode,
        destinationInformation: OcaNetworkAddress
    ) {
        self.event = event
        self.notificationDeliveryMode = notificationDeliveryMode
        self.destinationInformation = destinationInformation
    }
}

public struct OcaPropertyChangeSubscription2: Ocp1ParametersReflectable, Codable, Equatable,
    Hashable, Sendable
{
    public let emitter: OcaONo
    public let property: OcaPropertyID
    public let notificationDeliveryMode: OcaNotificationDeliveryMode
    public let destinationInformation: OcaNetworkAddress

    public init(
        emitter: OcaONo,
        property: OcaPropertyID,
        notificationDeliveryMode: OcaNotificationDeliveryMode,
        destinationInformation: OcaNetworkAddress
    ) {
        self.emitter = emitter
        self.property = property
        self.notificationDeliveryMode = notificationDeliveryMode
        self.destinationInformation = destinationInformation
    }
}

public typealias OcaGroupExceptionEventData = OcaList<OcaGroupException>

public struct OcaGroupException: Codable, Sendable {
    public let oNo: OcaONo
    public let methodID: OcaMethodID
    public let status: OcaStatus

    public init(oNo: OcaONo, methodID: OcaMethodID, status: OcaStatus) {
        self.oNo = oNo
        self.methodID = methodID
        self.status = status
    }
}
