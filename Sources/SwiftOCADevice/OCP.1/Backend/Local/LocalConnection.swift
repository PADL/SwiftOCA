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
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftOCA

public final class OcaLocalConnection: Ocp1Connection {
  let endpoint: OcaLocalDeviceEndpoint

  public init(
    _ endpoint: OcaLocalDeviceEndpoint
  ) {
    self.endpoint = endpoint
    super.init(options: Ocp1ConnectionOptions())
  }

  override public var connectionPrefix: String {
    OcaLocalConnectionPrefix
  }

  override public var heartbeatTime: Duration {
    .zero
  }

  override public func disconnectDevice() async throws {
    try await super.disconnectDevice()
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
