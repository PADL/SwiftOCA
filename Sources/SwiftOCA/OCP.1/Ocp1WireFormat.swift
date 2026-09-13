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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// AES70-3 binary framing: a sync byte, a 9-byte header, then length-prefixed
/// messages; the framing itself lives on `OcaControlProtocol`.
///
/// Reads the sync byte and header, then the number of bytes the header declares.
/// On a message-oriented transport the first read returns the whole PDU and the
/// second is skipped.
///
/// On a stream transport a read may return more than was asked for: a WebSocket
/// hands over a whole frame, and consecutive binary frames are a byte stream that
/// may hold several PDUs, or part of one (AES70-3 8.4.3.4.4). The bytes past the
/// PDU are kept for the next.
package final class Ocp1PduReader: OcaPduReader {
  private let isMessageOriented: Bool
  private let maximumPduSize: Int
  /// bytes read on a stream transport but not yet returned, from `offset`
  private var buffer = Data()
  private var offset = 0

  package init(isMessageOriented: Bool, maximumPduSize: Int) {
    self.isMessageOriented = isMessageOriented
    self.maximumPduSize = maximumPduSize
  }

  package func nextPdu(
    read: (_ count: Int, _ awaitingAllRead: Bool) async throws -> Data
  ) async throws -> Data {
    guard isMessageOriented else {
      return try await nextStreamPdu(read: read)
    }

    var messagePduData = try await read(OcaConnection.MinimumPduSize, true)

    guard messagePduData.count > 0 else {
      throw Ocp1Error.notConnected
    }
    guard messagePduData.count >= OcaConnection.MinimumPduSize else {
      throw Ocp1Error.pduTooShort
    }

    let bytesLeft = try pduLength(messagePduData, at: 0) - messagePduData.count
    if bytesLeft > 0 {
      messagePduData += try await read(bytesLeft, true)
    }

    return messagePduData
  }

  private func nextStreamPdu(
    read: (_ count: Int, _ awaitingAllRead: Bool) async throws -> Data
  ) async throws -> Data {
    // read only what is not already buffered, so a PDU left over from an earlier
    // read, or a whole frame, needs no further call
    if buffer.count - offset < OcaConnection.MinimumPduSize {
      try await fill(OcaConnection.MinimumPduSize, read: read)
    }
    let length = try pduLength(buffer, at: offset)
    if buffer.count - offset < length {
      try await fill(length, read: read)
    }

    let data = buffer
    let start = offset
    // the common case, one read or frame holding exactly one PDU, needs no copy
    if start == 0, data.count == length {
      buffer = Data()
      return data
    }
    let pduStart = data.startIndex + start
    let pdu = Data(data[pduStart..<(pduStart + length)])
    if start + length == data.count {
      buffer = Data()
      offset = 0
    } else {
      offset = start + length
    }
    return pdu
  }

  /// Reads until at least `count` bytes are buffered.
  private func fill(
    _ count: Int,
    read: (_ count: Int, _ awaitingAllRead: Bool) async throws -> Data
  ) async throws {
    while buffer.count - offset < count {
      let chunk = try await read(count - (buffer.count - offset), true)
      guard !chunk.isEmpty else {
        throw Ocp1Error.notConnected
      }
      // discard the PDUs already returned only when more must be read, so a read
      // holding many PDUs is not copied once per PDU
      if offset > 0 {
        buffer = Data(buffer[(buffer.startIndex + offset)...])
        offset = 0
      }
      if buffer.isEmpty {
        buffer = chunk
      } else {
        buffer.append(chunk)
      }
    }
  }

  /// The length, sync byte included, of the PDU whose header starts `offset` bytes
  /// into `data`, which must hold at least `MinimumPduSize` bytes from there.
  private func pduLength(_ data: Data, at offset: Int) throws -> Int {
    // just parse enough of the protocol in order to read rest of message
    // `syncVal: OcaUint8` || `protocolVersion: OcaUint16` || `pduSize: OcaUint32`
    guard data[data.startIndex + offset] == Ocp1SyncValue else {
      throw Ocp1Error.invalidSyncValue
    }
    let pduSize: OcaUint32 = data.decodeInteger(index: offset + 3)
    guard pduSize >= (OcaConnection.MinimumPduSize - 1) else { // doesn't include sync byte
      throw Ocp1Error.invalidPduSize
    }
    // compared without converting, so a size too large for Int on a 32-bit platform is
    // rejected rather than trapping
    guard pduSize <= maximumPduSize, pduSize < Int.max else {
      throw Ocp1Error.invalidPduSize
    }
    return Int(pduSize) + 1
  }
}
