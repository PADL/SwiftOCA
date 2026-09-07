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

#if NonEmbeddedBuild
import Foundation

/// AES70-4 framing is one JSON object per PDU, terminated by a newline; the framing
/// itself lives on `OcaControlProtocol`.
///
/// Reads newline-delimited PDUs. On a stream, bytes after a newline are kept for the
/// next PDU; on a message-oriented transport each read is one PDU.
package final class Ocp2PduReader: OcaPduReader {
  private static let newline = UInt8(ascii: "\n")
  private static let carriageReturn = UInt8(ascii: "\r")
  private static let readChunk = 64 * 1024

  private let isMessageOriented: Bool
  private let maximumPduSize: Int
  private var buffer = [UInt8]()
  /// index up to which `buffer` is known to hold no newline
  private var scanned = 0

  package init(isMessageOriented: Bool, maximumPduSize: Int) {
    self.isMessageOriented = isMessageOriented
    self.maximumPduSize = maximumPduSize
  }

  package func nextPdu(
    read: (_ count: Int, _ awaitingAllRead: Bool) async throws -> Data
  ) async throws -> Data {
    if isMessageOriented {
      // read past the cap (a PDU may be terminated, so allow for CR LF) rather
      // than up to it: a frame the transport would otherwise truncate to exactly
      // `maximumPduSize` is indistinguishable from one that fits, and would be
      // decoded as a malformed PDU instead of being rejected as oversized
      let message = try await read(maximumPduSize + 2, false)
      guard !message.isEmpty else { throw Ocp1Error.notConnected }
      let pdu = Self.trimmed(message)
      guard pdu.count <= maximumPduSize else { throw Ocp1Error.invalidPduSize }
      return pdu
    }

    while true {
      if let index = buffer[scanned...].firstIndex(of: Self.newline) {
        // a transport may hand over more than was asked for (a whole WebSocket
        // frame), so the cap applies to the PDU itself, not to the read size
        guard index <= maximumPduSize else { throw Ocp1Error.invalidPduSize }
        var line = Array(buffer[..<index])
        buffer.removeSubrange(...index)
        scanned = 0
        if line.last == Self.carriageReturn {
          line.removeLast()
        }
        // an empty line between PDUs is tolerated
        if line.isEmpty {
          continue
        }
        return Data(line)
      }
      scanned = buffer.count
      guard buffer.count < maximumPduSize else {
        throw Ocp1Error.invalidPduSize
      }
      let chunk = try await read(min(Self.readChunk, maximumPduSize - buffer.count), false)
      guard !chunk.isEmpty else { throw Ocp1Error.notConnected }
      buffer += chunk
    }
  }

  /// One datagram or frame holds one PDU; strip its terminator and anything after it.
  private static func trimmed(_ message: Data) -> Data {
    if let index = message.firstIndex(of: newline) {
      var end = index
      if end > message.startIndex, message[end - 1] == carriageReturn {
        end -= 1
      }
      return message[message.startIndex..<end]
    }
    return message
  }
}
#endif
