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
@_implementationOnly
import FlyingSocks
import Foundation
import SwiftOCA

/// A remote endpoint
public final class AES70OCP1Controller {
    typealias ControllerMessage = (Ocp1Message, Bool)

    let hostname: String
    private nonisolated let socket: AsyncSocket
    private nonisolated let logger: Logging?
    private let _messages: AsyncThrowingStream<AsyncSyncSequence<[ControllerMessage]>, Error>
    private var keepAliveTask: Task<(), Error>?
    private var subscriptions = [OcaONo: NSMutableSet]()
    var lastMessageReceivedTime = Date.distantPast
    var notificationsEnabled = true

    var messages: AnyAsyncSequence<ControllerMessage> {
        _messages.joined().eraseToAnyAsyncSequence()
    }

    init(socket: AsyncSocket, logger: Logging?) {
        hostname = Self.makeIdentifier(from: socket.socket)
        self.socket = socket
        self.logger = logger
        _messages = AsyncThrowingStream.decodingMessages(from: socket.bytes)
    }

    private func findSubscription(
        _ event: OcaEvent,
        subscriber: OcaMethod? = nil
    ) -> OcaSubscription? {
        guard let subscriptions = subscriptions[event.emitterONo] else {
            return nil
        }
        return subscriptions.first(where: {
            let subscription = $0 as! OcaSubscription
            return subscription.event == event &&
                subscriber == nil ? true : subscription.subscriber == subscriber
        }) as? OcaSubscription
    }

    func hasSubscription(_ subscription: OcaSubscription) -> Bool {
        findSubscription(
            subscription.event,
            subscriber: subscription.subscriber
        ) != nil
    }

    func addSubscription(
        _ subscription: OcaSubscription
    ) async throws {
        guard !hasSubscription(subscription) else {
            throw Ocp1Error.alreadySubscribedToEvent
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
        _ event: OcaEvent,
        subscriber: OcaMethod
    ) async throws {
        guard let subscription = findSubscription(event, subscriber: subscriber)
        else {
            return
        }

        subscriptions[event.emitterONo]?.remove(subscription)
    }

    func notifySubscribers(
        _ event: OcaEvent,
        parameters: Data
    ) async throws {
        guard let subscription = findSubscription(event) else {
            return
        }

        let eventData = Ocp1EventData(event: event, eventParameters: parameters)
        let ntfParams = Ocp1NtfParams(
            parameterCount: 2,
            context: subscription.subscriberContext,
            eventData: eventData
        )
        let notification = Ocp1Notification1(
            targetONo: subscription.event.emitterONo,
            methodID: subscription.subscriber.methodID,
            parameters: ntfParams
        )

        try await sendMessage(notification, type: .ocaNtf1)
    }

    var keepAliveInterval: UInt64 = 0 {
        didSet {
            if keepAliveInterval != 0 {
                keepAliveTask = Task<(), Error> {
                    repeat {
                        if lastMessageReceivedTime + 3 * Double(keepAliveInterval / NSEC_PER_SEC) <
                            Date()
                        {
                            try socket.close() // FIXME: is this thread-safe?
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
    }

    func sendMessages(
        _ messages: AnyAsyncSequence<Ocp1Message>,
        type messageType: OcaMessageType
    ) async throws {
        let messages = try await messages.collect()
        let messagePduData = try await AES70OCP1Connection.encodeOcp1MessagePdu(
            messages,
            type: messageType
        )
        try await socket.write(messagePduData)
    }

    func sendMessage(
        _ message: Ocp1Message,
        type messageType: OcaMessageType
    ) async throws {
        let sequence: AsyncSyncSequence<[Ocp1Message]> = [message].async
        try await sendMessages(sequence.eraseToAnyAsyncSequence(), type: messageType)
    }

    private func sendKeepAlive() async throws {
        let keepAlive = Ocp1KeepAlive1(heartBeatTime: OcaUint16(keepAliveInterval / NSEC_PER_SEC))
        try await sendMessage(keepAlive, type: .ocaKeepAlive)
    }

    func close(device: AES70OCP1Device) async throws {
        try socket.close()

        keepAliveTask?.cancel()
        keepAliveTask = nil

        await device.objects.values.forEach {
            try? $0.unlock(controller: self)
        }
    }

    nonisolated var identifier: String {
        "<\(hostname)>"
    }
}

extension AES70OCP1Controller: Equatable {
    public static func == (lhs: AES70OCP1Controller, rhs: AES70OCP1Controller) -> Bool {
        lhs.socket.socket.file == rhs.socket.socket.file
    }
}

extension AES70OCP1Controller: Hashable {
    public func hash(into hasher: inout Hasher) {
        socket.socket.file.hash(into: &hasher)
    }
}

extension AES70OCP1Controller {
    static func makeIdentifier(from socket: Socket) -> String {
        guard let peer = try? socket.remotePeer() else {
            return "unknown"
        }

        if case .unix = peer, let unixAddress = try? socket.sockname() {
            return makeIdentifier(from: unixAddress)
        } else {
            return makeIdentifier(from: peer)
        }
    }

    static func makeIdentifier(from peer: Socket.Address) -> String {
        switch peer {
        case .ip4(let address, port: _):
            return address
        case .ip6(let address, port: _):
            return address
        case let .unix(path):
            return path
        }
    }
}

extension AES70OCP1Controller {
    static func decodeOcp1Messages<S>(from bytes: S) async throws -> ([Ocp1Message], Bool)
        where S: AsyncChunkedSequence, S.Element == UInt8
    {
        var iterator = bytes.makeAsyncIterator()

        guard var messagePduData = try await iterator
            .nextChunk(count: AES70OCP1Connection.MinimumPduSize)
        else {
            throw Ocp1Error.pduTooShort
        }
        guard messagePduData[0] == Ocp1SyncValue else {
            throw Ocp1Error.invalidSyncValue
        }
        let pduSize: OcaUint32 = Data(messagePduData).decodeInteger(index: 3)
        guard await pduSize >= (AES70OCP1Connection.MinimumPduSize - 1) else {
            throw Ocp1Error.invalidPduSize
        }
        let bytesLeft = await Int(pduSize) - (AES70OCP1Connection.MinimumPduSize - 1)
        guard let remainder = try await iterator.nextChunk(count: bytesLeft) else {
            throw Ocp1Error.pduTooShort
        }
        messagePduData += remainder

        var messagePdus = [Data]()
        let messageType = try await AES70OCP1Connection.decodeOcp1MessagePdu(
            from: Data(messagePduData),
            messages: &messagePdus
        )
        let messages = try messagePdus.map {
            try AES70OCP1Connection.decodeOcp1Message(from: $0, type: messageType)
        }
        return (messages, messageType == .ocaCmdRrq)
    }
}

extension AsyncThrowingStream
    where Element == AsyncSyncSequence<[AES70OCP1Controller.ControllerMessage]>, Failure == Error
{
    static func decodingMessages<S: AsyncChunkedSequence>(from bytes: S) -> Self
        where S.Element == UInt8
    {
        AsyncThrowingStream<AsyncSyncSequence<[AES70OCP1Controller.ControllerMessage]>, Error> {
            do {
                let (messages, rrq) = try await AES70OCP1Controller.decodeOcp1Messages(from: bytes)
                return messages.map { ($0, rrq) }.async
            } catch Ocp1Error.pduTooShort {
                return nil
            } catch {
                throw error
            }
        }
    }
}
