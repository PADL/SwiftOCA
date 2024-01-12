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
import Foundation
import Logging
import SwiftOCA

#if os(macOS) || os(iOS)
typealias AES70OCP1Controller = AES70OCP1FlyingSocksController
public typealias AES70OCP1DeviceEndpoint = AES70OCP1FlyingSocksDeviceEndpoint
public typealias AES70OCP1WSDeviceEndpoint = AES70OCP1FlyingFoxDeviceEndpoint
#elseif os(Linux)
typealias AES70OCP1Controller = AES70OCP1IORingStreamController
public typealias AES70OCP1DeviceEndpoint = AES70OCP1IORingStreamDeviceEndpoint
#endif

public protocol AES70Controller: Actor {
    func addSubscription(
        _ subscription: OcaSubscriptionManagerSubscription
    ) async throws

    func removeSubscription(
        _ subscription: OcaSubscriptionManagerSubscription
    ) async throws

    func removeSubscription(
        _ event: OcaEvent,
        property: OcaPropertyID?,
        subscriber: OcaMethod
    ) async throws

    func sendMessage(
        _ message: Ocp1Message,
        type messageType: OcaMessageType
    ) async throws
}

public protocol AES70ControllerDefaultSubscribing: AES70Controller {
    var subscriptions: [OcaONo: NSMutableSet] { get set }
}

protocol AES70ControllerPrivate: AES70ControllerDefaultSubscribing, AnyActor {
    typealias ControllerMessage = (Ocp1Message, Bool)

    nonisolated var identifier: String { get }
    var messages: AnyAsyncSequence<ControllerMessage> { get }
    var lastMessageReceivedTime: Date { get set }
    var keepAliveInterval: UInt64 { get set }
    var keepAliveTask: Task<(), Error>? { get set }

    func sendMessages(
        _ messages: AnyAsyncSequence<Ocp1Message>,
        type messageType: OcaMessageType
    ) async throws

    func onConnectionBecomingStale() async throws
    func close() async throws
}

extension AES70ControllerPrivate {
    func handle<Endpoint: AES70DeviceEndpointPrivate>(
        for endpoint: Endpoint,
        message: Ocp1Message,
        rrq: Bool
    ) async throws {
        let controller = self as! Endpoint.ControllerType
        var response: Ocp1Response?

        lastMessageReceivedTime = Date()

        switch message {
        case let command as Ocp1Command:
            endpoint.logger.command(command, on: controller)
            let commandResponse = await AES70Device.shared.handleCommand(
                command,
                timeout: endpoint.timeout,
                from: controller
            )
            response = Ocp1Response(
                handle: command.handle,
                statusCode: commandResponse.statusCode,
                parameters: commandResponse.parameters
            )
        case let keepAlive as Ocp1KeepAlive1:
            keepAliveInterval = UInt64(keepAlive.heartBeatTime) * NSEC_PER_SEC
        case let keepAlive as Ocp1KeepAlive2:
            keepAliveInterval = UInt64(keepAlive.heartBeatTime) * NSEC_PER_MSEC
        default:
            throw Ocp1Error.invalidMessageType
        }

        if rrq, let response {
            try await sendMessage(response, type: .ocaRsp)
        }
        if let response {
            endpoint.logger.response(response, on: controller)
        }
    }

    func handle<Endpoint: AES70DeviceEndpointPrivate>(for endpoint: Endpoint) async {
        let controller = self as! Endpoint.ControllerType

        endpoint.logger.controllerAdded(controller)
        await endpoint.add(controller: controller)
        do {
            for try await (message, rrq) in messages {
                try await handle(
                    for: endpoint,
                    message: message,
                    rrq: rrq
                )
            }
        } catch {
            endpoint.logger.controllerError(error, on: controller)
        }
        await endpoint.remove(controller: controller)
        try? await close()
        endpoint.logger.controllerRemoved(controller)
    }

    var connectionIsStale: Bool {
        lastMessageReceivedTime + 3 * TimeInterval(keepAliveInterval) /
            TimeInterval(NSEC_PER_SEC) < Date()
    }

    func sendKeepAlive() async throws {
        let keepAlive = Ocp1KeepAlive1(heartBeatTime: OcaUint16(keepAliveInterval / NSEC_PER_SEC))
        try await sendMessage(keepAlive, type: .ocaKeepAlive)
    }

    func keepAliveIntervalDidChange() {
        if keepAliveInterval != 0 {
            keepAliveTask = Task<(), Error> {
                repeat {
                    if connectionIsStale {
                        try? await onConnectionBecomingStale()
                        break
                    }
                    try await sendKeepAlive()
                    try await Task.sleep(nanoseconds: keepAliveInterval)
                } while !Task.isCancelled
            }
        } else {
            keepAliveTask?.cancel()
            keepAliveTask = nil
        }
    }

    func decodeMessages(from messagePduData: [UInt8]) throws -> [ControllerMessage] {
        guard messagePduData.count >= AES70OCP1Connection.MinimumPduSize,
              messagePduData[0] == Ocp1SyncValue
        else {
            throw Ocp1Error.invalidSyncValue
        }
        let pduSize: OcaUint32 = Data(messagePduData).decodeInteger(index: 3)
        guard pduSize >= (AES70OCP1Connection.MinimumPduSize - 1) else {
            throw Ocp1Error.invalidPduSize
        }

        var messagePdus = [Data]()
        let messageType = try AES70OCP1Connection.decodeOcp1MessagePdu(
            from: Data(messagePduData),
            messages: &messagePdus
        )
        let messages = try messagePdus.map {
            try AES70OCP1Connection.decodeOcp1Message(from: $0, type: messageType)
        }

        return messages.map { ($0, messageType == .ocaCmdRrq) }
    }
}

