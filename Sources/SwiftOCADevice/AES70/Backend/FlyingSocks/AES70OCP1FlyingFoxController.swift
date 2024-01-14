//
// Copyright (c) 2024 PADL Software Pty Ltd
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

import AsyncExtensions
@_implementationOnly
import FlyingFox
@_implementationOnly
import FlyingSocks
import Foundation
import SwiftOCA

fileprivate extension AsyncStream where Element == WSMessage {
    var ocp1DecodedMessages: AnyAsyncSequence<AES70ControllerPrivate.ControllerMessage> {
        flatMap {
            // TODO: handle OCP.1 PDUs split over multiple frames
            guard case let .data(data) = $0 else {
                throw Ocp1Error.invalidMessageType
            }

            var messagePdus = [Data]()
            let messageType = try AES70OCP1Connection.decodeOcp1MessagePdu(
                from: data,
                messages: &messagePdus
            )
            let messages = try messagePdus.map {
                try AES70OCP1Connection.decodeOcp1Message(from: $0, type: messageType)
            }

            return messages.map { ($0, messageType == .ocaCmdRrq) }.async
        }.eraseToAnyAsyncSequence()
    }
}

/// A remote WebSocket endpoint
actor AES70OCP1FlyingFoxController: AES70ControllerPrivate, CustomStringConvertible {
    nonisolated static var connectionPrefix: String { "ocaws/tcp" }

    var subscriptions = [OcaONo: NSMutableSet]()

    private let inputStream: AsyncStream<WSMessage>
    private let outputStream: AsyncStream<WSMessage>.Continuation
    private var endpoint: AES70OCP1FlyingFoxDeviceEndpoint?

    var keepAliveTask: Task<(), Error>?
    var lastMessageReceivedTime = Date.distantPast

    var messages: AsyncExtensions.AnyAsyncSequence<ControllerMessage> {
        inputStream.ocp1DecodedMessages.eraseToAnyAsyncSequence()
    }

    init(
        inputStream: AsyncStream<WSMessage>,
        outputStream: AsyncStream<WSMessage>.Continuation,
        endpoint: AES70OCP1FlyingFoxDeviceEndpoint?
    ) {
        self.inputStream = inputStream
        self.outputStream = outputStream
        self.endpoint = endpoint
    }

    var keepAliveInterval: UInt64 = 0 {
        didSet {
            if keepAliveInterval != oldValue {
                keepAliveIntervalDidChange()
            }
        }
    }

    func onConnectionBecomingStale() async {
        await close()
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
        outputStream.yield(.data(messagePduData))
    }

    func close() async {
        outputStream.finish()

        keepAliveTask?.cancel()
        keepAliveTask = nil
    }

    nonisolated var identifier: String {
        String(describing: id)
    }

    public nonisolated var description: String {
        "\(type(of: self))(id: \(id))"
    }
}

#endif
