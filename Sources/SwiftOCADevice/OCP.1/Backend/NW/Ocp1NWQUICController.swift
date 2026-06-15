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

#if canImport(Network)

import AsyncAlgorithms
import AsyncExtensions
import Foundation
import Network
@_spi(SwiftOCAPrivate)
import SwiftOCA

@available(macOS 14.0, iOS 17.0, *)
actor Ocp1NWQUICController: Ocp1ControllerInternal, CustomStringConvertible {
  nonisolated var flags: OcaControllerFlags { .supportsLocking }
  nonisolated let connectionPrefix: String

  var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  var keepAliveTask: Task<(), Error>?
  var lastMessageReceivedTime = ContinuousClock.recentPast
  var lastMessageSentTime = ContinuousClock.recentPast
  weak var endpoint: Ocp1NWQUICDeviceEndpoint?

  private let _connection: NWConnection
  private let _queue: DispatchQueue
  private let _messages: AsyncThrowingStream<Ocp1MessageList, Error>
  private nonisolated let _identifier: String

  var messages: AnyAsyncSequence<Ocp1MessageList> {
    _messages.eraseToAnyAsyncSequence()
  }

  init(
    endpoint: Ocp1NWQUICDeviceEndpoint,
    connection: NWConnection,
    queue: DispatchQueue
  ) throws {
    self.endpoint = endpoint
    self._connection = connection
    self._queue = queue
    self.connectionPrefix = OcaQuicConnectionPrefix

    _identifier = Self.makeIdentifier(from: connection)
    _messages = Self.decodingMessages(from: connection, timeout: endpoint.timeout)

    connection.start(queue: queue)
  }

  var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  func sendOcp1EncodedData(_ data: Data) async throws {
    try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, Error>) in
      _connection.send(
        content: data,
        isComplete: false,
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

  func close() async throws {
    _connection.cancel()
    keepAliveTask?.cancel()
    keepAliveTask = nil
  }

  deinit {
    keepAliveTask?.cancel()
  }

  nonisolated var identifier: String {
    _identifier
  }

  nonisolated var description: String {
    "\(type(of: self))(address: \(_identifier))"
  }
}

@available(macOS 14.0, iOS 17.0, *)
extension Ocp1NWQUICController: Equatable {
  nonisolated static func == (
    lhs: Ocp1NWQUICController,
    rhs: Ocp1NWQUICController
  ) -> Bool {
    lhs._identifier == rhs._identifier
  }
}

@available(macOS 14.0, iOS 17.0, *)
extension Ocp1NWQUICController: Hashable {
  nonisolated func hash(into hasher: inout Hasher) {
    _identifier.hash(into: &hasher)
  }
}

@available(macOS 14.0, iOS 17.0, *)
private extension Ocp1NWQUICController {
  static func makeIdentifier(from connection: NWConnection) -> String {
    switch connection.endpoint {
    case let .hostPort(host, port):
      "\(host):\(port)"
    default:
      "\(connection.endpoint)"
    }
  }

  static func decodingMessages(
    from connection: NWConnection,
    timeout: Duration
  ) -> AsyncThrowingStream<Ocp1MessageList, Error> {
    AsyncThrowingStream<Ocp1MessageList, Error> {
      do {
        return try await withThrowingTimeout(of: timeout, clock: .continuous) {
          try await OcaDevice.receiveMessages { count in
            try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Data, Error>) in
              connection.receive(
                minimumIncompleteLength: count,
                maximumLength: max(count, Ocp1MaximumDatagramPduSize)
              ) { data, _, _, error in
                if let error {
                  continuation.resume(throwing: error)
                } else if let data {
                  continuation.resume(returning: data)
                } else {
                  continuation.resume(throwing: Ocp1Error.notConnected)
                }
              }
            }
          }
        }
      } catch {
        throw error
      }
    }
  }
}

#endif
