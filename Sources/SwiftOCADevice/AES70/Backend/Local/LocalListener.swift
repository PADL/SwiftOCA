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

import AsyncAlgorithms
import AsyncExtensions
import Foundation
import SwiftOCA

@AES70Device
public final class AES70LocalListener: AES70Listener {
    public var controllers: [AES70Controller] {
        [controller]
    }

    /// channel for receiving requests from the in-process controller
    var requestChannel = AsyncChannel<Data>()
    /// channel for sending responses to the in-process controller
    var responseChannel = AsyncChannel<Data>()

    private var controller: AES70LocalController!
    private var task: Task<(), Error>!

    public init() async throws {
        controller = await AES70LocalController(listener: self)
        try await AES70Device.shared.add(listener: self)

        task = Task {
            for await messagePdu in self.requestChannel {
                try await handleMessagePdu(messagePdu)
            }
        }
    }

    deinit {
        if let task {
            task.cancel()
        }
    }

    func handleMessagePdu(_ data: Data) async throws {
        var messagePdus = [Data]()
        let messageType = try AES70OCP1Connection.decodeOcp1MessagePdu(
            from: data,
            messages: &messagePdus
        )

        for messagePdu in messagePdus {
            let message = try AES70OCP1Connection.decodeOcp1Message(
                from: messagePdu,
                type: messageType
            )

            guard let command = message as? Ocp1Command else {
                continue
            }
            let commandResponse = await AES70Device.shared.handleCommand(command, from: controller)
            let response = Ocp1Response(
                handle: command.handle,
                statusCode: commandResponse.statusCode,
                parameters: commandResponse.parameters
            )

            if messageType == .ocaCmdRrq {
                try await controller.sendMessage(response, type: .ocaRsp)
            }
        }
    }
}
