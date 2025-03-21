//
// Copyright (c) 2023-2025 PADL Software Pty Ltd
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
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@_spi(SwiftOCAPrivate)
import SwiftOCA

/// A remote controller
actor Ocp1FlyingSocksStreamController: Ocp1ControllerInternal, CustomStringConvertible {
  nonisolated let connectionPrefix: String

  var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  var keepAliveTask: Task<(), Error>?
  var lastMessageReceivedTime = ContinuousClock.now
  var lastMessageSentTime = ContinuousClock.now
  weak var endpoint: Ocp1FlyingSocksStreamDeviceEndpoint?

  private let address: String
  private let socket: AsyncSocket
  private let _messages: AsyncThrowingStream<AsyncSyncSequence<[ControllerMessage]>, Error>
  private var socketClosed = false

  var messages: AnyAsyncSequence<ControllerMessage> {
    _messages.joined().eraseToAnyAsyncSequence()
  }

  init(endpoint: Ocp1FlyingSocksStreamDeviceEndpoint, socket: AsyncSocket) async throws {
    if case .unix = try? socket.socket.sockname() {
      connectionPrefix = OcaLocalConnectionPrefix
    } else {
      connectionPrefix = OcaTcpConnectionPrefix
      try socket.socket.setValue(
        true,
        for: BoolSocketOption(name: TCP_NODELAY),
        level: IPPROTO_TCP
      )
    }
    address = Self.makeIdentifier(from: socket.socket)
    self.endpoint = endpoint
    self.socket = socket
    _messages = AsyncThrowingStream.decodingMessages(from: socket.bytes, timeout: endpoint.timeout)
  }

  var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  func onConnectionBecomingStale() async throws {
    try await close()
  }

  func sendOcp1EncodedData(_ data: Data) async throws {
    try await socket.write(data)
  }

  private func closeSocket() throws {
    guard !socketClosed else { return }
    try socket.close()
    socketClosed = true
  }

  func close() async throws {
    try closeSocket()

    keepAliveTask?.cancel()
    keepAliveTask = nil
  }

  nonisolated var identifier: String {
    address
  }

  public nonisolated var description: String {
    "\(type(of: self))(address: \(address))"
  }

  private nonisolated var fileDescriptor: Socket.FileDescriptor {
    socket.socket.file
  }
}

extension Ocp1FlyingSocksStreamController: Equatable {
  public nonisolated static func == (
    lhs: Ocp1FlyingSocksStreamController,
    rhs: Ocp1FlyingSocksStreamController
  ) -> Bool {
    lhs.fileDescriptor == rhs.fileDescriptor
  }
}

extension Ocp1FlyingSocksStreamController: Hashable {
  public nonisolated func hash(into hasher: inout Hasher) {
    fileDescriptor.hash(into: &hasher)
  }
}

private extension Ocp1FlyingSocksStreamController {
  static func makeIdentifier(from socket: Socket) -> String {
    guard let peer = try? socket.remotePeer() else {
      return "unknown"
    }

    if case .unix = peer, let unixAddress = try? socket.sockname() {
      return makeIdentifier(from: unixAddress)
    } else {
      return makeIdentifier(from: peer)
    }
  }

  static func makeIdentifier(from peer: Socket.Address) -> String {
    switch peer {
    case let .ip4(address, port):
      "\(address):\(port)"
    case let .ip6(address, port):
      "\(address):\(port)"
    case let .unix(path):
      path
    }
  }
}

private extension AsyncThrowingStream
  where Element == AsyncSyncSequence<[Ocp1ControllerInternal.ControllerMessage]>,
  Failure == Error
{
  static func decodingMessages(
    from bytes: some AsyncBufferedSequence<UInt8>,
    timeout: Duration
  ) -> Self {
    AsyncThrowingStream<
      AsyncSyncSequence<[Ocp1ControllerInternal.ControllerMessage]>,
      Error
    > {
      do {
        return try await withThrowingTimeout(of: timeout) {
          var iterator = bytes.makeAsyncIterator()
          return try await OcaDevice.asyncReceiveMessages { count in
            var nremain = count
            var buffer = [UInt8]()
            buffer.reserveCapacity(count)

            repeat {
              let read = try await iterator.nextBuffer(suggested: nremain)
              guard let read, !read.isEmpty else {
                throw Ocp1Error.notConnected // EOF on zero bytes
              }
              buffer += read
              nremain -= read.count
            } while nremain > 0

            return buffer
          }
        }
      } catch Ocp1Error.pduTooShort {
        return nil
      } catch SocketError.disconnected {
        throw Ocp1Error.notConnected
      } catch {
        throw error
      }
    }
  }
}

extension OcaDevice {
  static func asyncReceiveMessages(_ read: (Int) async throws -> [UInt8]) async throws
    -> AsyncSyncSequence<[Ocp1ControllerInternal.ControllerMessage]>
  {
    try await receiveMessages(read).async
  }
}

#endif
