//
// Copyright (c) 2024-2026 PADL Software Pty Ltd
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

#if canImport(FlyingFox)

import AsyncExtensions
import FlyingFox
import FlyingSocks
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftOCA

/// A remote WebSocket endpoint
package actor Ocp1FlyingFoxController: Ocp1ControllerInternal, CustomStringConvertible {
  package nonisolated var flags: OcaControllerFlags {
    .supportsLocking
  }

  package nonisolated var connectionPrefix: String {
    _connectionPrefix
  }

  private nonisolated let _connectionPrefix: String
  private nonisolated let _usesTextFrames: Bool

  package var subscriptions = [OcaONo: Set<OcaSubscriptionManagerSubscription>]()

  private let _messages: AsyncThrowingStream<Ocp1MessageList, Error>
  private let outputStream: AsyncStream<WSMessage>.Continuation
  package var endpoint: Ocp1FlyingFoxDeviceEndpoint?
  package nonisolated let identifier: String
  package let controlProtocol: OcaControlProtocol

  package var keepAliveTask: Task<(), Error>?
  package let writeQueue: Ocp1WriteQueue? = Ocp1WriteQueue()
  package var lastMessageReceivedTime = ContinuousClock.recentPast
  package var lastMessageSentTime = ContinuousClock.recentPast

  package var messages: AsyncExtensions.AnyAsyncSequence<Ocp1MessageList> {
    _messages.eraseToAnyAsyncSequence()
  }

  init(
    endpoint: Ocp1FlyingFoxDeviceEndpoint?,
    controlProtocol: OcaControlProtocol,
    identifier: String,
    inputStream: AsyncStream<WSMessage>,
    outputStream: AsyncStream<WSMessage>.Continuation
  ) {
    self.outputStream = outputStream
    self.endpoint = endpoint
    self.identifier = identifier
    self.controlProtocol = controlProtocol
    let usesTextFrames = controlProtocol.webSocketUsesTextFrames
    _usesTextFrames = usesTextFrames
    _connectionPrefix = controlProtocol.connectionPrefix(
      ocp1: OcaWebSocketTcpConnectionPrefix,
      ocp2: OcaJsonWebSocketTcpConnectionPrefix
    )
    let maximumPduSize = endpoint?.maximumPduSize ?? OcaControlProtocol.defaultMaximumPduSize
    _messages = AsyncThrowingStream { continuation in
      let task = Task { [inputStream] in
        // consecutive frame payloads are a byte stream (AES70-4 10.4.3.4.4), so
        // one reader spans frames; OCP.1 keeps one PDU per binary frame
        let reader = controlProtocol.makeReader(
          isMessageOriented: !usesTextFrames,
          maximumPduSize: maximumPduSize
        )
        nonisolated(unsafe) var frames = inputStream.makeAsyncIterator()
        /// AES70-4 10.4.3.4.4: a binary frame closes with 1003, a malformed message
        /// with 1007; an over-long one with 1009. Each failure sends one close frame.
        func fail(_ code: WSCloseCode, _ error: Error) {
          outputStream.yield(.close(code))
          continuation.finish(throwing: error)
        }
        while true {
          let pdu: Data
          do {
            // one frame per read, whatever is asked for: WebSocket is message-oriented
            pdu = try await reader.nextPdu(read: { _, _ in
              try await Self.nextFrame(&frames, text: usesTextFrames)
            })
          } catch Ocp1Error.notConnected {
            continuation.finish()
            return
          } catch Ocp1Error.invalidMessageType {
            fail(.unsupportedData, Ocp1Error.invalidMessageType)
            return
          } catch Ocp1Error.invalidPduSize {
            fail(.messageTooBig, Ocp1Error.invalidPduSize)
            return
          } catch {
            continuation.finish(throwing: error)
            return
          }
          do {
            try continuation.yield(Ocp1MessageList(messagePduData: pdu, controlProtocol: controlProtocol))
          } catch {
            fail(usesTextFrames ? .invalidFramePayload : .protocolError, error)
            return
          }
        }
      }

      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }

  /// The next frame's payload, requiring text frames on OCP.2 and binary on OCP.1.
  private static func nextFrame(
    _ frames: inout AsyncStream<WSMessage>.AsyncIterator,
    text: Bool
  ) async throws -> Data {
    guard let message = await frames.next() else {
      throw Ocp1Error.notConnected
    }
    switch message {
    case let .data(data) where !text:
      return data
    case let .text(string) where text:
      return Data(string.utf8)
    case .close:
      throw Ocp1Error.notConnected
    default:
      throw Ocp1Error.invalidMessageType
    }
  }

  package var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  package func sendOcp1EncodedData(_ data: Data) async throws {
    if _usesTextFrames {
      outputStream.yield(.text(String(decoding: data, as: UTF8.self)))
    } else {
      outputStream.yield(.data(data))
    }
  }

  package func close() async {
    outputStream.finish()

    keepAliveTask?.cancel()
    keepAliveTask = nil
  }

  deinit {
    keepAliveTask?.cancel()
    outputStream.finish()
  }

  package nonisolated var description: String {
    "\(type(of: self))(address: \(identifier))"
  }
}

#endif
