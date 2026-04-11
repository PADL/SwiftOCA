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

/// A client-side OCP.1 connection over WebSockets.
///
/// WebSocket ping/pong frames handle connection liveness, so no OCP.1 keepalive
/// (heartbeat) messages are required. `heartbeatTime` is `.zero`.
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
    "\(OcaWebSocketTcpConnectionPrefix)/\(url.absoluteString)"
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
    let task = session.webSocketTask(with: url)
    task.maximumMessageSize = Int(UInt16.max)
    webSocketTask = task
    task.resume()

    receiveTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        do {
          let message = try await task.receive()
          switch message {
          case let .data(data):
            receivedMessageContinuation?.yield(data)
          case let .string(string):
            if let data = string.data(using: .utf8) {
              receivedMessageContinuation?.yield(data)
            }
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

  override public func read(_ length: Int) async throws -> Data {
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
    try await webSocketTask.send(.data(data))
    return data.count
  }
}

#endif
