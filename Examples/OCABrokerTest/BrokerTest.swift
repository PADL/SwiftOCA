//
// Copyright (c) 2025 PADL Software Pty Ltd
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

import SwiftOCA

private let connectionOptions = Ocp1ConnectionOptions(flags: [
  .automaticReconnect,
//  .enableTracing,
  .refreshSubscriptionsOnReconnection,
  .retainObjectCacheAfterDisconnect,
])

@main
public enum BrokerTest {
  public static func main() async throws {
#if canImport(Darwin)
    let broker = await OcaConnectionBroker(connectionOptions: connectionOptions)
    print("waiting for events from broker...")
    for try await event in await broker.events {
      print("\(event)")
      switch event.eventType {
      case .deviceAdded:
        Task { try await broker.connect(device: event.deviceIdentifier) }
      default:
        break
      }
    }
    print("done!")
#else
    preconditionFailure("OcaConnectionBroker not yet supported on non-Darwin platforms")
#endif
  }
}
