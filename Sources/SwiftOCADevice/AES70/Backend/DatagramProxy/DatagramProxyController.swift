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

import AsyncExtensions
import Foundation
import SwiftOCA

actor DatagramProxyController<T: DatagramProxyPeerIdentifier>: AES70OCP1ControllerPrivate,
    CustomStringConvertible
{
    nonisolated static var connectionPrefix: String { "oca/udp" }

    let peerID: T
    var subscriptions = [OcaONo: NSMutableSet]()
    var keepAliveTask: Task<(), Error>?
    var lastMessageReceivedTime = ContinuousClock.now
    var lastMessageSentTime = ContinuousClock.now

    private weak var endpoint: DatagramProxyDeviceEndpoint<T>?

    var messages: AnyAsyncSequence<ControllerMessage> {
        AsyncEmptySequence<ControllerMessage>().eraseToAnyAsyncSequence()
    }

    init(with peerID: T, endpoint: DatagramProxyDeviceEndpoint<T>) {
        self.peerID = peerID
        self.endpoint = endpoint
    }

    var heartbeatTime = Duration.seconds(1) {
        didSet {
            heartbeatTimeDidChange(from: oldValue)
        }
    }

    func sendMessages(
        _ messages: [Ocp1Message],
        type messageType: OcaMessageType
    ) async throws {
        let messagePduData = try AES70OCP1Connection.encodeOcp1MessagePdu(
            messages,
            type: messageType
        )
        endpoint?.outputStream.yield((peerID, [UInt8](messagePduData)))
    }

    nonisolated var identifier: String {
        String(describing: peerID)
    }

    public nonisolated var description: String {
        "\(type(of: self))(peerID: \(String(describing: peerID))"
    }

    func onConnectionBecomingStale() async throws {}

    func close() async throws {}
}
