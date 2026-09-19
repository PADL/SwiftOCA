//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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
#if canImport(Glibc)
import Glibc
#elseif canImport(WinSDK)
import WinSDK
#endif

/// A remote controller
package actor OcaFlyingSocksStreamController: Ocp1ControllerInternal, CustomStringConvertible {
  package nonisolated let flags: OcaControllerFlags
  package nonisolated let connectionPrefix: String

  package var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()
  package var keepAliveTask: Task<(), Error>?
  package let writeQueue: Ocp1WriteQueue? = Ocp1WriteQueue()
  package var lastMessageReceivedTime = ContinuousClock.recentPast
  package var lastMessageSentTime = ContinuousClock.recentPast
  package weak var endpoint: OcaFlyingSocksStreamDeviceEndpoint?
  package let controlProtocol: OcaControlProtocol

  private let address: String
  private let socket: AsyncSocket
  private let _messages: AsyncThrowingChannel<Ocp1MessageList, Error>

  package var messages: AnyAsyncSequence<Ocp1MessageList> {
    _messages.eraseToAnyAsyncSequence()
  }

  init(endpoint: OcaFlyingSocksStreamDeviceEndpoint, socket: AsyncSocket) throws {
    if case .unix = try? socket.socket.sockname() {
      connectionPrefix = endpoint.controlProtocol.connectionPrefix(
        ocp1: OcaLocalConnectionPrefix,
        ocp2: OcaJsonLocalConnectionPrefix
      )
      flags = [.supportsLocking, .isLocal]
    } else {
      connectionPrefix = endpoint.controlProtocol.connectionPrefix(
        ocp1: OcaTcpConnectionPrefix,
        ocp2: OcaJsonTcpConnectionPrefix
      )
      flags = .supportsLocking
      try socket.socket.setValue(
        true,
        for: BoolSocketOption(name: TCP_NODELAY),
        level: CInt(IPPROTO_TCP)
      )
    }
    address = Self.makeIdentifier(from: socket.socket)
    self.endpoint = endpoint
    controlProtocol = endpoint.controlProtocol
    self.socket = socket
    _messages = AsyncThrowingChannel.decodingMessages(
      from: socket.bytes,
      timeout: endpoint.timeout,
      controlProtocol: endpoint.controlProtocol,
      maximumPduSize: endpoint.maximumPduSize
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
    // A keepalive expiry closes the controller while its message loop is suspended reading
    // the socket. Closing the descriptor under that read would never wake it, so shut the
    // socket down instead: the read sees end of file and the loop ends, as FlyingFox expects
    // before a socket is closed. The descriptor is closed when the controller is released.
    #if canImport(WinSDK)
    _ = shutdown(socket.socket.file.rawValue, SD_BOTH)
    #else
    _ = shutdown(socket.socket.file.rawValue, Int32(SHUT_RDWR))
    #endif

    _messages.finish()
    keepAliveTask?.cancel()
    keepAliveTask = nil
  }

  deinit {
    keepAliveTask?.cancel()
    _messages.finish()
    try? socket.close()
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

extension OcaFlyingSocksStreamController: Equatable {
  package nonisolated static func == (
    lhs: OcaFlyingSocksStreamController,
    rhs: OcaFlyingSocksStreamController
  ) -> Bool {
    lhs.fileDescriptor == rhs.fileDescriptor
  }
}

extension OcaFlyingSocksStreamController: Hashable {
  package nonisolated func hash(into hasher: inout Hasher) {
    fileDescriptor.hash(into: &hasher)
  }
}

private extension OcaFlyingSocksStreamController {
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

private extension AsyncThrowingChannel
  where Element == Ocp1MessageList,
  Failure == Error
{
  static func decodingMessages(
    from bytes: some AsyncBufferedSequence<UInt8> & Sendable,
    timeout: Duration,
    controlProtocol: OcaControlProtocol,
    maximumPduSize: Int
  ) -> Self {
    let channel = Self()
    // one timer for every read on the connection, rather than a sleep per message that the
    // runtime would keep for the whole timeout after the message arrived
    let deadlines = DeadlineTimer()

    Task {
      // one iterator and one reader for the life of the connection, owned by this task: the
      // reader buffers bytes between PDUs, so neither can be recreated per PDU or shared
      var iterator = bytes.makeAsyncIterator()
      let reader = controlProtocol.makeReader(
        preservesPduBoundaries: false,
        maximumPduSize: maximumPduSize
      )

      do {
        repeat {
          // a timeout fails the stream from a watchdog, rather than moving the read, and
          // with it the reader, into a task of its own
          let deadline = ContinuousClock.now + timeout
          let watchdog = deadlines.watchdog(for: timeout) {
            channel.fail(Ocp1Error.responseTimeout)
          }
          let messages: Ocp1MessageList
          do {
            messages = try await OcaDevice.asyncReceiveMessages(
              reader: reader,
              controlProtocol: controlProtocol,
              read: { count, awaitingAllRead in
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
                } while awaitingAllRead && nremain > 0

                return buffer
              }
            )
          } catch {
            watchdog?.cancel()
            throw error
          }
          watchdog?.cancel()
          // the stream has failed if the watchdog fired, and nothing else ends this task
          // until the socket is closed: stop reading, rather than drop what arrives
          if watchdog != nil, ContinuousClock.now >= deadline {
            throw Ocp1Error.responseTimeout
          }
          await channel.send(messages)
        } while true
      } catch Ocp1Error.pduTooShort {
        channel.finish()
      } catch SocketError.disconnected {
        channel.fail(Ocp1Error.notConnected)
      } catch {
        channel.fail(error)
      }
    }

    return channel
  }
}

#endif