public extension AES70ControllerDefaultSubscribing {
    /// subscriptions are stored keyed by the emitter object number (the object that emits the
    /// event)
    /// each object has a set of subscriptions, note that EV1 and EV2 subscriptions are independent,
    /// i.e. a controller could subscribe to some events with EV1 and others with EV2 (although this
    /// would certainly be unusual). Hence when looking for a matching subscription, we compare the
    /// event ID, the property (in the case it is a property changed event), the subscriber, and the
    /// version.
    private func findSubscriptions(
        _ event: OcaEvent,
        property: OcaPropertyID? = nil,
        subscriber: OcaMethod? = nil,
        version: OcaSubscriptionManagerSubscription.EventVersion
    ) -> [OcaSubscriptionManagerSubscription] {
        precondition(property == nil || event.eventID == OcaPropertyChangedEventID)
        guard let subscriptions = subscriptions[event.emitterONo] else {
            return []
        }
        return subscriptions.filter {
            let subscription = $0 as! OcaSubscriptionManagerSubscription
            return subscription.event == event &&
                (subscriber == nil ? true : subscription.subscriber == subscriber) &&
                subscription.property == property &&
                subscription.version == version
        } as! [OcaSubscriptionManagerSubscription]
    }

    private func hasSubscription(
        _ event: OcaEvent,
        property: OcaPropertyID? = nil,
        subscriber: OcaMethod? = nil,
        version: OcaSubscriptionManagerSubscription.EventVersion
    ) -> Bool {
        findSubscriptions(
            event,
            property: property,
            subscriber: subscriber,
            version: version
        ).count > 0
    }

    private func hasSubscription(
        _ subscription: OcaSubscriptionManagerSubscription
    ) -> Bool {
        hasSubscription(
            subscription.event,
            subscriber: subscription.subscriber,
            version: subscription.version
        )
    }

    func addSubscription(
        _ subscription: OcaSubscriptionManagerSubscription
    ) async throws {
        guard !hasSubscription(subscription) else {
            throw Ocp1Error.alreadySubscribedToEvent
        }
        guard subscription.notificationDeliveryMode == .reliable else {
            // we don't support "fast" UDP deliveries yet
            throw Ocp1Error.status(.notImplemented)
        }
        var subscriptions = subscriptions[subscription.event.emitterONo]
        if subscriptions == nil {
            subscriptions = NSMutableSet(object: subscription)
            self.subscriptions[subscription.event.emitterONo] = subscriptions
        } else {
            subscriptions?.add(subscription)
        }
    }

    func removeSubscription(
        _ subscription: OcaSubscriptionManagerSubscription
    ) async throws {
        subscriptions[subscription.event.emitterONo]?.remove(subscription)
    }

    func removeSubscription(
        _ event: OcaEvent,
        property: OcaPropertyID?,
        subscriber: OcaMethod
    ) async throws {
        for subscription in findSubscriptions(event, subscriber: subscriber, version: .ev1) {
            subscriptions[event.emitterONo]?.remove(subscription)
        }
    }

    func notifySubscribers(
        _ event: OcaEvent,
        parameters: Data
    ) async throws {
        guard let subscriptions = subscriptions[event.emitterONo] else {
            return
        }

        let property: OcaPropertyID?

        if event.eventID == OcaPropertyChangedEventID {
            property = try Ocp1BinaryDecoder().decode(OcaPropertyID.self, from: parameters)
        } else {
            property = nil
        }

        for subscription in subscriptions {
            let subscription = subscription as! OcaSubscriptionManagerSubscription

            guard subscription.property == nil || property == subscription.property else {
                return
            }

            switch subscription.version {
            case .ev1:
                let eventData = Ocp1EventData(
                    event: subscription.event,
                    eventParameters: parameters
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

                try await sendMessage(notification, type: .ocaNtf1)
            case .ev2:
                let notification = Ocp1Notification2(
                    event: subscription.event,
                    notificationType: .event,
                    data: parameters
                )
                try await sendMessage(notification, type: .ocaNtf2)
            }
        }
    }
}

extension AES70ControllerPrivate {
    func sendMessage(
        _ message: Ocp1Message,
        type messageType: OcaMessageType
    ) async throws {
        let sequence: AsyncSyncSequence<[Ocp1Message]> = [message].async
        try await sendMessages(sequence.eraseToAnyAsyncSequence(), type: messageType)
    }
}

extension Logger {
    func controllerAdded(_ controller: AES70ControllerPrivate) {
        info("\(controller.identifier) controller added")
    }

    func controllerRemoved(_ controller: AES70ControllerPrivate) {
        info("\(controller.identifier) controller removed")
    }

    func command(_ command: Ocp1Command, on controller: AES70ControllerPrivate) {
        trace("\(controller.identifier) command: \(command)")
    }

    func response(_ response: Ocp1Response, on controller: AES70ControllerPrivate) {
        trace("\(controller.identifier) command: \(response)")
    }

    func controllerError(_ error: Error, on controller: AES70ControllerPrivate) {
        warning("\(controller.identifier) error: \(error.localizedDescription)")
    }
}
