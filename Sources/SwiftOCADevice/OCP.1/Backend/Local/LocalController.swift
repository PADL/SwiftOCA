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
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftOCA

package actor OcaLocalController: Ocp1ControllerInternal {
  package nonisolated var flags: OcaControllerFlags { [.supportsLocking, .isLocal] }
  package nonisolated var connectionPrefix: String { OcaLocalConnectionPrefix }

  package var lastMessageReceivedTime = ContinuousClock.recentPast
  package var lastMessageSentTime = ContinuousClock.recentPast
  package var heartbeatTime = Duration.seconds(0)
  package var keepAliveTask: Task<(), Error>?

  package weak var endpoint: OcaLocalDeviceEndpoint?
  package var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()

  init(endpoint: OcaLocalDeviceEndpoint) async {
    self.endpoint = endpoint
  }

  package var messages: AnyAsyncSequence<Ocp1MessageList> {
    endpoint!.requestChannel.map { data in
      try Ocp1MessageList(messagePduData: data)
    }.eraseToAnyAsyncSequence()
  }

  package func sendOcp1EncodedData(_ data: Data) async throws {
    await endpoint?.responseChannel.send(data)
  }

  package nonisolated var identifier: String {
    "local"
  }

  package func close() throws {}

  deinit {
    keepAliveTask?.cancel()
  }
}
