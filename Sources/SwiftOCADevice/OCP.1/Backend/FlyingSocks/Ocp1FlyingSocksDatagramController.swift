//
// Copyright (c) 2023-2024 PADL Software Pty Ltd
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

#if os(macOS) || os(iOS)

import AsyncAlgorithms
import AsyncExtensions
import FlyingSocks
import Foundation
@_spi(SwiftOCAPrivate)
import SwiftOCA

/// A remote controller
actor Ocp1FlyingSocksDatagramController: Ocp1ControllerInternal {
  nonisolated var connectionPrefix: String { OcaUdpConnectionPrefix }

  var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  let peerAddress: any SocketAddress
  let interfaceIndex: UInt32?
  let localAddress: (any SocketAddress)?
  var keepAliveTask: Task<(), Error>?
  var lastMessageReceivedTime = ContinuousClock.now
  var lastMessageSentTime = ContinuousClock.now

  private(set) var isOpen: Bool = false
  weak var endpoint: Ocp1FlyingSocksDatagramDeviceEndpoint?

  var messages: AnyAsyncSequence<ControllerMessage> {
    AsyncEmptySequence<ControllerMessage>().eraseToAnyAsyncSequence()
  }

  init(
    endpoint: Ocp1FlyingSocksDatagramDeviceEndpoint,
    peerAddress: any SocketAddress,
    interfaceIndex: UInt32?,
    localAddress: (any SocketAddress)?
  ) async throws {
    self.endpoint = endpoint
    self.peerAddress = peerAddress
    self.interfaceIndex = interfaceIndex
    self.localAddress = localAddress
  }

  func onConnectionBecomingStale() async throws {
    await endpoint?.unlockAndRemove(controller: self)
  }

  var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  func sendOcp1EncodedData(_ data: Data) async throws {
    let peerAddress = AnySocketAddress(peerAddress)
    let localAddress = localAddress != nil ? AnySocketAddress(localAddress!) : nil

    try await sendOcp1EncodedMessage(AsyncSocket.Message(
      peerAddress: peerAddress,
      bytes: Array(data),
      interfaceIndex: interfaceIndex,
      localAddress: localAddress
    ))
  }

  func sendOcp1EncodedMessage(_ messagePdu: AsyncSocket.Message) async throws {
    try await endpoint?.sendOcp1EncodedMessage(messagePdu)
  }

  func close() async throws {}

  func didOpen() {
    isOpen = true
  }

  nonisolated var identifier: String {
    peerAddress.withSockAddr { sa in
      deviceAddressToString(sa)
    }
  }

  nonisolated func matchesPeer(address: SocketAddress) -> Bool {
    var lhs = peerAddress.makeStorage()
    var rhs = address.makeStorage()

    return memcmp(&lhs, &rhs, MemoryLayout<sockaddr_storage>.size) == 0
  }
}

extension Ocp1FlyingSocksDatagramController: Equatable {
  public nonisolated static func == (
    lhs: Ocp1FlyingSocksDatagramController,
    rhs: Ocp1FlyingSocksDatagramController
  ) -> Bool {
    lhs.matchesPeer(address: rhs.peerAddress)
  }
}

extension Ocp1FlyingSocksDatagramController: Hashable {
  public nonisolated func hash(into hasher: inout Hasher) {
    var peerAddress = peerAddress.makeStorage()
    Data(bytes: &peerAddress, count: MemoryLayout<sockaddr_storage>.size).hash(into: &hasher)
  }
}

#endif
