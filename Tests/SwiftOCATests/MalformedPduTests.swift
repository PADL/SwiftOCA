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
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
import XCTest

/// PDUs arrive unvalidated from the network — a datagram endpoint hands a whole
/// attacker-sized datagram straight to the decoder — so every malformation here
/// must surface as a thrown `Ocp1Error`. Anything that traps instead is a
/// remotely triggerable denial of service.
final class MalformedPduTests: XCTestCase {
  /// An otherwise well-formed, parameterless command, 17 bytes long.
  private func emptyCommand(handle: OcaUint32 = 1) -> [UInt8] {
    var bytes: [UInt8] = []
    bytes += withUnsafeBytes(of: UInt32(17).bigEndian) { Array($0) } // commandSize
    bytes += withUnsafeBytes(of: handle.bigEndian) { Array($0) } // handle
    bytes += withUnsafeBytes(of: UInt32(100).bigEndian) { Array($0) } // targetONo
    bytes += [0, 1, 0, 1] // methodID
    bytes += [0] // parameterCount
    return bytes
  }

  private func pdu(
    syncValue: UInt8 = Ocp1SyncValue,
    protocolVersion: UInt16 = 1,
    pduSize: UInt32? = nil,
    type: OcaMessageType,
    messageCount: UInt16,
    body: [UInt8]
  ) -> Data {
    var bytes: [UInt8] = [syncValue]
    bytes += withUnsafeBytes(of: protocolVersion.bigEndian) { Array($0) }
    // `pduSize` counts everything after the sync byte
    let size = pduSize ?? UInt32(Ocp1Header.HeaderSize + body.count)
    bytes += withUnsafeBytes(of: size.bigEndian) { Array($0) }
    bytes += [type.rawValue]
    bytes += withUnsafeBytes(of: messageCount.bigEndian) { Array($0) }
    bytes += body
    return Data(bytes)
  }

  private func assertThrows(
    _ data: Data,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(
      try Ocp1Connection.decodeOcp1MessagePdu(from: data),
      message,
      file: file,
      line: line
    ) { error in
      XCTAssertTrue(error is Ocp1Error, "expected Ocp1Error, got \(error)", file: file, line: line)
    }
  }

  /// `messageCount` claims more messages than the PDU carries. Previously
  /// trapped on a `precondition` once the cursor ran past the buffer.
  func testMessageCountExceedsMessagesPresent() {
    assertThrows(
      pdu(type: .ocaCmd, messageCount: 5, body: emptyCommand()),
      "overclaimed messageCount must throw, not trap"
    )
  }

  /// `pduSize` declares more bytes than were delivered. Previously the bound
  /// check was off by two, letting a keep-alive slice run past the buffer end.
  func testPduSizeOverrunsDeliveredBuffer() {
    let body = emptyCommand()
    for excess in UInt32(1)...4 {
      assertThrows(
        pdu(
          pduSize: UInt32(Ocp1Header.HeaderSize + body.count) + excess,
          type: .ocaCmd,
          messageCount: 1,
          body: body
        ),
        "pduSize \(excess) byte(s) beyond the buffer must throw"
      )
    }
  }

  /// The same overrun, on the keep-alive path, which takes the remainder of the
  /// PDU rather than a sized message.
  func testKeepAlivePduSizeOverrunsDeliveredBuffer() {
    for excess in UInt32(1)...4 {
      assertThrows(
        pdu(
          pduSize: UInt32(Ocp1Header.HeaderSize + 2) + excess,
          type: .ocaKeepAlive,
          messageCount: 1,
          body: [0x00, 0x05]
        ),
        "keep-alive pduSize \(excess) byte(s) beyond the buffer must throw"
      )
    }
  }

  /// A message whose declared size extends past the end of the enclosing PDU.
  func testMessageSizeOverrunsPdu() {
    var body = emptyCommand()
    body[0..<4] = ArraySlice(withUnsafeBytes(of: UInt32(1024).bigEndian) { Array($0) })
    assertThrows(
      pdu(type: .ocaCmd, messageCount: 1, body: body),
      "message larger than its PDU must throw"
    )
  }

  /// A declared message size smaller than the size field itself would otherwise
  /// leave the cursor stationary and spin.
  func testMessageSizeSmallerThanSizeField() {
    for declared in UInt32(0)...3 {
      var body = emptyCommand()
      body[0..<4] = ArraySlice(withUnsafeBytes(of: declared.bigEndian) { Array($0) })
      assertThrows(
        pdu(type: .ocaCmd, messageCount: 1, body: body),
        "message size of \(declared) must throw"
      )
    }
  }

