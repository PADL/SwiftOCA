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
    var peerAddress: AnySocketAddress { get }
    var keepAliveInterval: UInt64 { get set }
    var keepAliveTask: Task<(), Error>? { get set }
    var lastMessageReceivedTime: Date { get set }

    func sendMessages(
        _ messages: AnyAsyncSequence<Ocp1Message>,
        type messageType: OcaMessageType
    ) async throws
}

actor AES70OCP1IORingStreamController: AES70OCP1IORingControllerPrivate, CustomStringConvertible {
    static var connectionPrefix: String { "oca/udp" }

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

    public nonisolated var description: String {
        "\(type(of: self))(socket: \(socket))"
    }

    func receiveMessagePdus() async throws -> [ControllerMessage] {
        var messagePduData = try await socket.read(
            count: AES70OCP1Connection.MinimumPduSize,
            awaitingAllRead: true
        )

        guard messagePduData.count != 0 else {
            // 0 length on EOF
            throw Ocp1Error.notConnected
        }

        guard messagePduData.count >= AES70OCP1Connection.MinimumPduSize,
              messagePduData[0] == Ocp1SyncValue
        else {
            throw Ocp1Error.invalidSyncValue
        }

        let pduSize: OcaUint32 = Data(messagePduData).decodeInteger(index: 3)
        guard pduSize >= (AES70OCP1Connection.MinimumPduSize - 1) else {
            throw Ocp1Error.invalidPduSize
        }

        let bytesLeft = Int(pduSize) - (AES70OCP1Connection.MinimumPduSize - 1)
        messagePduData += try await socket.read(count: bytesLeft, awaitingAllRead: true)

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

    init(socket: Socket) async throws {
        self.socket = socket
        peerAddress = try AnySocketAddress(self.socket.peerAddress)

        receiveMessageTask = Task { [self] in
            do {
                repeat {
                    try await receiveMessagePdus().asyncForEach {
                        await _messages.send($0)
                    }
                    if Task.isCancelled { break }
                } while true
            } catch {
                _messages.fail(error)
            }
        }
    }

    func close() async throws {
        // don't close the socket, it will be closed when last reference is released

        keepAliveTask?.cancel()
        keepAliveTask = nil

        receiveMessageTask?.cancel()
        receiveMessageTask = nil
    }

    func onConnectionBecomingStale() async throws {
        try await close()
    }

    var keepAliveInterval: UInt64 = 0 {
        didSet {
            if keepAliveInterval != oldValue {
                keepAliveIntervalDidChange()
            }
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
        _ = try await socket.write(
            Array(messagePduData),
            count: messagePduData.count,
            awaitingAllWritten: true
        )
    }

    nonisolated var identifier: String {
        (try? socket.peerName) ?? "unknown"
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
    static var connectionPrefix: String { "oca/udp" }

    var subscriptions = [OcaONo: NSMutableSet]()
    let peerAddress: AnySocketAddress
    var keepAliveTask: Task<(), Error>?
    var lastMessageReceivedTime = Date.distantPast

    private weak var endpoint: AES70OCP1IORingDatagramDeviceEndpoint?

    var messages: AnyAsyncSequence<ControllerMessage> {
        AsyncEmptySequence<ControllerMessage>().eraseToAnyAsyncSequence()
    }

    init(
        endpoint: AES70OCP1IORingDatagramDeviceEndpoint,
        peerAddress: any SocketAddress
    ) async throws {
        self.endpoint = endpoint
        self.peerAddress = AnySocketAddress(peerAddress)
    }

    func onConnectionBecomingStale() async throws {
        await endpoint?.unlockAndRemove(controller: self)
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

    nonisolated var identifier: String {
        (try? peerAddress.presentationAddress) ?? "unknown"
    }

    func close() async throws {}
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

// https://www.swiftbysundell.com/articles/async-and-concurrent-forEach-and-map/
extension Sequence {
    func asyncForEach(
        _ operation: @Sendable (Element) async throws -> ()
    ) async rethrows {
        for element in self {
            try await operation(element)
        }
    }
}

#endif
