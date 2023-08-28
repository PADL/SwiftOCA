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

actor AES70LocalController: _AES70ControllerInternal {
    weak var listener: AES70LocalListener?
    var subscriptions = [OcaONo: NSMutableSet]()

    init(listener: AES70LocalListener) async {
        self.listener = listener
    }

    func sendMessages(
        _ messages: AnyAsyncSequence<Ocp1Message>,
        type messageType: OcaMessageType
    ) async throws {
        let messages = try await messages.collect()
        let messagePduData = try await AES70OCP1Connection.encodeOcp1MessagePdu(
            messages,
            type: messageType
        )
        await listener?.responseChannel.send(messagePduData)
    }
}
