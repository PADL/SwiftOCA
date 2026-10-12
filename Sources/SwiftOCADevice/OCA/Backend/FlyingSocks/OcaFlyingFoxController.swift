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

import AsyncAlgorithms
import AsyncExtensions
import FlyingFox
import FlyingSocks
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftOCA
import Synchronization

/// A remote WebSocket endpoint
package actor OcaFlyingFoxController: Ocp1ControllerInternal, CustomStringConvertible {
  package nonisolated var flags: OcaControllerFlags {
    .supportsLocking
  }

  package nonisolated var connectionPrefix: String {
    _connectionPrefix
  }

  private nonisolated let _connectionPrefix: String
  private nonisolated let _usesTextFrames: Bool

  private let _messages: AsyncThrowingChannel<Ocp1MessageList, Error>
  private var receiveMessageTask: Task<(), Never>?
  private let output: AsyncChannel<WSFrame>
  private nonisolated let isClosed = Atomic(false)
  package var endpoint: OcaFlyingFoxDeviceEndpoint?
  package nonisolated let identifier: String
  package let controlProtocol: OcaControlProtocol

  package var keepAliveTask: Task<(), Error>?
  package let writeQueue: Ocp1WriteQueue? = Ocp1WriteQueue()
  package var lastMessageReceivedTime = ContinuousClock.recentPast
  package var lastMessageSentTime = ContinuousClock.recentPast

  package var messages: AsyncExtensions.AnyAsyncSequence<Ocp1MessageList> {
    _messages.eraseToAnyAsyncSequence()
  }

  /// `frames` are the peer's, read only as PDUs are wanted, so a peer that floods waits in
  /// its socket. `output` takes a frame only when the server is about to write it.
  init(
    endpoint: OcaFlyingFoxDeviceEndpoint?,
    controlProtocol: OcaControlProtocol,
    identifier: String,
    frames: AsyncThrowingStream<WSFrame, any Error>,
    output: AsyncChannel<WSFrame>
  ) {
    self.output = output
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
    let messagesChannel = AsyncThrowingChannel<Ocp1MessageList, Error>()
    _messages = messagesChannel
    receiveMessageTask = Task {
      // consecutive frame payloads are a byte stream (AES70-3 8.4.3.4.4, AES70-4
      // 10.4.3.4.4), so one stream reader spans frames: a frame may hold several
      // PDUs, or part of one
      let reader = controlProtocol.makeReader(
        preservesPduBoundaries: false,
        maximumPduSize: maximumPduSize
      )
      nonisolated(unsafe) var frames = FrameReader(frames, text: usesTextFrames)
      // a pong or a close frame takes the same handoff as a PDU, so a peer that pings
      // without reading stalls only its own reader, in its own socket
      let reply: @Sendable (WSFrame) async -> () = { frame in
        await output.send(frame)
      }
      /// Each failure sends one close frame. AES70-3 8.4.3.4.4: on OCP.1 a text frame
      /// closes with 1011 (UNEXPECTED), a malformed message with 1007 (BAD_DATA).
      /// AES70-4 10.4.3.4.4: on OCP.2 a binary frame closes with 1003, a malformed
      /// message with 1007, an over-long one with 1009.
      func fail(_ code: WSCloseCode, _ error: Error) async {
        await reply(.close(code: code))
        messagesChannel.fail(error)
      }
      while true {
        let pdu: Data
        do {
          // a whole frame per read, whatever is asked for; the reader keeps the rest
          pdu = try await reader.nextPdu(read: { _, _ in
            try await frames.nextPayload(replying: reply)
          })
        } catch Ocp1Error.notConnected {
          messagesChannel.finish()
          return
        } catch is WSProtocolError {
          await fail(.protocolError, Ocp1Error.invalidMessageType)
          return
        } catch Ocp1Error.invalidMessageType {
          await fail(usesTextFrames ? .unsupportedData : .unexpected, Ocp1Error.invalidMessageType)
          return
        } catch Ocp1Error.invalidPduSize {
          // AES70-3 has no code for an over-long PDU, which cannot be framed: bad data
          await fail(
            usesTextFrames ? .messageTooBig : .invalidFramePayload,
            Ocp1Error.invalidPduSize
          )
          return
        } catch Ocp1Error.invalidSyncValue {
          await fail(.invalidFramePayload, Ocp1Error.invalidSyncValue)
          return
        } catch {
          messagesChannel.fail(error)
          return
        }
        do {
          let messageList = try Ocp1MessageList(
            messagePduData: pdu,
            controlProtocol: controlProtocol
          )
          await messagesChannel.send(messageList)
        } catch {
          await fail(.invalidFramePayload, error)
          return
        }
      }
    }
  }

  /// Zero until the controller negotiates one, as on the other stream transports: SwiftOCA's
  /// WebSocket client sends no keepalives. A peer that stops reading is expired by the write
  /// backlog budget, since a send here waits on the socket.
  package var heartbeatTime = Duration.seconds(0) {
    didSet {
      heartbeatTimeDidChange(from: oldValue)
    }
  }

  package func sendOcp1EncodedData(_ data: Data) async throws {
    let opcode: WSFrame.Opcode = _usesTextFrames ? .text : .binary
    try await send(WSFrame(fin: true, opcode: opcode, mask: nil, payload: data))
  }

  /// Hands `frame` to the server, which takes it only when it is about to write it, so no
  /// more than one frame waits here however far behind the peer is. The wait ends with
  /// `notConnected` once the connection has gone, whichever side ended it.
  private func send(_ frame: WSFrame) async throws {
    guard !isClosed.load(ordering: .acquiring) else { throw Ocp1Error.notConnected }
    await output.send(frame)
    guard !isClosed.load(ordering: .acquiring) else { throw Ocp1Error.notConnected }
  }

  /// Ends sending: a send waiting on the handoff resumes and throws, and later ones throw at
  /// once. The server calls this when its connection has ended, before the controller is
  /// removed, so that no sender hangs on a socket nothing will write to again.
  nonisolated func endSending() {
    isClosed.store(true, ordering: .releasing)
    output.finish()
  }

  package func close() async {
    endSending()
    receiveMessageTask?.cancel()
    receiveMessageTask = nil
    _messages.finish()

    keepAliveTask?.cancel()
    keepAliveTask = nil
  }

  deinit {
    receiveMessageTask?.cancel()
    keepAliveTask?.cancel()
    _messages.finish()
    endSending()
  }

  package nonisolated var description: String {
    "\(type(of: self))(address: \(identifier))"
  }
}

