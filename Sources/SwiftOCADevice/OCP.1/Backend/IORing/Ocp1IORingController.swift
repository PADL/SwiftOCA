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

protocol Ocp1IORingControllerPrivate: Ocp1ControllerInternal,
    Ocp1ControllerInternalLightweightNotifyingInternal, Actor,
    Equatable, Hashable
{
    var peerAddress: AnySocketAddress { get }

    func sendOcp1EncodedMessage(_ message: Message) async throws
}

extension Ocp1IORingControllerPrivate {
    func sendOcp1EncodedData(
        _ data: Data,
        to destinationAddress: OcaNetworkAddress
    ) async throws {
        let networkAddress = try Ocp1NetworkAddress(networkAddress: destinationAddress)
        let peerAddress: SocketAddress
        if networkAddress.address.isEmpty {
            // empty string means send to controller address but via UDP
            peerAddress = self.peerAddress
        } else {
            peerAddress = try sockaddr_storage(
                family: networkAddress.family,
                presentationAddress: networkAddress.presentationAddress
            )
        }
        try await sendOcp1EncodedMessage(Message(address: peerAddress, buffer: [UInt8](data)))
    }
}

actor Ocp1IORingStreamController: Ocp1IORingControllerPrivate, CustomStringConvertible {
    nonisolated var connectionPrefix: String { OcaTcpConnectionPrefix }

    var subscriptions = [OcaONo: NSMutableSet]()
    let peerAddress: AnySocketAddress
    var receiveMessageTask: Task<(), Never>?
    var keepAliveTask: Task<(), Error>?
    var lastMessageReceivedTime = ContinuousClock.now
    var lastMessageSentTime = ContinuousClock.now
    weak var endpoint: Ocp1IORingStreamDeviceEndpoint?

    var messages: AnyAsyncSequence<ControllerMessage> {
        _messages.eraseToAnyAsyncSequence()
    }

    private var _messages = AsyncThrowingChannel<ControllerMessage, Error>()
    private let socket: Socket
    let notificationSocket: Socket

    public nonisolated var description: String {
        "\(type(of: self))(socket: \(socket))"
    }

    init(
        endpoint: Ocp1IORingStreamDeviceEndpoint,
        socket: Socket,
        notificationSocket: Socket
    ) async throws {
        self.socket = socket
        self.notificationSocket = notificationSocket
        self.endpoint = endpoint

        peerAddress = try AnySocketAddress(self.socket.peerAddress)

        receiveMessageTask = Task { [self] in
            do {
                repeat {
                    try await OcaDevice
                        .receiveMessages { try await socket.read(count: $0, awaitingAllRead: true) }
                        .asyncForEach {
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

    var heartbeatTime = Duration.seconds(1) {
        didSet {
            heartbeatTimeDidChange(from: oldValue)
        }
    }

    func sendOcp1EncodedData(_ data: Data) async throws {
        _ = try await socket.write(
            [UInt8](data),
            count: data.count,
            awaitingAllWritten: true
        )
    }

    func sendOcp1EncodedMessage(_ messagePdu: Message) async throws {
        try await notificationSocket.sendMessage(messagePdu)
    }

    nonisolated var identifier: String {
        (try? socket.peerName) ?? "unknown"
    }
}

private extension Ocp1NetworkAddress {
    var presentationAddress: String {
        get throws {
            switch family {
            case sa_family_t(AF_INET):
                return "\(address):\(port)"
            case sa_family_t(AF_INET6):
                return "[\(address)]:\(port)"
            case sa_family_t(AF_LOCAL):
                return address
            default:
                throw Ocp1Error.status(.parameterError)
            }
        }
    }

    var family: sa_family_t {
        if address.hasPrefix("[") && address.contains("]") {
            return sa_family_t(AF_INET6)
        } else if address.contains("/") {
            // presuming we have an absolute path to distinguish from IPv4 address
            return sa_family_t(AF_LOCAL)
        } else {
            return sa_family_t(AF_INET)
        }
    }
}

extension Ocp1IORingStreamController: Equatable {
    public nonisolated static func == (
        lhs: Ocp1IORingStreamController,
        rhs: Ocp1IORingStreamController
    ) -> Bool {
        lhs.socket == rhs.socket
    }
}

extension Ocp1IORingStreamController: Hashable {
    public nonisolated func hash(into hasher: inout Hasher) {
        socket.hash(into: &hasher)
    }
}

actor Ocp1IORingDatagramController: Ocp1IORingControllerPrivate, Ocp1ControllerDatagramSemantics {
    nonisolated var connectionPrefix: String { OcaUdpConnectionPrefix }

    var subscriptions = [OcaONo: NSMutableSet]()
    let peerAddress: AnySocketAddress
    var keepAliveTask: Task<(), Error>?
    var lastMessageReceivedTime = ContinuousClock.now
    var lastMessageSentTime = ContinuousClock.now

    private(set) var isOpen: Bool = false
    weak var endpoint: Ocp1IORingDatagramDeviceEndpoint?

    var messages: AnyAsyncSequence<ControllerMessage> {
        AsyncEmptySequence<ControllerMessage>().eraseToAnyAsyncSequence()
    }

    init(
        endpoint: Ocp1IORingDatagramDeviceEndpoint,
        peerAddress: any SocketAddress
    ) async throws {
        self.endpoint = endpoint
        self.peerAddress = AnySocketAddress(peerAddress)
    }

    func onConnectionBecomingStale() async throws {
        await endpoint?.unlockAndRemove(controller: self)
    }

    var heartbeatTime = Duration.seconds(0) {
        didSet {
            heartbeatTimeDidChange(from: oldValue)
        }
    }

    func sendOcp1EncodedData(_ data: Data) async throws {
        try await sendOcp1EncodedMessage(Message(address: peerAddress, buffer: [UInt8](data)))
    }

    func sendOcp1EncodedMessage(_ messagePdu: Message) async throws {
        try await endpoint?.sendOcp1EncodedMessage(messagePdu)
    }

    nonisolated var identifier: String {
        (try? peerAddress.presentationAddress) ?? "unknown"
    }

    func close() async throws {}

    func didOpen() {
        isOpen = true
    }
}

extension Ocp1IORingDatagramController: Equatable {
    public nonisolated static func == (
        lhs: Ocp1IORingDatagramController,
        rhs: Ocp1IORingDatagramController
    ) -> Bool {
        lhs.peerAddress == rhs.peerAddress
    }
}

extension Ocp1IORingDatagramController: Hashable {
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
