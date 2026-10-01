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

@_spi(SwiftOCAPrivate) @testable import SwiftOCA
import Testing

@Suite
struct DNSServiceTXTRecordTests {
  /// What the endpoint registrar wrote before the encoding was shared: each entry as
  /// its length byte and `key=value`.
  private func legacyEncoding(_ entries: [(String, String)]) -> [UInt8] {
    entries.flatMap { key, value in
      let keyValue = "\(key)=\(value)".utf8
      return [UInt8(keyValue.count)] + keyValue
    }
  }

  @Test
  func anEndpointRecordIsEncodedAsBefore() {
    let entries = [
      ("txtvers", "1"),
      ("protovers", "3"),
      ("path", "/oca"),
      ("modelGUID", "0ae91b0000000001"),
      ("serialNumber", "MT1A2B"),
    ]
    #expect(DNSServiceTXTRecord.encode(entries) == legacyEncoding(entries))
  }

  @Test
  func entriesKeepTheirOrderAndRoundTrip() {
    let entries = [("api_proto", "http"), ("api_ver", "v1.3"), ("ver_slf", "0"), ("empty", "")]
    let encoded = DNSServiceTXTRecord.encode(entries)
    #expect(encoded.first == UInt8("api_proto=http".utf8.count))
    #expect(DNSServiceTXTRecord.decode(encoded) == [
      "api_proto": "http", "api_ver": "v1.3", "ver_slf": "0", "empty": "",
    ])
  }

  @Test
  func aValueMayContainAnEqualsSign() {
    let encoded = DNSServiceTXTRecord.encode([("path", "/a=b")])
    #expect(DNSServiceTXTRecord.decode(encoded) == ["path": "/a=b"])
  }

  @Test
  func aKeyTheWireFormCannotCarryIsLeftOut() {
    let entries = [("", "x"), ("a=b", "x"), ("caf\u{e9}", "x"), ("tab\t", "x"), ("ok", "y")]
    #expect(DNSServiceTXTRecord.encode(entries) == legacyEncoding([("ok", "y")]))
    #expect(!DNSServiceTXTRecord.isValidKey(String(repeating: "k", count: 3) + "="))
    #expect(DNSServiceTXTRecord.isValidKey("ver_slf"))
  }

  @Test
  func aLongValueIsCutToFitAtACharacterBoundary() {
    // 250 bytes of key and `=`, then two-byte characters: only two of them fit
    let key = String(repeating: "k", count: 249)
    let encoded = DNSServiceTXTRecord.encode([(key, String(repeating: "\u{e9}", count: 10))])
    #expect(encoded.count == 1 + 254)
    #expect(encoded.first == 254)
    #expect(DNSServiceTXTRecord.decode(encoded) == [key: "\u{e9}\u{e9}"])

    let long = DNSServiceTXTRecord.encode([("k", String(repeating: "v", count: 1000))])
    #expect(long.count == 256)
    #expect(long.first == 255)
  }

  @Test
  func decodingToleratesWhatReceiversMustTolerate() {
    // an entry with no `=`, an empty entry, invalid UTF-8, then a truncated entry
    let record: [UInt8] = [4] + Array("flag".utf8) + [0] + [2, 0xFF, 0xFE] + [3]
      + Array("a=1".utf8) + [9] + Array("cut".utf8)
    #expect(DNSServiceTXTRecord.decode(record) == ["flag": "", "": "", "a": "1"])
    #expect(DNSServiceTXTRecord.decode([UInt8]()).isEmpty)
    #expect(DNSServiceTXTRecord.decode([UInt8(0)]) == ["": ""])
  }
}
