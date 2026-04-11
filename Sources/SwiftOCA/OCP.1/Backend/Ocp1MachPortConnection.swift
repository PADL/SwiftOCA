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

#if canImport(Darwin)

import Darwin.Mach
import Foundation

/// OCP.1 connection using Mach ports for fast local IPC between processes.
///
/// The connection discovers the device via a bootstrap service name, performs
/// a handshake to exchange dedicated send/receive ports, then exchanges OCP.1
/// PDUs as Mach messages.
public final class Ocp1MachPortConnection: Ocp1Connection {
  private let serviceName: String

  /// send right to the device's per-controller receive port
  private var serverPort: mach_port_t = .init(0)
  /// our local receive port handle
  private var clientHandle: Ocp1MachPortHandle?
  /// serial queue for blocking mach_msg receive calls
  private var receiveQueue: DispatchQueue?

  public init(
    serviceName: String,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) {
    self.serviceName = serviceName
    super.init(options: options)
  }

  override public nonisolated var connectionPrefix: String {
    "\(OcaMachPortConnectionPrefix)/\(serviceName)"
  }

  override public var heartbeatTime: Duration {
    .seconds(1)
  }

  override public var isDatagram: Bool {
    true
  }

  private func _cleanupConnection() {
    if serverPort != mach_port_t(0) {
      try? clientHandle?.sendDisconnect(to: serverPort)
      Ocp1MachPortHandle.deallocateSendRight(serverPort)
      serverPort = mach_port_t(0)
    }
    clientHandle?.destroy()
    clientHandle = nil
    receiveQueue = nil
  }

  override public func connectDevice() async throws {
    _cleanupConnection()

    // 1. Look up the device's listener port via bootstrap
    let listenerPort = try Ocp1MachPortBootstrap.lookUp(serviceName: serviceName)
    defer { Ocp1MachPortHandle.deallocateSendRight(listenerPort) }

    // 2. Allocate our receive port
    let handle = try Ocp1MachPortHandle.allocateReceivePort()

    // 3. Create a send right to transfer to the device
    let clientSendRight = try handle.makeSendRight()

    // 4. Send connect message with our port, using a temporary reply port
    let replyHandle = try Ocp1MachPortHandle.allocateReceivePort()

    do {
      try handle.sendConnect(
        to: listenerPort,
        replyPort: replyHandle.port,
        transferPort: clientSendRight
      )
    } catch {
      replyHandle.destroy()
      handle.destroy()
      throw error
    }

    // 5. Wait for connectReply with timeout
    let timeoutMs = mach_msg_timeout_t(options.connectionTimeout.asMilliseconds)
    let replyEnvelope: Ocp1MachPortEnvelope
    do {
      replyEnvelope = try replyHandle.receive(timeout: timeoutMs)
    } catch {
      replyHandle.destroy()
      handle.destroy()
      throw error
    }
    replyHandle.destroy()

    guard replyEnvelope.kind == .connectReply,
          replyEnvelope.transferredPort != mach_port_t(0)
    else {
      replyEnvelope.dispose()
      handle.destroy()
      throw Ocp1Error.notConnected
    }

    // 6. Commit state — handshake succeeded
    clientHandle = handle
    serverPort = replyEnvelope.transferredPort

    // 7. Create the receive queue for blocking mach_msg
    receiveQueue = DispatchQueue(label: "com.padl.SwiftOCA.machReceive.\(serviceName)")

    try await super.connectDevice()
  }

  override public func disconnectDevice() async throws {
    _cleanupConnection()
    try await super.disconnectDevice()
  }

  override public func read(_ length: Int) async throws -> Data {
    guard let handle = clientHandle, let queue = receiveQueue else {
      throw Ocp1Error.notConnected
    }
    return try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          while true {
            let envelope = try handle.receive()
            switch envelope.kind {
            case .data:
              continuation.resume(returning: envelope.payload)
              return
            case .disconnect:
              continuation.resume(throwing: Ocp1Error.notConnected)
              return
            case .connectReply, .connect:
              envelope.dispose()
              continue
            }
          }
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  override public func write(_ data: Data) async throws -> Int {
    guard serverPort != mach_port_t(0), let handle = clientHandle else {
      throw Ocp1Error.notConnected
    }
    try handle.sendData(data, to: serverPort)
    return data.count
  }
}

private extension Duration {
  var asMilliseconds: Int64 {
    let (seconds, attoseconds) = components
    return seconds * 1000 + attoseconds / 1_000_000_000_000_000
  }
}

#endif
