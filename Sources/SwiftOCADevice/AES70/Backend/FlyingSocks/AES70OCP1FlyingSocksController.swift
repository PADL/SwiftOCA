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

#if os(macOS) || os(iOS)

import AsyncAlgorithms
import AsyncExtensions
@_implementationOnly
import FlyingSocks
import Foundation
import SwiftOCA

/// A remote endpoint
actor AES70OCP1FlyingSocksController: AES70ControllerPrivate {
    typealias ControllerMessage = (Ocp1Message, Bool)

    var subscriptions = [OcaONo: NSMutableSet]()

    private let hostname: String
    private let socket: AsyncSocket
    private let logger: Logging?
    private let _messages: AsyncThrowingStream<AsyncSyncSequence<[ControllerMessage]>, Error>
    private var keepAliveTask: Task<(), Error>?
    private var lastMessageReceivedTime = Date.distantPast
    private var socketClosed = false

    var messages: AnyAsyncSequence<ControllerMessage> {
        _messages.joined().eraseToAnyAsyncSequence()
    }

    init(socket: AsyncSocket, logger: Logging?) async throws {
        hostname = Self.makeIdentifier(from: socket.socket)
        self.socket = socket
        self.logger = logger
        _messages = AsyncThrowingStream.decodingMessages(from: socket.bytes)
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
                            try self.closeSocket()
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
        let messagePduData = try await AES70OCP1Connection.encodeOcp1MessagePdu(
            messages,
            type: messageType
        )
        try await socket.write(messagePduData)
    }

    private func sendKeepAlive() async throws {
        let keepAlive = Ocp1KeepAlive1(heartBeatTime: OcaUint16(keepAliveInterval / NSEC_PER_SEC))
        try await sendMessage(keepAlive, type: .ocaKeepAlive)
    }

    private func closeSocket() throws {
        guard !socketClosed else { return }
        try socket.close()
        socketClosed = true
    }

    func close() async throws {
        try closeSocket()

        keepAliveTask?.cancel()
        keepAliveTask = nil

        await AES70Device.shared.unlockAll(controller: self)
    }

    nonisolated var identifier: String {
        "<\(hostname)>"
    }

    func updateLastMessageReceivedTime() {
        lastMessageReceivedTime = Date()
    }

    private nonisolated var fileDescriptor: Socket.FileDescriptor {
        socket.socket.file
    }
}

extension AES70OCP1FlyingSocksController: Equatable {
    public nonisolated static func == (
        lhs: AES70OCP1FlyingSocksController,
        rhs: AES70OCP1FlyingSocksController
    ) -> Bool {
        lhs.fileDescriptor == rhs.fileDescriptor
    }
}

extension AES70OCP1FlyingSocksController: Hashable {
    public nonisolated func hash(into hasher: inout Hasher) {
        fileDescriptor.hash(into: &hasher)
    }
}

private extension AES70OCP1FlyingSocksController {
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

private func decodeOcp1Messages<S>(from bytes: S) async throws -> ([Ocp1Message], Bool)
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

private extension AsyncThrowingStream
    where Element == AsyncSyncSequence<[AES70OCP1FlyingSocksController.ControllerMessage]>,
    Failure == Error
{
    static func decodingMessages<S: AsyncChunkedSequence>(from bytes: S) -> Self
        where S.Element == UInt8
    {
        AsyncThrowingStream<
            AsyncSyncSequence<[AES70OCP1FlyingSocksController.ControllerMessage]>,
            Error
        > {
            do {
                let (messages, rrq) = try await decodeOcp1Messages(from: bytes)
                return messages.map { ($0, rrq) }.async
            } catch Ocp1Error.pduTooShort {
                return nil
            } catch {
                throw error
            }
        }
    }
}

#endif
