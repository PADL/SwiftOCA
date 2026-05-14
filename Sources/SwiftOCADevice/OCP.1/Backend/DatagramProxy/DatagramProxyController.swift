//
// Copyright (c) 2024 PADL Software Pty Ltd
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

package actor DatagramProxyController<T: DatagramProxyPeerIdentifier>: Ocp1ControllerInternal,
  Ocp1ControllerDatagramSemantics,
  CustomStringConvertible
{
  package nonisolated var flags: OcaControllerFlags { .supportsLocking }
  package nonisolated var connectionPrefix: String { OcaDatagramProxyConnectionPrefix }

  let peerID: T
  package var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  package var keepAliveTask: Task<(), Error>?
  package var lastMessageReceivedTime = ContinuousClock.recentPast
  package var lastMessageSentTime = ContinuousClock.recentPast

  package private(set) var isOpen: Bool = false
  package weak var endpoint: DatagramProxyDeviceEndpoint<T>?

  package var messages: AnyAsyncSequence<Ocp1MessageList> {
    AsyncEmptySequence<Ocp1MessageList>().eraseToAnyAsyncSequence()
  }

  init(with peerID: T, endpoint: DatagramProxyDeviceEndpoint<T>) {
    self.peerID = peerID
    self.endpoint = endpoint
    heartbeatTime = endpoint.timeout
  }

  package var heartbeatTime: Duration {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  func startKeepAliveIfNeeded() {
    if keepAliveTask == nil {
      lastMessageReceivedTime = .now
      heartbeatTimeDidChange(from: .zero)
    }
  }

  package func sendOcp1EncodedData(_ data: Data) async throws {
    endpoint?.outputStream.yield((peerID, [UInt8](data)))
  }

  package nonisolated var identifier: String {
    String(describing: peerID)
  }

  package nonisolated var description: String {
    "\(type(of: self))(peerID: \(String(describing: peerID))"
  }

  package func close() async throws {}

  package func didOpen() {
    isOpen = true
  }
}
