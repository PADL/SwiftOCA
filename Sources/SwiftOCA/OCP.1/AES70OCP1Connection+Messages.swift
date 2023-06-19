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
    @MainActor
    private func sendMessage(_ message: Ocp1Message, type messageType: OcaMessageType) async throws {
        guard let requestMonitor = requestMonitor else { throw Ocp1Error.notConnected }
        await requestMonitor.channel.send((messageType, [message]))
    }

    @MainActor
    func sendCommand(_ command: Ocp1Command) async throws {
        // debugPrint("sendCommand \(command)")
        try await sendMessage(command, type: .ocaCmd)
    }
    
    @MainActor
    private func response(for handle: OcaUint32) async throws -> Ocp1Response {
        guard let responseMonitor = responseMonitor else {
            throw Ocp1Error.notConnected
        }
        
        let deadline = Date() + responseTimeout
        repeat {
            for await response in responseMonitor.channel {
                if response.handle == handle {
                    return response
                }
            }
        } while Date() < deadline
        debugPrint("timed out waiting for response for handle \(handle)")
        throw Ocp1Error.responseTimeout
    }

    @MainActor
    func sendCommandRrq(_ command: Ocp1Command) async throws -> Ocp1Response {
        try await sendMessage(command, type: .ocaCmdRrq)
        return try await response(for: command.handle)
    }

    @MainActor
    func sendKeepAlive() async throws {
        let message = Ocp1KeepAlive1(heartBeatTime: keepAliveInterval)
        try await sendMessage(message, type: .ocaKeepAlive)
    }
}
