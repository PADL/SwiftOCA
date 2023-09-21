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

#if canImport(IORing)

import AsyncAlgorithms
import AsyncExtensions
import Foundation
@_implementationOnly
import IORing
@_implementationOnly
import IORingUtils
import SwiftOCA

protocol AES70OCP1IORingControllerPrivate: AES70ControllerPrivate, Actor, Equatable, Hashable {
    typealias ControllerMessage = (Ocp1Message, Bool)

    var peerAddress: AnySocketAddress { get }
    var keepAliveInterval: UInt64 { get set }
    var keepAliveTask: Task<(), Error>? { get set }
    var lastMessageReceivedTime: Date { get set }

    func removeFromDeviceEndpoint() async throws

    func sendMessages(
        _ messages: AnyAsyncSequence<Ocp1Message>,
        type messageType: OcaMessageType
    ) async throws
}

extension AES70OCP1IORingControllerPrivate {
    private var connectionIsStale: Bool {
        lastMessageReceivedTime + 3 * TimeInterval(keepAliveInterval) /
            TimeInterval(NSEC_PER_SEC) < Date()
    }

    func setKeepAliveInterval(_ keepAliveInterval: UInt64) {
        self.keepAliveInterval = keepAliveInterval
    }

    func updateLastMessageReceivedTime() {
        lastMessageReceivedTime = Date()
    }

    private func sendKeepAlive() async throws {
        let keepAlive = Ocp1KeepAlive1(heartBeatTime: OcaUint16(keepAliveInterval / NSEC_PER_SEC))
        try await sendMessage(keepAlive, type: .ocaKeepAlive)
    }

    func keepAliveIntervalDidChange() {
        if keepAliveInterval != 0 {
            keepAliveTask = Task<(), Error> {
                repeat {
                    if connectionIsStale {
                        Task {
                            try? await self.removeFromDeviceEndpoint()
                        }
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

actor AES70OCP1IORingStreamController: AES70OCP1IORingControllerPrivate {
    var subscriptions = [OcaONo: NSMutableSet]()
    let peerAddress: AnySocketAddress
    var receiveMessageTask: Task<(), Never>?
    var keepAliveTask: Task<(), Error>?
    var lastMessageReceivedTime = Date.distantPast

    var messages: AnyAsyncSequence<ControllerMessage> {
        _messages.eraseToAnyAsyncSequence()
    }

    private var _messages = AsyncThrowingChannel<ControllerMessage, Error>()
    private let socket: Socket

    private func receiveMessages(
        _ messages: inout [Data]
    ) async throws -> OcaMessageType {
        var messagePduData = try await socket.read(count: AES70OCP1Connection.MinimumPduSize)

        guard messagePduData[0] == Ocp1SyncValue else {
            throw Ocp1Error.invalidSyncValue
        }

        let pduSize: OcaUint32 = Data(messagePduData).decodeInteger(index: 3)
        guard pduSize >= (AES70OCP1Connection.MinimumPduSize - 1) else {
            throw Ocp1Error.invalidPduSize
        }

        let bytesLeft = Int(pduSize) - (AES70OCP1Connection.MinimumPduSize - 1)

        messagePduData += try await socket.read(count: bytesLeft)

        return try AES70OCP1Connection.decodeOcp1MessagePdu(
            from: Data(messagePduData),
            messages: &messages
        )
    }

    init(socket: Socket) async throws {
        peerAddress = try AnySocketAddress(socket.peerAddress)
        self.socket = socket

        receiveMessageTask = Task { [self] in
            do {
                repeat {
                    var messagePdus = [Data]()
                    let messageType = try await receiveMessages(&messagePdus)
                    for messagePdu in messagePdus {
                        let message = try AES70OCP1Connection.decodeOcp1Message(
                            from: messagePdu,
                            type: messageType
                        )
                        await _messages.send((message, messageType == .ocaCmdRrq))
                    }
                } while true
            } catch {
                _messages.fail(error)
            }
        }
    }

    deinit {
        receiveMessageTask?.cancel()
        receiveMessageTask = nil

        await AES70Device.shared.unlockAll(controller: self)
    }

    func close() async throws {
        if !socket.isClosed {
            try await socket.close()
        }

        keepAliveTask?.cancel()
        keepAliveTask = nil
    }

    func removeFromDeviceEndpoint() async throws {
        try await close()
    }

    var keepAliveInterval: UInt64 = 0 {
        didSet {
            keepAliveIntervalDidChange()
        }
    }

    func sendMessages(
        _ messages: AnyAsyncSequence<Ocp1Message>,
        type messageType: OcaMessageType
    ) async throws {
        let messages = try await messages.collect()
        let messagePduData = try AES70OCP1Connection.encodeOcp1MessagePdu(
            messages,
            type: messageType
        )
        try await socket.write(Array(messagePduData), count: messagePduData.count)
    }

    nonisolated var identifier: String {
        "<\((try? socket.peerName) ?? "unknown")>"
    }
}

extension AES70OCP1IORingStreamController: Equatable {
    public nonisolated static func == (
        lhs: AES70OCP1IORingStreamController,
        rhs: AES70OCP1IORingStreamController
    ) -> Bool {
        lhs.socket == rhs.socket
    }
}

extension AES70OCP1IORingStreamController: Hashable {
    public nonisolated func hash(into hasher: inout Hasher) {
        socket.hash(into: &hasher)
    }
}

actor AES70OCP1IORingDatagramController: AES70OCP1IORingControllerPrivate {
    var subscriptions = [OcaONo: NSMutableSet]()
    let peerAddress: AnySocketAddress
    var keepAliveTask: Task<(), Error>?
    var lastMessageReceivedTime = Date.distantPast

    private weak var endpoint: AES70OCP1IORingDatagramDeviceEndpoint?

    init(
        endpoint: AES70OCP1IORingDatagramDeviceEndpoint,
        peerAddress: any SocketAddress
    ) async throws {
        self.endpoint = endpoint
        self.peerAddress = AnySocketAddress(peerAddress)
    }

    deinit {
        await AES70Device.shared.unlockAll(controller: self)
    }

    func removeFromDeviceEndpoint() async throws {
        await endpoint?.remove(controller: self)
    }

    var keepAliveInterval: UInt64 = 0 {
        didSet {
            keepAliveIntervalDidChange()
        }
    }

    func sendMessages(
        _ messages: AnyAsyncSequence<Ocp1Message>,
        type messageType: OcaMessageType
    ) async throws {
        let messages = try await messages.collect()
        let messagePduData = try AES70OCP1Connection.encodeOcp1MessagePdu(
            messages,
            type: messageType
        )
        let messagePdu = try Message(address: peerAddress, buffer: Array(messagePduData))
        try await endpoint?.sendMessagePdu(messagePdu)
    }

    func receiveMessagePdu(_ messagePdu: Message) throws -> [ControllerMessage] {
        let messagePduData = messagePdu.buffer

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

    nonisolated var identifier: String {
        "<\((try? peerAddress.presentationAddress) ?? "unknown")>"
    }
}

extension AES70OCP1IORingDatagramController: Equatable {
    public nonisolated static func == (
        lhs: AES70OCP1IORingDatagramController,
        rhs: AES70OCP1IORingDatagramController
    ) -> Bool {
        lhs.peerAddress == rhs.peerAddress
    }
}

extension AES70OCP1IORingDatagramController: Hashable {
    public nonisolated func hash(into hasher: inout Hasher) {
        peerAddress.hash(into: &hasher)
    }
}

#endif