  /// A message that is sized correctly but truncated mid-field.
  func testTruncatedCommand() {
    for length in 4..<17 {
      var body = Array(emptyCommand().prefix(length))
      body[0..<4] = ArraySlice(withUnsafeBytes(of: UInt32(length).bigEndian) { Array($0) })
      assertThrows(
        pdu(type: .ocaCmd, messageCount: 1, body: body),
        "command truncated to \(length) bytes must throw"
      )
    }
  }

  /// `pduSize` smaller than the fixed header.
  func testPduSizeBelowHeaderSize() {
    for size in UInt32(0)..<UInt32(Ocp1Header.HeaderSize) {
      assertThrows(
        pdu(pduSize: size, type: .ocaCmd, messageCount: 0, body: []),
        "pduSize \(size) below header size must throw"
      )
    }
  }

  func testEmptyAndTruncatedHeaders() {
    let wellFormed = pdu(type: .ocaCmd, messageCount: 1, body: emptyCommand())
    for length in 0..<(1 + Ocp1Header.HeaderSize) {
      assertThrows(
        wellFormed.prefix(length),
        "PDU truncated to \(length) bytes must throw"
      )
    }
  }

  func testBadSyncValue() {
    assertThrows(
      pdu(syncValue: 0x00, type: .ocaCmd, messageCount: 1, body: emptyCommand()),
      "bad sync value must throw"
    )
  }

  func testUnsupportedProtocolVersion() {
    assertThrows(
      pdu(protocolVersion: 0, type: .ocaCmd, messageCount: 1, body: emptyCommand()),
      "protocol version below 1 must throw"
    )
  }

  /// A keep-alive PDU that is neither the 2-byte nor the 4-byte variant.
  func testKeepAliveWithUnexpectedLength() {
    for length in [0, 1, 3, 5, 8] {
      assertThrows(
        pdu(
          type: .ocaKeepAlive,
          messageCount: 1,
          body: [UInt8](repeating: 0, count: length)
        ),
        "keep-alive of \(length) bytes must throw"
      )
    }
  }

  /// Every one-byte truncation of a well-formed multi-message PDU. None may
  /// trap, whatever the header happens to claim about the bytes that are gone.
  func testEveryTruncationOfWellFormedPdu() throws {
    let commands = [
      Ocp1Command(handle: 1, targetONo: 100, methodID: "1.1"),
      Ocp1Command(
        handle: 2,
        targetONo: 200,
        methodID: "3.5",
        parameters: Ocp1Parameters(parameterCount: 1, parameterData: Data([0xFF, 0xFE]))
      ),
    ]
    let wellFormed: Data = try Ocp1Connection.encodeOcp1MessagePdu(commands, type: .ocaCmd)

    // the intact PDU still decodes
    let (type, messages) = try Ocp1Connection.decodeOcp1MessagePdu(from: wellFormed)
    XCTAssertEqual(type, .ocaCmd)
    XCTAssertEqual(messages.count, 2)

    for length in 0..<wellFormed.count {
      assertThrows(
        wellFormed.prefix(length),
        "PDU truncated to \(length) of \(wellFormed.count) bytes must throw"
      )
    }
  }

  /// Random corruption of a well-formed PDU: any byte may be garbage, but the
  /// decoder must always either succeed or throw.
  func testFuzzedPdus() throws {
    let command = Ocp1Command(
      handle: 1,
      targetONo: 5000,
      methodID: "2.6",
      parameters: Ocp1Parameters(parameterCount: 1, parameterData: Data([0x01, 0x02]))
    )
    let wellFormed: Data = try Ocp1Connection.encodeOcp1MessagePdu([command], type: .ocaCmdRrq)

    var generator = SystemRandomNumberGenerator()
    for _ in 0..<20000 {
      var corrupted = [UInt8](wellFormed)
      for _ in 0..<Int.random(in: 1...4, using: &generator) {
        let index = Int.random(in: 0..<corrupted.count, using: &generator)
        corrupted[index] = UInt8.random(in: .min ... .max, using: &generator)
      }
      // truncate sometimes, to mix length and content corruption
      if Bool.random(using: &generator) {
        corrupted = Array(corrupted.prefix(Int.random(in: 0...corrupted.count, using: &generator)))
      }
      do {
        _ = try Ocp1Connection.decodeOcp1MessagePdu(from: Data(corrupted))
      } catch is Ocp1Error {
        // expected for malformed input
      } catch {
        XCTFail("decoder threw non-Ocp1Error \(error) for \(Data(corrupted).hexString)")
      }
    }
  }
}
