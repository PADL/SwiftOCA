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
    var ocp1DecodedMessages: AnyAsyncSequence<(Ocp1Message, Bool)> {
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
actor AES70OCP1FlyingFoxController: AES70ControllerPrivate {
    var subscriptions = [OcaONo: NSMutableSet]()

    private let outputStream: AsyncStream<WSMessage>.Continuation
    private var endpoint: AES70OCP1FlyingFoxDeviceEndpoint?

    private var keepAliveTask: Task<(), Error>?
    private var lastMessageReceivedTime = Date.distantPast

    init(
        inputStream: AsyncStream<WSMessage>,
        outputStream: AsyncStream<WSMessage>.Continuation,
        endpoint: AES70OCP1FlyingFoxDeviceEndpoint?
    ) {
        self.outputStream = outputStream
        self.endpoint = endpoint

        Task { @AES70Device in
            await self.endpoint?.add(controller: self)
            do {
                for try await (message, rrq) in inputStream.ocp1DecodedMessages {
                    var response: Ocp1Response?

                    await self.updateLastMessageReceivedTime()

                    switch message {
                    case let command as Ocp1Command:
                        await self.endpoint?.logger.command(command, on: self)
                        let commandResponse = await AES70Device.shared.handleCommand(
                            command,
                            timeout: self.endpoint?.timeout ?? 0,
                            from: self
                        )
                        response = Ocp1Response(
                            handle: command.handle,
                            statusCode: commandResponse.statusCode,
                            parameters: commandResponse.parameters
                        )
                    case let keepAlive as Ocp1KeepAlive1:
                        await self
                            .setKeepAliveInterval(UInt64(keepAlive.heartBeatTime) * NSEC_PER_SEC)
                    case let keepAlive as Ocp1KeepAlive2:
                        await self
                            .setKeepAliveInterval(UInt64(keepAlive.heartBeatTime) * NSEC_PER_MSEC)
                    default:
                        throw Ocp1Error.invalidMessageType
                    }

                    if rrq, let response {
                        try await self.sendMessage(response, type: .ocaRsp)
                    }
                    if let response {
                        await self.endpoint?.logger.response(response, on: self)
                    }
                }
            } catch {
                await self.endpoint?.logger.controllerError(error, on: self)
            }
            await self.endpoint?.remove(controller: self)
            await self.close()
        }
    }

    private var connectionIsStale: Bool {
        lastMessageReceivedTime + 3 * TimeInterval(keepAliveInterval) /
            TimeInterval(NSEC_PER_SEC) < Date()
    }

    private var keepAliveInterval: UInt64 = 0 {
        didSet {
            if keepAliveInterval != 0, keepAliveInterval != oldValue {
                keepAliveTask = Task<(), Error> {
                    repeat {
                        if connectionIsStale {
                            await self.close()
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

    private func setKeepAliveInterval(_ keepAliveInterval: UInt64) {
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
        outputStream.yield(.data(messagePduData))
    }

    private func sendKeepAlive() async throws {
        let keepAlive = Ocp1KeepAlive1(heartBeatTime: OcaUint16(keepAliveInterval / NSEC_PER_SEC))
        try await sendMessage(keepAlive, type: .ocaKeepAlive)
    }

    private func close() async {
        outputStream.finish()

        keepAliveTask?.cancel()
        keepAliveTask = nil

        await AES70Device.shared.unlockAll(controller: self)
    }

    nonisolated var identifier: String {
        String(describing: id)
    }

    func updateLastMessageReceivedTime() {
        lastMessageReceivedTime = Date()
    }
}

#endif
