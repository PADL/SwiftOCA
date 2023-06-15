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
import BinaryCoder

public enum OcaSubscriptionManagerState: OcaUint8, Codable {
    case normal = 1
    case eventsDisabled = 2
}

public class OcaSubscriptionManager: OcaManager {
    public override class var classID: OcaClassID { OcaClassID("1.3.4") }
    
    // 3.1
    // TODO: this is not gettable/settable only modified by events
    var state: OcaSubscriptionManagerState = .normal
    
    convenience init() {
        self.init(objectNumber: OcaSubscriptionManagerONo)
    }
    
    // 3.1
    func addSubscription(event: OcaEvent,
                         subscriber: OcaMethod,
                         subscriberContext: OcaBlob,
                         notificationDeliveryMode: OcaNotificationDeliveryMode,
                         destinationInformation: OcaNetworkAddress) async throws {
        struct AddSubscriptionParameters: Codable {
            let event: OcaEvent
            let subscriber: OcaMethod
            let subscriberContext: OcaBlob
            let notificationDeliveryMode: OcaNotificationDeliveryMode
            let destinationInformation: OcaNetworkAddress
        }
        
        let params = AddSubscriptionParameters(event: event,
                                               subscriber: subscriber,
                                               subscriberContext: subscriberContext,
                                               notificationDeliveryMode: notificationDeliveryMode,
                                               destinationInformation: destinationInformation)
        try await sendCommandRrq(methodID: OcaMethodID("3.1"), parameters: params)
    }
    
    // 3.2
    func removeSubscription(event: OcaEvent, subscriber: OcaMethod) async throws  {
        struct RemoveSubscriptionParameters: Codable {
            let event: OcaEvent
            let subscriber: OcaMethod
        }
        
        let params = RemoveSubscriptionParameters(event: event,
                                                  subscriber: subscriber)
        try await sendCommandRrq(methodID: OcaMethodID("3.2"), parameters: params)
    }
    
    // 3.3
    func disableNotifications() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.3"))
    }
    
    // 3.4
    func renableNotifications() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.4"))
    }
    
    // 3.5
    func addPropertyChangeSubscription(emitter: OcaONo,
                                       property: OcaPropertyID,
                                       subscriber: OcaMethod,
                                       subscriberContext: OcaBlob,
                                       notificationDeliveryMode: OcaNotificationDeliveryMode,
                                       destinationInformation: OcaNetworkAddress) async throws {
        struct AddPropertyChangeSubscriptionParameters: Codable {
            let emitter: OcaONo
            let property: OcaPropertyID
            let subscriber: OcaMethod
            let subscriberContext: OcaBlob
            let notificationDeliveryMode: OcaNotificationDeliveryMode
            let destinationInformation: OcaNetworkAddress
        }
        
        let params = AddPropertyChangeSubscriptionParameters(emitter: emitter,
                                                             property: property,
                                                             subscriber: subscriber,
                                                             subscriberContext: subscriberContext,
                                                             notificationDeliveryMode: notificationDeliveryMode,
                                                             destinationInformation: destinationInformation)
        try await sendCommandRrq(methodID: OcaMethodID("3.5"), parameters: params)
    }
    
    // 3.6
    func removePropertyChangeSubscription(emitter: OcaONo,
                                          property: OcaPropertyID,
                                          subscriber: OcaMethod) async throws {
        struct RemovePropertyChangeSubscriptionParameters: Codable {
            let emitter: OcaONo
            let property: OcaPropertyID
            let subscriber: OcaMethod
        }
        
        let params = RemovePropertyChangeSubscriptionParameters(emitter: emitter,
                                                                property: property,
                                                                subscriber: subscriber)
        try await sendCommandRrq(methodID: OcaMethodID("3.6"), parameters: params)
    }
    
    // 3.7
    func getMaximumSubscriberContextLength(max: inout OcaUint16) async throws {
        try await sendCommandRrq(methodID: OcaMethodID("3.6"),
                                 responseParameterCount: 1,
                                 responseParameters: &max)
    }
}
