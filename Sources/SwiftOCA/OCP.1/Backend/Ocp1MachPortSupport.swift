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
import Synchronization
import SystemPackage

// OcaMachPortConnectionPrefix is defined in Ocp1Connection.swift

// MARK: - Swift equivalents of Mach macros

private let _MACH_PORT_NULL = mach_port_t(0)

private func _MACH_MSGH_BITS(
  _ remote: mach_msg_bits_t,
  _ local: mach_msg_bits_t
) -> mach_msg_bits_t {
  remote | (local << 8)
}

private let _MACH_MSGH_BITS_COMPLEX = mach_msg_bits_t(0x80000000)
private let _MAX_TRAILER_SIZE = MemoryLayout<mach_msg_max_trailer_t>.size

// MARK: - Transport message kinds

package enum Ocp1MachPortMessageID: mach_msg_id_t {
  case connect = 1
  case connectReply = 2
  case data = 3
  case disconnect = 4
}

// MARK: - Inline vs OOL threshold

/// Payloads up to this size are sent inline in the Mach message body,
/// avoiding the VM mapping overhead of OOL descriptors. Larger payloads
/// use OOL with virtual copy.
private let _inlineThreshold = 4096

// MARK: - Mach message structures for send/receive

// -- OOL (out-of-line) data messages for large payloads --

private struct Ocp1MachOOLDataMessageSend {
  var header: mach_msg_header_t
  var body: mach_msg_body_t
  var payload: mach_msg_ool_descriptor_t

  init(
    remotePort: mach_port_t,
    localPort: mach_port_t,
    id: Ocp1MachPortMessageID,
    address: UnsafeRawPointer,
    size: Int
  ) {
    header = mach_msg_header_t()
    header.msgh_bits = _MACH_MSGH_BITS(
      mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND),
      localPort != _MACH_PORT_NULL ? mach_msg_bits_t(MACH_MSG_TYPE_MAKE_SEND) : 0
    ) | _MACH_MSGH_BITS_COMPLEX
    header.msgh_size = mach_msg_size_t(MemoryLayout<Self>.size)
    header.msgh_remote_port = remotePort
    header.msgh_local_port = localPort
    header.msgh_id = id.rawValue

    body = mach_msg_body_t()
    body.msgh_descriptor_count = 1

    payload = mach_msg_ool_descriptor_t()
    payload.address = UnsafeMutableRawPointer(mutating: address)
    payload.size = mach_msg_size_t(size)
    payload.deallocate = 0
    payload.copy = mach_msg_copy_options_t(MACH_MSG_VIRTUAL_COPY)
    payload.type = mach_msg_descriptor_type_t(MACH_MSG_OOL_DESCRIPTOR)
  }
}

private struct Ocp1MachOOLDataMessageReceive {
  var header: mach_msg_header_t
  var body: mach_msg_body_t
  var payload: mach_msg_ool_descriptor_t
  var trailer: mach_msg_max_trailer_t

  init() {
    header = mach_msg_header_t()
    body = mach_msg_body_t()
    payload = mach_msg_ool_descriptor_t()
    trailer = mach_msg_max_trailer_t()
  }
}

// -- Port transfer messages --

private struct Ocp1MachPortTransferMessageSend {
  var header: mach_msg_header_t
  var body: mach_msg_body_t
  var port: mach_msg_port_descriptor_t

  init(
    remotePort: mach_port_t,
    id: Ocp1MachPortMessageID,
    transferPort: mach_port_t
  ) {
    header = mach_msg_header_t()
    header.msgh_bits = _MACH_MSGH_BITS(
      mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND),
      0
    ) | _MACH_MSGH_BITS_COMPLEX
    header.msgh_size = mach_msg_size_t(MemoryLayout<Self>.size)
    header.msgh_remote_port = remotePort
    header.msgh_local_port = _MACH_PORT_NULL
    header.msgh_id = id.rawValue

    body = mach_msg_body_t()
    body.msgh_descriptor_count = 1

    port = mach_msg_port_descriptor_t()
    port.name = transferPort
    port.disposition = mach_msg_type_name_t(MACH_MSG_TYPE_MOVE_SEND)
    port.type = mach_msg_descriptor_type_t(MACH_MSG_PORT_DESCRIPTOR)
  }
}

private struct Ocp1MachConnectMessageSend {
  var header: mach_msg_header_t
  var body: mach_msg_body_t
  var port: mach_msg_port_descriptor_t

