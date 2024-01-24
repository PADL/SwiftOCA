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

protocol OCP1ControllerInternal: AES70ControllerDefaultSubscribing, AnyActor {
    nonisolated static var connectionPrefix: String { get }

    typealias ControllerMessage = (Ocp1Message, Bool)

    /// get an identifier used for logging
    nonisolated var identifier: String { get }

    /// a sequence of (message, isRrq) where isRrq indicates if a response is required
    var messages: AnyAsyncSequence<ControllerMessage> { get }

    /// last message sent time
    var lastMessageSentTime: ContinuousClock.Instant { get set }

    /// last message received time
    var lastMessageReceivedTime: ContinuousClock.Instant { get set }

    /// keep alive interval
    var heartbeatTime: Duration { get set }

    /// keep alive task
    var keepAliveTask: Task<(), Error>? { get set }

    func sendOcp1EncodedData(_ data: Data) async throws

    /// cleanup
    func onConnectionBecomingStale() async throws

    /// close the underlying connection (if any)
    func close() async throws
}

extension OCP1ControllerInternal {
    /// handle a single message
    func handle<Endpoint: AES70DeviceEndpointPrivate>(
        for endpoint: Endpoint,
        message: Ocp1Message,
        rrq: Bool
    ) async throws {
        let controller = self as! Endpoint.ControllerType
        var response: Ocp1Response?

        lastMessageReceivedTime = .now

        switch message {
        case let command as Ocp1Command:
            endpoint.logger.command(command, on: controller)
            let commandResponse = await endpoint.device.handleCommand(
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
            heartbeatTime = .seconds(keepAlive.heartBeatTime)
        case let keepAlive as Ocp1KeepAlive2:
            heartbeatTime = .milliseconds(keepAlive.heartBeatTime)
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
        } catch Ocp1Error.notConnected {
        } catch {
            endpoint.logger.error(error, controller: controller)
        }
        await endpoint.unlockAndRemove(controller: controller)
        try? await close()
        endpoint.logger.info("controller removed", controller: controller)
    }

    /// returns `true` if insufficient keepalives were received to keep connection fresh
    private func connectionIsStale(_ now: ContinuousClock.Instant) -> Bool {
        lastMessageReceivedTime + (heartbeatTime * 3) < now
    }

    /// returns `true` if we haven't sent any message for `keepAliveThreshold`
    private func connectionNeedsKeepAlive(_ now: ContinuousClock.Instant) -> Bool {
        lastMessageSentTime + heartbeatTime < now
    }

    private func sendKeepAlive() async throws {
        try await sendMessage(
            Ocp1KeepAlive.keepAlive(interval: heartbeatTime),
            type: .ocaKeepAlive
        )
    }

    /// AES70-3 notes that both controller and device send `KeepAlive` messages if they haven't
    /// yet received (or sent) another message during `HeartbeatTime`.
    func heartbeatTimeDidChange(from oldValue: Duration) {
        if heartbeatTime != .zero, heartbeatTime != oldValue || keepAliveTask == nil {
            // if we have a keepalive interval and it has changed, or we haven't yet started
            // the keepalive task, (re)start it
            keepAliveTask = Task<(), Error> {
                repeat {
                    let now = ContinuousClock.now
                    if connectionIsStale(now) {
                        try? await onConnectionBecomingStale()
                        break
                    }
                    if connectionNeedsKeepAlive(now) {
                        try await sendKeepAlive()
                    }
                    try await Task.sleep(for: heartbeatTime)
                } while !Task.isCancelled
            }
        } else if heartbeatTime == .zero, let keepAliveTask {
            // otherwise if the new interval is zero, cancel the task (if any)
            keepAliveTask.cancel()
            self.keepAliveTask = nil
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
        try await sendMessages([message], type: messageType)
    }

    func sendMessages(
        _ messages: [Ocp1Message],
        type messageType: OcaMessageType
    ) async throws {
        lastMessageSentTime = .now

        try await sendOcp1EncodedData(AES70OCP1Connection.encodeOcp1MessagePdu(
            messages,
            type: messageType
        ))
    }
}

extension AES70Device {
    #if canImport(IORing)
    typealias GetChunk = @Sendable (Int) async throws -> [UInt8]
    #else
    typealias GetChunk = (Int) async throws -> [UInt8]
    #endif

    static func receiveMessages(_ getChunk: GetChunk) async throws
        -> [OCP1ControllerInternal.ControllerMessage]
    {
        var messagePduData = try await getChunk(AES70OCP1Connection.MinimumPduSize)

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
        messagePduData += try await getChunk(bytesLeft)

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
}

extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) * 1e-18
    }
}

protocol OCP1ControllerInternalLightweightNotifyingInternal: AES70ControllerLightweightNotifying {
    func sendOcp1EncodedData(
        _ data: Data,
        to destinationAddress: OcaNetworkAddress
    ) async throws
}

extension OCP1ControllerInternalLightweightNotifyingInternal {
    func sendMessage(
        _ message: Ocp1Message,
        type messageType: OcaMessageType,
        to destinationAddress: OcaNetworkAddress
    ) async throws {
        try await sendOcp1EncodedData(AES70OCP1Connection.encodeOcp1MessagePdu(
            [message],
            type: messageType
        ), to: destinationAddress)
    }
}
