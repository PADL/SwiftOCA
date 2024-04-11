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

/// A remote controller
actor Ocp1FlyingSocksController: Ocp1ControllerInternal, CustomStringConvertible {
    nonisolated var connectionPrefix: String { OcaTcpConnectionPrefix }

    var subscriptions = [OcaONo: NSMutableSet]()
    var keepAliveTask: Task<(), Error>?
    var lastMessageReceivedTime = ContinuousClock.now
    var lastMessageSentTime = ContinuousClock.now
    weak var endpoint: Ocp1FlyingSocksDeviceEndpoint?

    private let address: String
    private let socket: AsyncSocket
    private let _messages: AsyncThrowingStream<AsyncSyncSequence<[ControllerMessage]>, Error>
    private var socketClosed = false

    var messages: AnyAsyncSequence<ControllerMessage> {
        _messages.joined().eraseToAnyAsyncSequence()
    }

    init(endpoint: Ocp1FlyingSocksDeviceEndpoint, socket: AsyncSocket) async throws {
        address = Self.makeIdentifier(from: socket.socket)
        self.endpoint = endpoint
        self.socket = socket
        _messages = AsyncThrowingStream.decodingMessages(from: socket.bytes)
    }

    var heartbeatTime = Duration.seconds(0) {
        didSet {
            heartbeatTimeDidChange(from: oldValue)
        }
    }

    func onConnectionBecomingStale() async throws {
        try await close()
    }

    func sendOcp1EncodedData(_ data: Data) async throws {
        try await socket.write(data)
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

extension Ocp1FlyingSocksController: Equatable {
    public nonisolated static func == (
        lhs: Ocp1FlyingSocksController,
        rhs: Ocp1FlyingSocksController
    ) -> Bool {
        lhs.fileDescriptor == rhs.fileDescriptor
    }
}

extension Ocp1FlyingSocksController: Hashable {
    public nonisolated func hash(into hasher: inout Hasher) {
        fileDescriptor.hash(into: &hasher)
    }
}

private extension Ocp1FlyingSocksController {
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
    where Element == AsyncSyncSequence<[Ocp1ControllerInternal.ControllerMessage]>,
    Failure == Error
{
    static func decodingMessages<S: AsyncChunkedSequence>(from bytes: S) -> Self
        where S.Element == UInt8
    {
        AsyncThrowingStream<
            AsyncSyncSequence<[Ocp1ControllerInternal.ControllerMessage]>,
            Error
        > {
            do {
                var iterator = bytes.makeAsyncIterator()
                return try await OcaDevice.receiveMessages { count in
                    try await iterator.nextChunk(count: count) ?? []
                }.async
            } catch Ocp1Error.pduTooShort {
                return nil
            } catch SocketError.disconnected {
                throw Ocp1Error.notConnected
            } catch {
                throw error
            }
        }
    }
}

#endif
