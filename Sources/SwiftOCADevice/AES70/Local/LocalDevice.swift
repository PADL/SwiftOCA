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

public actor AES70LocalDevice: AES70DevicePrivate {
    /// channel for receiving requests from the in-process controller
    var requestChannel = AsyncChannel<Data>()
    /// channel for sending responses to the in-process controller
    var responseChannel = AsyncChannel<Data>()

    public internal(set) var objects = [OcaONo: OcaRoot]()

    public var rootBlock: OcaBlock<OcaRoot>!
    public var subscriptionManager: OcaSubscriptionManager!
    public var deviceManager: OcaDeviceManager!

    private var nextObjectNumber: OcaONo = 4096
    private var controller: AES70LocalController!

    private var task: Task<(), Error>!

    public init() async throws {
        controller = await AES70LocalController(device: self)

        rootBlock = try await OcaBlock(
            objectNumber: OcaRootBlockONo,
            deviceDelegate: self,
            addToRootBlock: false
        )
        subscriptionManager = try await OcaSubscriptionManager(deviceDelegate: self)
        deviceManager = try await OcaDeviceManager(deviceDelegate: self)

        task = Task {
            for await messagePdu in self.requestChannel {
                try await handleMessagePdu(messagePdu)
            }
        }
    }

    public func notifySubscribers(_ event: OcaEvent, parameters: Data) async throws {
        try await controller.notifySubscribers2(
            event,
            parameters: parameters
        )
    }

    deinit {
        if let task {
            task.cancel()
        }
    }

    public func allocateObjectNumber() -> OcaONo {
        defer { nextObjectNumber += 1 }
        return nextObjectNumber
    }

    func handleMessagePdu(_ data: Data) async throws {
        var messagePdus = [Data]()
        let messageType = try await AES70OCP1Connection.decodeOcp1MessagePdu(
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
            let commandResponse = await handleCommand(command, from: controller)
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
