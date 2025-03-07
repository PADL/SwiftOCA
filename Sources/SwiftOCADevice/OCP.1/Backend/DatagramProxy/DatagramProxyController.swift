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

actor DatagramProxyController<T: DatagramProxyPeerIdentifier>: Ocp1ControllerInternal,
  Ocp1ControllerDatagramSemantics,
  CustomStringConvertible
{
  nonisolated var connectionPrefix: String { OcaDatagramProxyConnectionPrefix }

  let peerID: T
  var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  var keepAliveTask: Task<(), Error>?
  var lastMessageReceivedTime = ContinuousClock.now
  var lastMessageSentTime = ContinuousClock.now

  private(set) var isOpen: Bool = false
  weak var endpoint: DatagramProxyDeviceEndpoint<T>?

  var messages: AnyAsyncSequence<ControllerMessage> {
    AsyncEmptySequence<ControllerMessage>().eraseToAnyAsyncSequence()
  }

  init(with peerID: T, endpoint: DatagramProxyDeviceEndpoint<T>) {
    self.peerID = peerID
    self.endpoint = endpoint
  }

  var heartbeatTime = Duration.seconds(1) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  func sendOcp1EncodedData(_ data: Data) async throws {
    endpoint?.outputStream.yield((peerID, [UInt8](data)))
  }

  nonisolated var identifier: String {
    String(describing: peerID)
  }

  public nonisolated var description: String {
    "\(type(of: self))(peerID: \(String(describing: peerID))"
  }

  func onConnectionBecomingStale() async throws {}

  func close() async throws {}

  func didOpen() {
    isOpen = true
  }
}