  init(
    remotePort: mach_port_t,
    replyPort: mach_port_t,
    transferPort: mach_port_t
  ) {
    header = mach_msg_header_t()
    header.msgh_bits = _MACH_MSGH_BITS(
      mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND),
      mach_msg_bits_t(MACH_MSG_TYPE_MAKE_SEND)
    ) | _MACH_MSGH_BITS_COMPLEX
    header.msgh_size = mach_msg_size_t(MemoryLayout<Self>.size)
    header.msgh_remote_port = remotePort
    header.msgh_local_port = replyPort
    header.msgh_id = Ocp1MachPortMessageID.connect.rawValue

    body = mach_msg_body_t()
    body.msgh_descriptor_count = 1

    port = mach_msg_port_descriptor_t()
    port.name = transferPort
    port.disposition = mach_msg_type_name_t(MACH_MSG_TYPE_MOVE_SEND)
    port.type = mach_msg_descriptor_type_t(MACH_MSG_PORT_DESCRIPTOR)
  }
}

private struct Ocp1MachPortTransferMessageReceive {
  var header: mach_msg_header_t
  var body: mach_msg_body_t
  var port: mach_msg_port_descriptor_t
  var trailer: mach_msg_max_trailer_t

  init() {
    header = mach_msg_header_t()
    body = mach_msg_body_t()
    port = mach_msg_port_descriptor_t()
    trailer = mach_msg_max_trailer_t()
  }
}

// MARK: - Received envelope

package struct Ocp1MachPortEnvelope: Sendable {
  package let kind: Ocp1MachPortMessageID
  package let payload: Data
  package let transferredPort: mach_port_t
  package let replyPort: mach_port_t

  /// Deallocate any port rights carried by this envelope. Call when
  /// discarding an envelope whose rights are not otherwise consumed.
  package func dispose() {
    Ocp1MachPortHandle.deallocateSendRight(transferredPort)
    Ocp1MachPortHandle.deallocateSendRight(replyPort)
  }
}

// MARK: - Mach port handle wrapper

