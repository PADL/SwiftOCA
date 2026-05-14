//
// Copyright (c) 2026 PADL Software Pty Ltd
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

#if canImport(Network)

import AsyncExtensions
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Network
@_spi(SwiftOCAPrivate)
import SwiftOCA
import Synchronization

/// Per-peer remote controller for Network.framework's UDP (plain or DTLS)
/// path. NWListener demuxes datagrams to per-peer NWConnections for us;
/// each `receiveMessage` yields one whole datagram for decode.
package actor Ocp1NWDatagramController: Ocp1ControllerInternal,
  Ocp1ControllerDatagramSemantics,
  CustomStringConvertible
{
  package nonisolated let flags: OcaControllerFlags
  package nonisolated let connectionPrefix: String
  package nonisolated let identifier: String
  /// Filled by the secure UDP endpoint after the DTLS handshake; left
  /// `.anonymous` on plaintext UDP.
  private let _peerIdentity = Mutex<OcaPeerIdentity>(.anonymous)
  package nonisolated var peerIdentity: OcaPeerIdentity {
    _peerIdentity.withLock { $0 }
  }
  package nonisolated func setPeerIdentity(_ identity: OcaPeerIdentity) {
    _peerIdentity.withLock { $0 = identity }
  }

  package var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  package var keepAliveTask: Task<(), Error>?
  package var lastMessageReceivedTime = ContinuousClock.recentPast
  package var lastMessageSentTime = ContinuousClock.recentPast
  package weak var endpoint: Ocp1NWDatagramDeviceEndpoint?

  private let connection: NWConnection
  private let _messages: AsyncThrowingStream<Ocp1MessageList, Error>
  private var connectionClosed = false
  package private(set) var isOpen: Bool = false

  package var messages: AnyAsyncSequence<Ocp1MessageList> {
    _messages.eraseToAnyAsyncSequence()
  }

  package var heartbeatTime = Duration.seconds(1) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  init(endpoint: Ocp1NWDatagramDeviceEndpoint, connection: NWConnection) {
    self.endpoint = endpoint
    self.connection = connection
    flags = endpoint.controllerFlags
    connectionPrefix = endpoint.controllerConnectionPrefix
    identifier = Self.makeIdentifier(from: connection)
    _messages = Self.makeMessagesStream(on: connection)
  }

  package func sendOcp1EncodedData(_ data: Data) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.send(
        content: data,
        completion: .contentProcessed { error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume()
          }
        }
      )
    }
  }

  package func close() async throws {
    guard !connectionClosed else { return }
    connection.cancel()
    connectionClosed = true
    keepAliveTask?.cancel()
    keepAliveTask = nil
  }

  package func didOpen() {
    isOpen = true
  }

  deinit {
    keepAliveTask?.cancel()
  }

  package nonisolated var description: String {
    "\(type(of: self))(\(identifier))"
  }
}

extension Ocp1NWDatagramController: Equatable {
  package nonisolated static func == (
    lhs: Ocp1NWDatagramController,
    rhs: Ocp1NWDatagramController
  ) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }
}

extension Ocp1NWDatagramController: Hashable {
  package nonisolated func hash(into hasher: inout Hasher) {
    ObjectIdentifier(self).hash(into: &hasher)
  }
}

private extension Ocp1NWDatagramController {
  static func makeIdentifier(from connection: NWConnection) -> String {
    switch connection.endpoint {
    case let .hostPort(host, port):
      "\(host):\(port.rawValue)"
    default:
      String(describing: connection.endpoint)
    }
  }

  /// One whole datagram per element; one datagram may carry multiple
  /// concatenated OCP.1 PDUs.
  static func makeMessagesStream(
    on connection: NWConnection
  ) -> AsyncThrowingStream<Ocp1MessageList, Error> {
    AsyncThrowingStream { () async throws -> Ocp1MessageList? in
      let datagram = try await connection.receiveOneDatagram()
      return try Ocp1MessageList(messagePduData: datagram)
    }
  }
}

private extension NWConnection {
  /// Maps graceful peer shutdown (`isComplete && data == nil`) to
  /// `.notConnected` so the stream terminates cleanly.
  func receiveOneDatagram() async throws -> Data {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
      receiveMessage { data, _, isComplete, error in
        if let error {
          continuation.resume(throwing: error)
        } else if isComplete, data == nil {
          continuation.resume(throwing: Ocp1Error.notConnected)
        } else if let data, !data.isEmpty {
          continuation.resume(returning: data)
        } else {
          continuation.resume(throwing: Ocp1Error.notConnected)
        }
      }
    }
  }
}

#endif
