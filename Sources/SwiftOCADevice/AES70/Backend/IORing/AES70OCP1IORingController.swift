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

import AsyncExtensions
import Foundation
@_implementationOnly
import IORing
@_implementationOnly
import IORingUtils
import SwiftOCA

/// A remote endpoint
actor AES70OCP1IORingController: AES70ControllerPrivate {
    static let MaximumPduSize = 1500 // FIXME: check this

    typealias ControllerMessage = (Ocp1Message, Bool)

    var subscriptions = [OcaONo: NSMutableSet]()

    private let peerAddress: any SocketAddress
    private let socket: Socket
    private let _messages: AnyAsyncSequence<Message>

    private var keepAliveTask: Task<(), Error>?
    private var lastMessageReceivedTime = Date.distantPast

    private func decodeOcp1Messages(from messagePduData: [UInt8]) throws -> ([Ocp1Message], Bool) {
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
        return (messages, messageType == .ocaCmdRrq)
    }

    var messages: AnyAsyncSequence<ControllerMessage> {
        _messages.map { message in
            do {
                let (messages, rrq) = try await self.decodeOcp1Messages(from: message.buffer)
                return messages.map { ($0, rrq) }.async
            } catch Ocp1Error.pduTooShort {
                return [].async
            } catch {
                throw error
            }
        }.joined().eraseToAnyAsyncSequence()
    }

    init(socket: Socket) async throws {
        peerAddress = try socket.peerAddress
        self.socket = socket
        _messages = try await socket.recvmsg(count: Self.MaximumPduSize)
    }

    var connectionIsStale: Bool {
        lastMessageReceivedTime + 3 * TimeInterval(keepAliveInterval) /
            TimeInterval(NSEC_PER_SEC) < Date()
    }

    var keepAliveInterval: UInt64 = 0 {
        didSet {
            if keepAliveInterval != 0 {
                keepAliveTask = Task<(), Error> {
                    repeat {
                        if connectionIsStale {
                            Task { try await self.closeSocket() }
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

    func setKeepAliveInterval(_ keepAliveInterval: UInt64) {
        self.keepAliveInterval = keepAliveInterval
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
        let message = try Message(address: peerAddress, buffer: [UInt8](messagePduData))
        try await socket.sendmsg(message)
    }

    private func sendKeepAlive() async throws {
        let keepAlive = Ocp1KeepAlive1(heartBeatTime: OcaUint16(keepAliveInterval / NSEC_PER_SEC))
        try await sendMessage(keepAlive, type: .ocaKeepAlive)
    }

    private func closeSocket() async throws {
        guard !socket.isClosed else { return }
        try await socket.close()
    }

    func close() async throws {
        try await closeSocket()

        keepAliveTask?.cancel()
        keepAliveTask = nil

        await AES70Device.shared.unlockAll(controller: self)
    }

    nonisolated var identifier: String {
        "<\((try? socket.peerName) ?? "unknown")>"
    }

    func updateLastMessageReceivedTime() {
        lastMessageReceivedTime = Date()
    }
}

extension AES70OCP1IORingController: Equatable {
    public nonisolated static func == (
        lhs: AES70OCP1IORingController,
        rhs: AES70OCP1IORingController
    ) -> Bool {
        lhs.socket == rhs.socket
    }
}

extension AES70OCP1IORingController: Hashable {
    public nonisolated func hash(into hasher: inout Hasher) {
        socket.hash(into: &hasher)
    }
}

#endif