/// Manages a Mach receive right. Send rights to remote ports are tracked
/// separately by callers (and cleaned up via `deallocateSendRight`).
package final class Ocp1MachPortHandle: Sendable {
  package let port: mach_port_t
  private let destroyed = Mutex(false)

  private init(port: mach_port_t) {
    self.port = port
  }

  /// Allocate a new receive right using swift-system's `Mach.Port`,
  /// then take ownership of the raw name for use with `mach_msg`.
  package static func allocateReceivePort() throws -> Ocp1MachPortHandle {
    let receiveRight = Mach.Port<Mach.ReceiveRight>()
    let name = receiveRight.unguardAndRelinquish()
    // set queue limit
    var limits = mach_port_limits_t(mpl_qlimit: 64)
    _ = withUnsafeMutablePointer(to: &limits) { limitsPtr in
      limitsPtr.withMemoryRebound(
        to: integer_t.self,
        capacity: MemoryLayout<mach_port_limits_t>.size / MemoryLayout<integer_t>.size
      ) { intPtr in
        mach_port_set_attributes(
          mach_task_self_,
          name,
          MACH_PORT_LIMITS_INFO,
          intPtr,
          mach_msg_type_number_t(
            MemoryLayout<mach_port_limits_t>.size / MemoryLayout<integer_t>.size
          )
        )
      }
    }
    return Ocp1MachPortHandle(port: name)
  }

  /// Create a send right for this receive port. Caller is responsible
  /// for deallocating via `deallocateSendRight` or transferring via a
  /// Mach message with `MACH_MSG_TYPE_MOVE_SEND`.
  package func makeSendRight() throws -> mach_port_t {
    let kr = mach_port_insert_right(
      mach_task_self_,
      port,
      port,
      mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND)
    )
    guard kr == KERN_SUCCESS else {
      throw Ocp1Error.status(.deviceError)
    }
    return port
  }

  // MARK: - Sending

  package func sendData(_ data: Data, to remotePort: mach_port_t) throws {
    try data.withUnsafeBytes { buffer in
      guard let baseAddress = buffer.baseAddress else { return }
      if buffer.count <= _inlineThreshold {
        try _sendDataInline(baseAddress, count: buffer.count, to: remotePort)
      } else {
        try _sendDataOOL(baseAddress, count: buffer.count, to: remotePort)
      }
    }
  }

  private func _sendDataInline(
    _ baseAddress: UnsafeRawPointer,
    count: Int,
    to remotePort: mach_port_t
  ) throws {
    let headerSize = MemoryLayout<mach_msg_header_t>.size
    let rawSize = headerSize + count
    // Mach messages must be naturally aligned (multiple of 4 bytes)
    let totalSize = (rawSize + 3) & ~3
    let buffer = UnsafeMutableRawPointer.allocate(
      byteCount: totalSize,
      alignment: MemoryLayout<mach_msg_header_t>.alignment
    )
    defer { buffer.deallocate() }

    buffer.initializeMemory(as: UInt8.self, repeating: 0, count: totalSize)

    let hdr = buffer.assumingMemoryBound(to: mach_msg_header_t.self)
    hdr.pointee.msgh_bits = _MACH_MSGH_BITS(
      mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND),
      0
    )
    hdr.pointee.msgh_size = mach_msg_size_t(rawSize)
    hdr.pointee.msgh_remote_port = remotePort
    hdr.pointee.msgh_local_port = _MACH_PORT_NULL
    hdr.pointee.msgh_id = Ocp1MachPortMessageID.data.rawValue

    buffer.advanced(by: headerSize).copyMemory(from: baseAddress, byteCount: count)

    let kr = mach_msg(
      hdr,
      MACH_SEND_MSG,
      mach_msg_size_t(totalSize),
      0,
      _MACH_PORT_NULL,
      MACH_MSG_TIMEOUT_NONE,
      _MACH_PORT_NULL
    )
    guard kr == MACH_MSG_SUCCESS else {
      throw Ocp1Error.pduSendingFailed
    }
  }

  private func _sendDataOOL(
    _ baseAddress: UnsafeRawPointer,
    count: Int,
    to remotePort: mach_port_t
  ) throws {
    var msg = Ocp1MachOOLDataMessageSend(
      remotePort: remotePort,
      localPort: _MACH_PORT_NULL,
      id: .data,
      address: baseAddress,
      size: count
    )
    let kr = withUnsafeMutablePointer(to: &msg) { msgPtr in
      msgPtr.withMemoryRebound(to: mach_msg_header_t.self, capacity: 1) { hdr in
        mach_msg(
          hdr,
          MACH_SEND_MSG,
          mach_msg_size_t(MemoryLayout<Ocp1MachOOLDataMessageSend>.size),
          0,
          _MACH_PORT_NULL,
          MACH_MSG_TIMEOUT_NONE,
          _MACH_PORT_NULL
        )
      }
    }
    guard kr == MACH_MSG_SUCCESS else {
      throw Ocp1Error.pduSendingFailed
    }
  }

  package func sendConnect(
    to remotePort: mach_port_t,
    replyPort: mach_port_t,
    transferPort: mach_port_t
  ) throws {
    var msg = Ocp1MachConnectMessageSend(
      remotePort: remotePort,
      replyPort: replyPort,
      transferPort: transferPort
    )
    let kr = withUnsafeMutablePointer(to: &msg) { msgPtr in
      msgPtr.withMemoryRebound(to: mach_msg_header_t.self, capacity: 1) { hdr in
        mach_msg(
          hdr,
          MACH_SEND_MSG,
          mach_msg_size_t(MemoryLayout<Ocp1MachConnectMessageSend>.size),
          0,
          _MACH_PORT_NULL,
          MACH_MSG_TIMEOUT_NONE,
          _MACH_PORT_NULL
        )
      }
    }
    guard kr == MACH_MSG_SUCCESS else {
      throw Ocp1Error.pduSendingFailed
    }
  }

  package func sendPortTransfer(
    to remotePort: mach_port_t,
    id: Ocp1MachPortMessageID,
    transferPort: mach_port_t
  ) throws {
    var msg = Ocp1MachPortTransferMessageSend(
      remotePort: remotePort,
      id: id,
      transferPort: transferPort
    )
    let kr = withUnsafeMutablePointer(to: &msg) { msgPtr in
      msgPtr.withMemoryRebound(to: mach_msg_header_t.self, capacity: 1) { hdr in
        mach_msg(
          hdr,
          MACH_SEND_MSG,
          mach_msg_size_t(MemoryLayout<Ocp1MachPortTransferMessageSend>.size),
          0,
          _MACH_PORT_NULL,
          MACH_MSG_TIMEOUT_NONE,
          _MACH_PORT_NULL
        )
      }
    }
    guard kr == MACH_MSG_SUCCESS else {
      throw Ocp1Error.pduSendingFailed
    }
  }

  package func sendDisconnect(to remotePort: mach_port_t) throws {
    var header = mach_msg_header_t()
    header.msgh_bits = _MACH_MSGH_BITS(
      mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND),
      0
    )
    header.msgh_size = mach_msg_size_t(MemoryLayout<mach_msg_header_t>.size)
    header.msgh_remote_port = remotePort
    header.msgh_local_port = _MACH_PORT_NULL
    header.msgh_id = Ocp1MachPortMessageID.disconnect.rawValue

    let kr = withUnsafeMutablePointer(to: &header) { hdr in
      mach_msg(
        hdr,
        MACH_SEND_MSG,
        mach_msg_size_t(MemoryLayout<mach_msg_header_t>.size),
        0,
        _MACH_PORT_NULL,
        MACH_MSG_TIMEOUT_NONE,
        _MACH_PORT_NULL
      )
    }
    guard kr == MACH_MSG_SUCCESS else {
      throw Ocp1Error.pduSendingFailed
    }
  }

  // MARK: - Receiving

  /// Receive a message with no timeout (blocks indefinitely).
  package func receive() throws -> Ocp1MachPortEnvelope {
    try _receive(timeout: MACH_MSG_TIMEOUT_NONE, options: 0)
  }

  /// Receive a message with a timeout in milliseconds.
  /// Throws `Ocp1Error.responseTimeout` if the timeout expires.
  package func receive(timeout: mach_msg_timeout_t) throws -> Ocp1MachPortEnvelope {
    try _receive(timeout: timeout, options: MACH_RCV_TIMEOUT)
  }

  private func _receive(
    timeout: mach_msg_timeout_t,
    options: mach_msg_option_t
  ) throws -> Ocp1MachPortEnvelope {
    let headerSize = MemoryLayout<mach_msg_header_t>.size
    let bufferSize = max(
      MemoryLayout<Ocp1MachOOLDataMessageReceive>.size,
      MemoryLayout<Ocp1MachPortTransferMessageReceive>.size,
      headerSize + _inlineThreshold + _MAX_TRAILER_SIZE
    )
    let alignment = MemoryLayout<mach_msg_header_t>.alignment
    let buffer = UnsafeMutableRawPointer.allocate(
      byteCount: bufferSize,
      alignment: alignment
    )
    defer { buffer.deallocate() }
    buffer.initializeMemory(as: UInt8.self, repeating: 0, count: bufferSize)

    let hdr = buffer.assumingMemoryBound(to: mach_msg_header_t.self)
    let kr = mach_msg(
      hdr,
      MACH_RCV_MSG | MACH_RCV_LARGE | options,
      0,
      mach_msg_size_t(bufferSize),
      port,
      timeout,
      _MACH_PORT_NULL
    )

    if kr == MACH_RCV_TIMED_OUT {
      throw Ocp1Error.responseTimeout
    }
    guard kr == MACH_MSG_SUCCESS else {
      throw Ocp1Error.notConnected
    }

    guard let kind = Ocp1MachPortMessageID(rawValue: hdr.pointee.msgh_id) else {
      mach_msg_destroy(hdr)
      throw Ocp1Error.invalidMessageType
    }

    let replyPort = hdr.pointee.msgh_remote_port
    let isComplex = (hdr.pointee.msgh_bits & _MACH_MSGH_BITS_COMPLEX) != 0

    switch kind {
    case .data:
      if isComplex {
        let msg = buffer.load(as: Ocp1MachOOLDataMessageReceive.self)
        guard msg.body.msgh_descriptor_count == 1,
              msg.payload.type == mach_msg_descriptor_type_t(MACH_MSG_OOL_DESCRIPTOR)
        else {
          mach_msg_destroy(hdr)
          throw Ocp1Error.invalidMessageType
        }
        let payload: Data
        if let address = msg.payload.address, msg.payload.size > 0 {
          payload = Data(bytes: address, count: Int(msg.payload.size))
          vm_deallocate(
            mach_task_self_,
            vm_address_t(bitPattern: address),
            vm_size_t(msg.payload.size)
          )
        } else {
          payload = Data()
        }
        return Ocp1MachPortEnvelope(
          kind: .data,
          payload: payload,
          transferredPort: _MACH_PORT_NULL,
          replyPort: replyPort
        )
      } else {
        let msgSize = Int(hdr.pointee.msgh_size)
        let payloadSize = msgSize - headerSize
        let payload: Data
        if payloadSize > 0 {
          payload = Data(bytes: buffer.advanced(by: headerSize), count: payloadSize)
        } else {
          payload = Data()
        }
        return Ocp1MachPortEnvelope(
          kind: .data,
          payload: payload,
          transferredPort: _MACH_PORT_NULL,
          replyPort: replyPort
        )
      }

    case .connect, .connectReply:
      guard isComplex else {
        throw Ocp1Error.invalidMessageType
      }
      let msg = buffer.load(as: Ocp1MachPortTransferMessageReceive.self)
      guard msg.body.msgh_descriptor_count == 1,
            msg.port.type == mach_msg_descriptor_type_t(MACH_MSG_PORT_DESCRIPTOR)
      else {
        mach_msg_destroy(hdr)
        throw Ocp1Error.invalidMessageType
      }
      return Ocp1MachPortEnvelope(
        kind: kind,
        payload: Data(),
        transferredPort: msg.port.name,
        replyPort: replyPort
      )

    case .disconnect:
      return Ocp1MachPortEnvelope(
        kind: .disconnect,
        payload: Data(),
        transferredPort: _MACH_PORT_NULL,
        replyPort: replyPort
      )
    }
  }

  // MARK: - Lifecycle

  /// Destroy the receive right (and any coalesced send rights).
  package func destroy() {
    let shouldDestroy = destroyed.withLock { destroyed -> Bool in
      guard !destroyed else { return false }
      destroyed = true
      return true
    }
    if shouldDestroy {
      mach_port_destroy(mach_task_self_, port)
    }
  }

  /// Deallocate a send right obtained via `makeSendRight()` or received
  /// in a Mach message port descriptor.
  package static func deallocateSendRight(_ port: mach_port_t) {
    guard port != _MACH_PORT_NULL else { return }
    mach_port_deallocate(mach_task_self_, port)
  }

  deinit {
    destroy()
  }
}

