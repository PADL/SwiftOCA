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

public final class AES70LocalConnection: AES70OCP1Connection {
    nonisolated static var connectionPrefix: String { "oca/local" }

    let endpoint: AES70LocalDeviceEndpoint

    public init(
        _ endpoint: AES70LocalDeviceEndpoint
    ) {
        self.endpoint = endpoint
        super.init(options: AES70OCP1ConnectionOptions())
    }

    override public var connectionPrefix: String {
        "oca/local"
    }

    override public var heartbeatTime: Duration {
        .zero
    }

    override public func disconnectDevice(clearObjectCache: Bool) async throws {
        try await super.disconnectDevice(clearObjectCache: clearObjectCache)
        endpoint.responseChannel.finish()
        endpoint.requestChannel.finish()
    }

    override public func read(_ length: Int) async throws -> Data {
        for await data in endpoint.responseChannel {
            return data
        }
        throw Ocp1Error.pduTooShort
    }

    override public func write(_ data: Data) async throws -> Int {
        // this can't run on the same actor otherwise we can deadlock with read()
        Task { await endpoint.requestChannel.send(data) }
        return data.count
    }
}
