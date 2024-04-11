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

import AsyncExtensions
import Foundation
import SwiftOCA

actor OcaLocalController: Ocp1ControllerInternal {
    nonisolated static var connectionPrefix: String { OcaLocalConnectionPrefix }

    var lastMessageReceivedTime = ContinuousClock.now
    var lastMessageSentTime = ContinuousClock.now
    var heartbeatTime = Duration.seconds(0)
    var keepAliveTask: Task<(), Error>?

    weak var endpoint: OcaLocalDeviceEndpoint?
    var subscriptions = [OcaONo: NSMutableSet]()

    init(endpoint: OcaLocalDeviceEndpoint) async {
        self.endpoint = endpoint
    }

    var messages: AnyAsyncSequence<ControllerMessage> {
        endpoint!.requestChannel.flatMap { data in
            var messagePdus = [Data]()

            let messageType = try Ocp1Connection.decodeOcp1MessagePdu(
                from: data,
                messages: &messagePdus
            )

            return try messagePdus.map { messagePdu in
                let message = try Ocp1Connection.decodeOcp1Message(
                    from: messagePdu,
                    type: messageType
                )

                return (message, messageType == .ocaCmdRrq)
            }.async
        }.eraseToAnyAsyncSequence()
    }

    func sendOcp1EncodedData(_ data: Data) async throws {
        await endpoint?.responseChannel.send(data)
    }

    nonisolated var identifier: String {
        "local"
    }

    func close() throws {}

    func onConnectionBecomingStale() async throws {}
}