// MARK: - Bootstrap API imports (not exposed to Swift by the Darwin overlay)

@_extern(c, "bootstrap_look_up")
private func _bootstrap_look_up(
  _ bp: mach_port_t,
  _ serviceName: UnsafePointer<CChar>,
  _ sp: UnsafeMutablePointer<mach_port_t>
) -> kern_return_t

@_extern(c, "bootstrap_register")
private func _bootstrap_register(
  _ bp: mach_port_t,
  _ serviceName: UnsafePointer<CChar>,
  _ sp: mach_port_t
) -> kern_return_t

@_extern(c, "bootstrap_check_in")
private func _bootstrap_check_in(
  _ bp: mach_port_t,
  _ serviceName: UnsafePointer<CChar>,
  _ sp: UnsafeMutablePointer<mach_port_t>
) -> kern_return_t

// MARK: - Bootstrap helpers

// bootstrap_port is a global mutable var in the Mach headers, which triggers
// concurrency warnings in Swift 6. It is effectively read-only after process init.
@_extern(c, "bootstrap_port")
private nonisolated(unsafe) var _bootstrapPort: mach_port_t

package enum Ocp1MachPortBootstrap {
  package static func lookUp(serviceName: String) throws -> mach_port_t {
    var port = mach_port_t()
    let kr = _bootstrap_look_up(_bootstrapPort, serviceName, &port)
    guard kr == KERN_SUCCESS else {
      throw Ocp1Error.notConnected
    }
    return port
  }

  package static func register(
    serviceName: String,
    port: mach_port_t
  ) throws {
    let kr = _bootstrap_register(_bootstrapPort, serviceName, port)
    guard kr == KERN_SUCCESS else {
      throw Ocp1Error.status(.deviceError)
    }
  }

  package static func checkIn(serviceName: String) throws -> mach_port_t {
    var port = mach_port_t()
    let kr = _bootstrap_check_in(_bootstrapPort, serviceName, &port)
    guard kr == KERN_SUCCESS else {
      throw Ocp1Error.status(.deviceError)
    }
    return port
  }
}

#endif
