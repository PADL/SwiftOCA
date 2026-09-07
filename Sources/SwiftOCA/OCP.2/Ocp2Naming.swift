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

import Synchronization

/// OCP.2 names parameters and fields by the AES70-2A model names. SwiftOCA derives
/// them from Swift identifiers: a property or `CodingKey` name with its first letter
/// upper-cased (`gain` → `Gain`, `oNo` → `ONo`), or explicit names supplied by the
/// caller. On receipt names are matched case-insensitively, and a single-parameter
/// object is accepted whatever its member is called, so a peer still using the 2023
/// model's lower-case spellings (`minGain`, `lockable`), which OCA 1.5B makes
/// UpperCamelCase, is understood.
package enum Ocp2Naming {
  /// The wire name derived from a Swift identifier.
  package static func wireName(_ swiftName: String) -> String {
    var name = Substring(swiftName)
    while name.hasPrefix("_") {
      name = name.dropFirst()
    }
    guard let first = name.first else { return swiftName }
    return first.uppercased() + name.dropFirst()
  }

  /// The wire names for a bounded property: `Gain`, `MinGain`, `MaxGain`.
  package static func boundedWireNames(_ name: String) -> [String] {
    [name, "Min" + name, "Max" + name]
  }

  /// Case-insensitive match, ignoring leading underscores on either side. ASCII
  /// case folding only, which is all AES70 names use; allocation-free, as it runs
  /// once per member on every decode.
  package static func matches(_ a: String, _ b: String) -> Bool {
    let underscore = UInt8(ascii: "_")
    var x = a.utf8[...].drop(while: { $0 == underscore })
    var y = b.utf8[...].drop(while: { $0 == underscore })
    guard x.count == y.count else { return false }
    while let cx = x.popFirst(), let cy = y.popFirst() {
      if cx != cy, cx & 0xDF != cy & 0xDF || !(cx & 0xDF >= 0x41 && cx & 0xDF <= 0x5A) {
        return false
      }
    }
    return true
  }

  private static let _fieldNameCache = Mutex<[ObjectIdentifier: [String]]>([:])

  /// Stored-property names of `type` in declaration order (leading `_` stripped, so
  /// a property wrapper's storage reads as the property).
  package static func fieldNames(of type: Any.Type) -> [String] {
    let key = ObjectIdentifier(type)
    if let cached = _fieldNameCache.withLock({ $0[key] }) {
      return cached
    }
    var names = [String]()
    _forEachField(of: type) { name, _, _, _ in
      var s = String(cString: name)
      while s.hasPrefix("_") {
        s = String(s.dropFirst())
      }
      names.append(s)
      return true
    }
    _fieldNameCache.withLock { $0[key] = names }
    return names
  }

  /// The parameter names a top-level parameter object uses: explicit names first,
  /// then names derived from the type's fields.
  static func parameterNames(
    explicit: [String]?,
    fieldNames: [String]
  ) -> [String] {
    var names = explicit ?? []
    if names.count < fieldNames.count {
      names += fieldNames[names.count...].map(wireName)
    }
    return names
  }

  /// Placeholder key for a single unnamed parameter sent by a caller that did not
  /// supply a name. Peers that match by position accept it; use a name where the
  /// model's spelling matters.
  package static let unnamedParameter = "Value"
}
