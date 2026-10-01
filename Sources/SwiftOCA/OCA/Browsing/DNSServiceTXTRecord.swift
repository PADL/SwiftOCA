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

/// The wire form of a DNS-SD TXT record (RFC 6763 section 6): a sequence of
/// `key=value` strings, each preceded by its length in one byte.
@_spi(SwiftOCAPrivate)
public enum DNSServiceTXTRecord {
  /// The longest a `key=value` string can be, its length being a single byte.
  public static let maxEntryLength = 255

  /// Whether RFC 6763 section 6.4 allows `key`: at least one character, all of them
  /// printable US-ASCII, none of them `=`.
  public static func isValidKey(_ key: String) -> Bool {
    !key.isEmpty && key.utf8.allSatisfy { (0x20...0x7E).contains($0) && $0 != UInt8(ascii: "=") }
  }

  /// Encodes the entries in order. The wire form has no escaping, so an entry whose key
  /// is not valid cannot be represented and is left out; a value too long for its entry
  /// to fit in 255 bytes is cut short at a character boundary.
  public static func encode(_ entries: [(String, String)]) -> [UInt8] {
    var buffer = [UInt8]()
    for (key, value) in entries {
      // the key, the `=` and the value share the 255 bytes
      guard isValidKey(key), key.utf8.count < maxEntryLength else { continue }
      var valueBytes = [UInt8]()
      let room = maxEntryLength - key.utf8.count - 1
      for character in value {
        let bytes = Array(String(character).utf8)
        guard valueBytes.count + bytes.count <= room else { break }
        valueBytes += bytes
      }
      buffer.append(UInt8(key.utf8.count + 1 + valueBytes.count))
      buffer += key.utf8
      buffer.append(UInt8(ascii: "="))
      buffer += valueBytes
    }
    return buffer
  }

  /// Decodes the entries of a TXT record into a dictionary. An entry with no `=` has an
  /// empty value; an entry that is not UTF-8 is skipped; a truncated record ends the
  /// decoding. Where a key recurs the last entry has it.
  public static func decode(_ record: some Collection<UInt8>) -> [String: String] {
    var entries = [String: String]()
    var remainder = record[...]
    while let length = remainder.first {
      remainder = remainder.dropFirst()
      guard remainder.count >= Int(length) else { break }
      let entry = remainder.prefix(Int(length))
      remainder = remainder.dropFirst(Int(length))
      // decoding repairs invalid UTF-8, so a string that differs from its bytes was not valid
      let string = String(decoding: entry, as: UTF8.self)
      guard string.utf8.elementsEqual(entry) else { continue }
      let components = string.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      entries[String(components[0])] = components.count > 1 ? String(components[1]) : ""
    }
    return entries
  }
}
