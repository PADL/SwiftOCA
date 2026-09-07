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
package final class Ocp1PduReader: OcaPduReader {
  private let maximumPduSize: Int

  package init(maximumPduSize: Int) {
    self.maximumPduSize = maximumPduSize
  }

  package func nextPdu(
    read: (_ count: Int, _ awaitingAllRead: Bool) async throws -> Data
  ) async throws -> Data {
    var messagePduData = try await read(Ocp1Connection.MinimumPduSize, true)

    guard messagePduData.count > 0 else {
      throw Ocp1Error.notConnected
    }

    // just parse enough of the protocol in order to read rest of message
    // `syncVal: OcaUint8` || `protocolVersion: OcaUint16` || `pduSize: OcaUint32`
    guard messagePduData.count >= Ocp1Connection.MinimumPduSize else {
      throw Ocp1Error.pduTooShort
    }
    guard messagePduData[messagePduData.startIndex] == Ocp1SyncValue else {
      throw Ocp1Error.invalidSyncValue
    }

    let pduSize: OcaUint32 = messagePduData.decodeInteger(index: messagePduData.startIndex + 3)
    guard pduSize >= (Ocp1Connection.MinimumPduSize - 1) else { // doesn't include sync byte
      throw Ocp1Error.invalidPduSize
    }
    guard Int(pduSize) <= maximumPduSize else {
      throw Ocp1Error.invalidPduSize
    }

    let bytesLeft = Int(pduSize) + 1 - messagePduData.count
    if bytesLeft > 0 {
      messagePduData += try await read(bytesLeft, true)
    }

    return messagePduData
  }
}
