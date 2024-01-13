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

import AsyncAlgorithms
import AsyncExtensions
import Foundation
import Logging
import SwiftOCA

/// AES70ControllerPrivate should eventually be merged into AES70Controller once we are ready to
/// support out-of-tree endpoints

protocol AES70ControllerPrivate: AES70ControllerDefaultSubscribing, AnyActor {
    nonisolated static var connectionPrefix: String { get }

    typealias ControllerMessage = (Ocp1Message, Bool)

    /// get an identifier used for logging
    nonisolated var identifier: String { get }

    /// a sequence of (message, isRrq) where isRrq indicates if a response is required
    var messages: AnyAsyncSequence<ControllerMessage> { get }

    /// last message received time
    var lastMessageReceivedTime: Date { get set }

    /// keep alive interval
    var keepAliveInterval: UInt64 { get set }

    /// keep alive task
    var keepAliveTask: Task<(), Error>? { get set }

    /// encode and send a set of messages
    func sendMessages(
        _ messages: AnyAsyncSequence<Ocp1Message>,
        type messageType: OcaMessageType
    ) async throws

    /// cleanup
    func onConnectionBecomingStale() async throws

    /// close the underlying connection (if any)
    func close() async throws
}

extension AES70ControllerPrivate {
    /// handle a singlam essage
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
            endpoint.logger.info("received unknown message \(message)")
            throw Ocp1Error.invalidMessageType
        }

        if rrq, let response {
            try await sendMessage(response, type: .ocaRsp)
        }
        if let response {
            endpoint.logger.response(response, on: controller)
        }
    }

    /// handle messages until an error
    func handle<Endpoint: AES70DeviceEndpointPrivate>(for endpoint: Endpoint) async {
        let controller = self as! Endpoint.ControllerType

        endpoint.logger.info("controller added", controller: controller)
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
            endpoint.logger.error(error, controller: controller)
        }
        await endpoint.unlockAndRemove(controller: controller)
        try? await close()
        endpoint.logger.info("controller removed", controller: controller)
    }

    /// returns `true` if insufficient keepalives were received to keep connection fresh
    private var connectionIsStale: Bool {
        lastMessageReceivedTime + 3 * TimeInterval(keepAliveInterval) /
            TimeInterval(NSEC_PER_SEC) < Date()
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

    func sendMessage(
        _ message: Ocp1Message,
        type messageType: OcaMessageType
    ) async throws {
        let sequence: AsyncSyncSequence<[Ocp1Message]> = [message].async
        try await sendMessages(sequence.eraseToAnyAsyncSequence(), type: messageType)
    }
}
