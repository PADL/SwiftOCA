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

#if os(macOS) || os(iOS) || os(Windows) || !NonEmbeddedBuild

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
import Synchronization
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WinSDK)
import WinSDK
#endif

/// A remote controller
package actor Ocp1FlyingSocksStreamController: Ocp1ControllerInternal, CustomStringConvertible {
  package nonisolated let flags: OcaControllerFlags
  package nonisolated let connectionPrefix: String

  package var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  package var keepAliveTask: Task<(), Error>?
  package let writeQueue: Ocp1WriteQueue? = Ocp1WriteQueue()
  package var lastMessageReceivedTime = ContinuousClock.recentPast
  package var lastMessageSentTime = ContinuousClock.recentPast
  package weak var endpoint: Ocp1FlyingSocksStreamDeviceEndpoint?

  private let address: String
  private let socket: AsyncSocket
  private let lifetime: Ocp1FlyingSocksSocketLifetime
  private let _messages: AsyncThrowingStream<Ocp1MessageList, Error>

  package var messages: AnyAsyncSequence<Ocp1MessageList> {
    _messages.eraseToAnyAsyncSequence()
  }

  init(endpoint: Ocp1FlyingSocksStreamDeviceEndpoint, socket: AsyncSocket) throws {
    if case .unix = try? socket.socket.sockname() {
      connectionPrefix = OcaLocalConnectionPrefix
      flags = [.supportsLocking, .isLocal]
    } else {
      connectionPrefix = OcaTcpConnectionPrefix
      flags = .supportsLocking
      try socket.socket.setValue(
        true,
        for: BoolSocketOption(name: TCP_NODELAY),
        level: CInt(IPPROTO_TCP)
      )
    }
    address = Self.makeIdentifier(from: socket.socket)
    self.endpoint = endpoint
    self.socket = socket
    let lifetime = Ocp1FlyingSocksSocketLifetime(socket)
    self.lifetime = lifetime
    _messages = AsyncThrowingStream.decodingMessages(
      from: socket.bytes,
      timeout: endpoint.timeout,
      onEnd: { lifetime.readEnded() }
    )
  }

  package var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  package func sendOcp1EncodedData(_ data: Data) async throws {
    try await socket.write(data)
  }

  package func close() async throws {
    // Shut the socket down rather than close it. The message loop may be suspended reading
    // it, as when a keepalive expires, and closing the descriptor under that read would
    // leave the socket pool waiting on it for good. Shutting it down wakes the read with
    // end of file, and the descriptor is closed once the message stream has ended.
    lifetime.shutDown()

    keepAliveTask?.cancel()
    keepAliveTask = nil
  }

  deinit {
    keepAliveTask?.cancel()
  }

  package nonisolated var identifier: String {
    address
  }

  package nonisolated var description: String {
    "\(type(of: self))(address: \(address))"
  }

  private nonisolated var fileDescriptor: Socket.FileDescriptor {
    socket.socket.file
  }
}

/// Closes a controller's socket exactly once, and never while its message stream is
/// suspended reading it. A socket closed under a suspended read leaves the FlyingSocks
/// socket pool waiting on a descriptor that reports nothing more, and that a socket accepted
/// later may be given (swhitty/FlyingFox#244). So `shutDown()`, from `close()`, shuts the
/// socket down, which wakes the read with end of file, and the socket is closed by whichever
/// comes last of that and the stream ending. The shutdown and the close are both made under
/// the lock, so neither can reach a descriptor already closed and given to another socket.
private final class Ocp1FlyingSocksSocketLifetime: Sendable {
  private struct State {
    var readEnded = false
    var shutDown = false
    var closed = false
  }

  private let socket: AsyncSocket
  private let state = Mutex(State())

  init(_ socket: AsyncSocket) {
    self.socket = socket
  }

  /// From `close()`: shut the socket down, closing it at once if the stream has ended.
  func shutDown() {
    state.withLock { state in
      guard !state.closed else { return }
      state.shutDown = true
      if state.readEnded {
        state.closed = true
        try? socket.close()
      } else {
        // wakes the read the stream is suspended on; the stream then ends and closes it
        Self.shutDownBothDirections(socket.socket.file)
      }
    }
  }

  /// From the message stream once it has ended, so that no read is suspended on the socket.
  func readEnded() {
    state.withLock { state in
      state.readEnded = true
      guard state.shutDown, !state.closed else { return }
      state.closed = true
      try? socket.close()
    }
  }

  deinit {
    // if neither got as far as closing it
    state.withLock { state in
      guard !state.closed else { return }
      state.closed = true
      try? socket.close()
    }
  }

  private static func shutDownBothDirections(_ file: Socket.FileDescriptor) {
    #if canImport(WinSDK)
    _ = shutdown(file.rawValue, SD_BOTH)
    #else
    _ = shutdown(file.rawValue, Int32(SHUT_RDWR))
    #endif
  }
}

extension Ocp1FlyingSocksStreamController: Equatable {
  package nonisolated static func == (
    lhs: Ocp1FlyingSocksStreamController,
    rhs: Ocp1FlyingSocksStreamController
  ) -> Bool {
    lhs.fileDescriptor == rhs.fileDescriptor
  }
}

extension Ocp1FlyingSocksStreamController: Hashable {
  package nonisolated func hash(into hasher: inout Hasher) {
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
  where Element == Ocp1MessageList,
  Failure == Error
{
  /// `onEnd` is called when the stream ends, however it ends, and so has no read suspended.
  static func decodingMessages(
    from bytes: some AsyncBufferedSequence<UInt8>,
    timeout: Duration,
    onEnd: @escaping @Sendable () -> ()
  ) -> Self {
    // one timer for every read on the connection, rather than a sleep per message that the
    // runtime would keep for the whole timeout after the message arrived
    let deadlines = DeadlineTimer()
    return AsyncThrowingStream<Ocp1MessageList, Error> {
      do {
        return try await deadlines.withThrowingTimeout(of: timeout) {
          nonisolated(unsafe) var iterator = bytes.makeAsyncIterator()
          return try await OcaDevice.asyncReceiveMessages { count in
            var nremain = count
            var buffer = Data()
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
        onEnd()
        return nil
      } catch SocketError.disconnected {
        onEnd()
        throw Ocp1Error.notConnected
      } catch {
        onEnd()
        throw error
      }
    }
  }
}

extension OcaDevice {
  static func asyncReceiveMessages(_ read: (Int) async throws -> Data) async throws
    -> Ocp1MessageList
  {
    try await _receiveMessages(read)
  }
}

#endif
