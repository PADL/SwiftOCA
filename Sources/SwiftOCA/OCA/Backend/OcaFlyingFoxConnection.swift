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

@available(*, deprecated, renamed: "OcaFlyingFoxConnection")
public typealias Ocp1FlyingFoxConnection = OcaFlyingFoxConnection

/// A client-side OCP.1 or OCP.2 connection over WebSockets.
///
/// WebSocket ping/pong frames handle connection liveness, so no keepalive
/// (heartbeat) messages are required by default; `heartbeatTime` is `.zero` unless
/// the options override it. OCP.1 travels in binary frames with the `AES70-OCP.1`
/// subprotocol (AES70-3 8.4.3.4), OCP.2 in text frames with the `AES70-OCP.2`
/// subprotocol (AES70-4 10.4.3.4).
public final class OcaFlyingFoxConnection: OcaConnection {
  private let url: URL
  private var webSocketTask: URLSessionWebSocketTask?
  private var session: URLSession?

  public init(
    url: URL,
    options: OcaConnectionOptions = OcaConnectionOptions()
  ) {
    self.url = url
    super.init(options: options)
  }

  public convenience init(
    host: String,
    port: UInt16,
    options: OcaConnectionOptions = OcaConnectionOptions()
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

    let session = URLSession(configuration: .default)
    self.session = session
    let task: URLSessionWebSocketTask = if let subprotocol = controlProtocol.webSocketSubprotocol {
      session.webSocketTask(with: url, protocols: [subprotocol])
    } else {
      session.webSocketTask(with: url)
    }
    task.maximumMessageSize = options.maximumPduSize
    webSocketTask = task
    task.resume()

    do {
      try await super.connectDevice()
    } catch {
      _cleanupConnection()
      throw error
    }
  }

  private func _cleanupConnection() {
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    webSocketTask = nil
    session?.invalidateAndCancel()
    session = nil
  }

  override public func disconnectDevice() async throws {
    _cleanupConnection()
    try await super.disconnectDevice()
  }

  /// One frame per read, whatever `length` and `awaitingAllRead`. The reader keeps what
  /// it does not use, as a frame may hold several PDUs or part of one (AES70-3 8.4.3.4.4,
  /// AES70-4 10.4.3.4.4).
  override public func read(_ length: Int, awaitingAllRead: Bool) async throws -> Data {
    guard let webSocketTask else {
      throw Ocp1Error.notConnected
    }
    let usesTextFrames = controlProtocol.webSocketUsesTextFrames
    while true {
      let message: URLSessionWebSocketTask.Message
      do {
        message = try await withTaskCancellationHandler {
          try await webSocketTask.receive()
        } onCancel: {
          // URLSessionWebSocketTask.receive() does not reliably observe Swift task
          // cancellation. Closing the captured transport generation unblocks the
          // monitor's task group so its reconnect path can run.
          webSocketTask.cancel(with: .normalClosure, reason: nil)
        }
      } catch {
        throw Ocp1Error.notConnected
      }
      switch message {
      case let .data(data):
        guard !usesTextFrames else {
          webSocketTask.cancel(with: .unsupportedData, reason: nil)
          throw Ocp1Error.invalidMessageType
        }
        if !data.isEmpty { return data }
      case let .string(string):
        guard usesTextFrames else {
          webSocketTask.cancel(with: .internalServerError, reason: nil)
          throw Ocp1Error.invalidMessageType
        }
        if !string.isEmpty { return Data(string.utf8) }
      @unknown default:
        continue
      }
    }
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