private extension WSCloseCode {
  /// AES70-3's UNEXPECTED, registered by RFC 6455 as Internal Error
  static let unexpected = WSCloseCode(1011, reason: "Unexpected")
}

/// A frame RFC 6455 does not allow where it came: closed with 1002
private struct WSProtocolError: Error {}

/// Reads the peer's frames as one byte stream, answering pings and echoing its close
/// frame itself, so that nothing but the socket buffers a frame it has not asked for.
private struct FrameReader {
  private var frames: AsyncThrowingStream<WSFrame, any Error>.AsyncIterator
  private let text: Bool
  /// the opcode of a fragmented message in progress, which its continuation frames share
  private var fragmented: WSFrame.Opcode?

  init(_ frames: AsyncThrowingStream<WSFrame, any Error>, text: Bool) {
    self.frames = frames.makeAsyncIterator()
    self.text = text
  }

  /// The next frame's payload, requiring text frames on OCP.2 and binary on OCP.1. An
  /// empty frame adds nothing to the byte stream, so it is skipped rather than returned,
  /// which the reader would take for EOF. `reply` sends the peer a pong or its close frame.
  mutating func nextPayload(replying reply: (WSFrame) async -> ()) async throws -> Data {
    while true {
      guard let frame = try await frames.next() else {
        throw Ocp1Error.notConnected
      }
      // RFC 6455 5.2 and 5.5: no extension is negotiated, and a control frame is not
      // fragmented and carries at most 125 bytes. FlyingFox has unmasked the payload
      // and does not say whether the peer masked it, so that is not checked here.
      guard !frame.rsv1, !frame.rsv2, !frame.rsv3 else { throw WSProtocolError() }
      var opcode = frame.opcode
      switch opcode {
      case .ping, .pong, .close:
        guard frame.fin, frame.payload.count <= 125 else { throw WSProtocolError() }
      default:
        break
      }
      switch opcode {
      case .ping:
        var pong = frame
        pong.opcode = .pong
        await reply(pong)
        continue
      case .pong:
        continue
      case .close:
        await reply(Self.closeFrame(echoing: frame.payload))
        throw Ocp1Error.notConnected
      case .continuation:
        guard let first = fragmented else { throw WSProtocolError() }
        opcode = first
      case .text, .binary:
        guard fragmented == nil else { throw WSProtocolError() }
      default:
        throw WSProtocolError()
      }
      fragmented = frame.fin ? nil : opcode
      guard opcode == (text ? .text : .binary) else {
        throw Ocp1Error.invalidMessageType
      }
      if frame.payload.isEmpty { continue }
      return frame.payload
    }
  }

  /// The close frame to answer a peer's with (RFC 6455 5.5.1): its own status code, or
  /// none if it sent none. A one-byte payload, a code that only an endpoint may report
  /// to itself (1005, 1006, 1015), or a reason that is not UTF-8 (7.4.1) is answered 1002.
  private static func closeFrame(echoing payload: Data) -> WSFrame {
    guard payload.count != 1 else { return .close(code: .protocolError) }
    guard payload.count >= 2 else {
      return WSFrame(fin: true, opcode: .close, mask: nil, payload: Data())
    }
    let code = payload.prefix(2).reduce(UInt16(0)) { $0 << 8 | UInt16($1) }
    guard ![1005, 1006, 1015].contains(code),
          let reason = String(validating: payload.dropFirst(2), as: UTF8.self)
    else {
      return .close(code: .protocolError)
    }
    return .close(code: WSCloseCode(code, reason: reason))
  }
}

#endif
