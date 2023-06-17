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

import Foundation

extension AES70OCP1Connection {
    private func sendMessage(_ message: Ocp1Message, type messageType: OcaMessageType) async throws {
        guard let requestMonitor = await requestMonitor else { throw Ocp1Error.notConnected }
        await requestMonitor.channel.send((messageType, [message]))
    }

    func sendCommand(_ command: Ocp1Command) async throws {
        // debugPrint("sendCommand \(command)")
        try await sendMessage(command, type: .ocaCmd)
    }
    
    private func response(for handle: OcaUint32) async throws -> Ocp1Response {
        let deadline = Date() + self.responseTimeout
        
        guard let responseMonitor = await responseMonitor else { throw Ocp1Error.notConnected }
        
        for await response in responseMonitor.channel {
            // debugPrint("awaiting response \(response)")
            if response.handle == handle {
                return response
            }
            if Date() > deadline {
                break
            }
        }
        throw Ocp1Error.responseTimeout
    }

    func sendCommandRrq(_ command: Ocp1Command) async throws -> Ocp1Response {
        // debugPrint("sendCommandRrq \(command)")
        
        try await sendMessage(command, type: .ocaCmdRrq)
        return try await response(for: command.handle)
    }

    func sendKeepAlive() async throws {
        let message = Ocp1KeepAlive1(heartBeatTime: keepAliveInterval)
        try await sendMessage(message, type: .ocaKeepAlive)
    }
}
