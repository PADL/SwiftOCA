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
actor AES70OCP1FlyingSocksController: AES70ControllerPrivate, CustomStringConvertible {
    nonisolated static var connectionPrefix: String { "oca/tcp" }

    var subscriptions = [OcaONo: NSMutableSet]()
    var keepAliveTask: Task<(), Error>?
    var lastMessageReceivedTime = ContinuousClock.now

    private let address: String
    private let socket: AsyncSocket
    private let _messages: AsyncThrowingStream<AsyncSyncSequence<[ControllerMessage]>, Error>
    private var socketClosed = false

    var messages: AnyAsyncSequence<ControllerMessage> {
        _messages.joined().eraseToAnyAsyncSequence()
    }

    init(socket: AsyncSocket) async throws {
        address = Self.makeIdentifier(from: socket.socket)
        self.socket = socket
        _messages = AsyncThrowingStream.decodingMessages(from: socket.bytes)
    }

    var keepAliveInterval = Duration.seconds(0) {
        didSet {
            keepAliveIntervalDidChange(from: oldValue)
        }
    }

    func onConnectionBecomingStale() async throws {
        try closeSocket()
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
        try await socket.write(messagePduData)
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
    }

    nonisolated var identifier: String {
        address
    }

    public nonisolated var description: String {
        "\(type(of: self))(address: \(address))"
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
        case let .ip4(address, port):
            return "\(address):\(port)"
        case let .ip6(address, port):
            return "\(address):\(port)"
        case let .unix(path):
            return path
        }
    }
}

private extension AsyncThrowingStream
    where Element == AsyncSyncSequence<[AES70ControllerPrivate.ControllerMessage]>,
    Failure == Error
{
    static func decodingMessages<S: AsyncChunkedSequence>(from bytes: S) -> Self
        where S.Element == UInt8
    {
        AsyncThrowingStream<
            AsyncSyncSequence<[AES70ControllerPrivate.ControllerMessage]>,
            Error
        > {
            do {
                var iterator = bytes.makeAsyncIterator()
                return try await AES70Device.receiveMessages { count in
                    try await iterator.nextChunk(count: count) ?? []
                }.async
            } catch Ocp1Error.pduTooShort {
                return nil
            } catch {
                throw error
            }
        }
    }
}

#endif
