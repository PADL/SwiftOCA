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

#if os(macOS) || os(iOS)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A client-side OCP.1 or OCP.2 connection over WebSockets.
///
/// WebSocket ping/pong frames handle connection liveness, so no keepalive
/// (heartbeat) messages are required by default; `heartbeatTime` is `.zero` unless
/// the options override it. OCP.1 travels in binary frames, OCP.2 in text frames with
/// the `AES70-OCP.2` subprotocol (AES70-4 10.4.3.4).
public final class Ocp1FlyingFoxConnection: Ocp1Connection {
  private let url: URL
  private var webSocketTask: URLSessionWebSocketTask?
  private var session: URLSession?
  private var receivedMessageContinuation: AsyncThrowingStream<Data, Error>.Continuation?
  private var receivedMessageStream: AsyncThrowingStream<Data, Error>?
  private var receiveTask: Task<(), Never>?

  public init(
    url: URL,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) {
    self.url = url
    super.init(options: options)
  }

  public convenience init(
    host: String,
    port: UInt16,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) {
    let url = URL(string: "ws://\(host):\(port)/")!
    self.init(url: url, options: options)
  }

  override public nonisolated var connectionPrefix: String {
    let prefix = _connectionPrefix(
      ocp1: OcaWebSocketTcpConnectionPrefix,
      ocp2: OcaJsonWebSocketTcpConnectionPrefix
    )
    return "\(prefix)/\(url.absoluteString)"
  }

  /// WebSocket ping/pong handles liveness; no OCP.1 keepalive needed.
  override public var heartbeatTime: Duration {
    .zero
  }

  override public var isDatagram: Bool { false }

  override public func connectDevice() async throws {
    // close any existing resources before creating new ones (e.g. during reconnection retries)
    _cleanupConnection()

    let (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
    receivedMessageContinuation = continuation
    receivedMessageStream = stream

    let session = URLSession(configuration: .default)
    self.session = session
    let task: URLSessionWebSocketTask = if let subprotocol = controlProtocol.webSocketSubprotocol {
      session.webSocketTask(with: url, protocols: [subprotocol])
    } else {
      session.webSocketTask(with: url)
    }
    task.maximumMessageSize = controlProtocol.webSocketUsesTextFrames
      ? options.maximumPduSize
      : Int(UInt16.max)
    webSocketTask = task
    task.resume()

    let usesTextFrames = controlProtocol.webSocketUsesTextFrames
    receiveTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        do {
          let message = try await task.receive()
          switch message {
          case let .data(data):
            guard !usesTextFrames else {
              // AES70-4 10.4.3.4.4: OCP.2 travels in text frames only
              task.cancel(with: .unsupportedData, reason: nil)
              receivedMessageContinuation?.finish(throwing: Ocp1Error.notConnected)
              return
            }
            receivedMessageContinuation?.yield(data)
          case let .string(string):
            receivedMessageContinuation?.yield(Data(string.utf8))
          @unknown default:
            break
          }
        } catch {
          receivedMessageContinuation?.finish(throwing: Ocp1Error.notConnected)
          return
        }
      }
    }

    do {
      try await super.connectDevice()
    } catch {
      _cleanupConnection()
      throw error
    }
  }

  private func _cleanupConnection() {
    receiveTask?.cancel()
    receiveTask = nil
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    webSocketTask = nil
    receivedMessageContinuation?.finish()
    receivedMessageContinuation = nil
    receivedMessageStream = nil
    session?.invalidateAndCancel()
    session = nil
  }

  override public func disconnectDevice() async throws {
    _cleanupConnection()
    try await super.disconnectDevice()
  }

  /// One frame per read, whatever `length` and `awaitingAllRead`: the transport is
  /// message-oriented.
  override public func read(_ length: Int, awaitingAllRead: Bool) async throws -> Data {
    guard let receivedMessageStream else {
      throw Ocp1Error.notConnected
    }
    for try await data in receivedMessageStream {
      return data
    }
    throw Ocp1Error.notConnected
  }

  override public func write(_ data: Data) async throws -> Int {
    guard let webSocketTask else {
      throw Ocp1Error.notConnected
    }
    if controlProtocol.webSocketUsesTextFrames {
      try await webSocketTask.send(.string(String(decoding: data, as: UTF8.self)))
    } else {
      try await webSocketTask.send(.data(data))
    }
    return data.count
  }
}

#endif
