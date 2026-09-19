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

// macOS-only, not Darwin-wide: see Ocp1MachPortSupport.swift.
#if os(macOS)

import Darwin.Mach
import Foundation

package let Ocp1MaximumMachPortPduSize = 1024 * 1024

/// OCP.1 connection using Mach ports for fast local IPC between processes.
///
/// The connection discovers the device via a bootstrap service name, performs
/// a handshake to exchange dedicated send/receive ports, then exchanges OCP.1
/// PDUs as Mach messages.
public final class Ocp1MachPortConnection: OcaConnection {
  private let serviceName: String

  /// send right to the device's per-controller receive port
  private var serverPort: mach_port_t = .init(0)
  /// our local receive port handle
  private var clientHandle: Ocp1MachPortHandle?
  /// serial queue for blocking mach_msg receive calls
  private var receiveQueue: DispatchQueue?

  public init(
    serviceName: String,
    options: OcaConnectionOptions = OcaConnectionOptions()
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

  /// payloads too large to send inline go out of line, so no MTU applies: bounded only so
  /// that a peer cannot have us accept an arbitrarily large PDU
  override public var maximumDatagramPduSize: Int {
    Ocp1MaximumMachPortPduSize
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

  override public func read(_ length: Int, awaitingAllRead: Bool) async throws -> Data {
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
              continuation.resume(returning: _trimmingAlignmentPadding(envelope.payload))
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

/// A data message's payload, less any alignment padding after its PDU.
///
/// A Mach message is padded to a multiple of 4 bytes and the receiver learns only the
/// padded size, so an inline payload can end with up to 3 zero bytes that are not part of
/// the PDU. Left in, they would fail the check that a packet holds exactly one PDU.
private func _trimmingAlignmentPadding(_ payload: Data) -> Data {
  guard payload.count >= OcaConnection.MinimumPduSize,
        payload[payload.startIndex] == Ocp1SyncValue
  else {
    return payload
  }
  // `syncVal: OcaUint8` || `protocolVersion: OcaUint16` || `pduSize: OcaUint32`, where
  // `pduSize` does not count the sync byte
  let pduSize: OcaUint32 = payload.decodeInteger(index: 3)
  guard let size = Int(exactly: pduSize), size < Int.max else {
    return payload
  }
  let pduLength = size + 1
  guard pduLength < payload.count, payload.count - pduLength < 4,
        payload[(payload.startIndex + pduLength)...].allSatisfy({ $0 == 0 })
  else {
    return payload
  }
  return payload.prefix(pduLength)
}

private extension Duration {
  var asMilliseconds: Int64 {
    let (seconds, attoseconds) = components
    return seconds * 1000 + attoseconds / 1_000_000_000_000_000
  }
}

#endif
