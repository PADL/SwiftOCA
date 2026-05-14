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

import AsyncAlgorithms
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

/// Remote controller via Network.framework; shared by plaintext TCP and TLS.
package actor Ocp1NWStreamController: Ocp1ControllerInternal, CustomStringConvertible {
  package nonisolated let flags: OcaControllerFlags
  package nonisolated let connectionPrefix: String
  package nonisolated let identifier: String
  /// Filled by the secure endpoint on `.ready`; left `.anonymous` on plaintext.
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
  package weak var endpoint: Ocp1NWStreamDeviceEndpoint?

  private let connection: NWConnection
  private let _messages: AsyncThrowingStream<Ocp1MessageList, Error>
  private var connectionClosed = false

  package var messages: AnyAsyncSequence<Ocp1MessageList> {
    _messages.eraseToAnyAsyncSequence()
  }

  package var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  init(endpoint: Ocp1NWStreamDeviceEndpoint, connection: NWConnection) {
    self.endpoint = endpoint
    self.connection = connection
    flags = endpoint.controllerFlags
    connectionPrefix = endpoint.controllerConnectionPrefix
    identifier = Self.makeIdentifier(from: connection)
    _messages = Self.makeMessagesStream(on: connection, timeout: endpoint.timeout)
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

  deinit {
    keepAliveTask?.cancel()
  }

  package nonisolated var description: String {
    "\(type(of: self))(\(identifier))"
  }
}

extension Ocp1NWStreamController: Equatable {
  package nonisolated static func == (
    lhs: Ocp1NWStreamController,
    rhs: Ocp1NWStreamController
  ) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }
}

extension Ocp1NWStreamController: Hashable {
  package nonisolated func hash(into hasher: inout Hasher) {
    ObjectIdentifier(self).hash(into: &hasher)
  }
}

private extension Ocp1NWStreamController {
  static func makeIdentifier(from connection: NWConnection) -> String {
    switch connection.endpoint {
    case let .hostPort(host, port):
      "\(host):\(port.rawValue)"
    case let .unix(path):
      path
    default:
      String(describing: connection.endpoint)
    }
  }

  static func makeMessagesStream(
    on connection: NWConnection,
    timeout: Duration
  ) -> AsyncThrowingStream<Ocp1MessageList, Error> {
    AsyncThrowingStream { () async throws -> Ocp1MessageList? in
      try await withThrowingTimeout(of: timeout, clock: .continuous) {
        try await OcaDevice.asyncReceiveMessages { count in
          try await connection.receiveExactly(count)
        }
      }
    }
  }
}

extension NWConnection {
  /// Maps graceful peer-close to `.notConnected`.
  fileprivate func receiveExactly(_ count: Int) async throws -> Data {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
      receive(minimumIncompleteLength: count, maximumLength: count) { data, _, isComplete, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let data, data.count == count {
          continuation.resume(returning: data)
        } else if isComplete {
          continuation.resume(throwing: Ocp1Error.notConnected)
        } else {
          continuation.resume(throwing: Ocp1Error.notConnected)
        }
      }
    }
  }
}

#endif
