//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

/// Remote endpoint IDs are adaptation-specific blobs. These helpers translate the
/// human-readable forms each adaptation defines so tools need not know the adaptations.
public enum OcaRemoteEndpointID {
  /// Encodes `string` for the adaptation, falling back to hex bytes.
  public static func blob(
    parsing string: String,
    adaptation: OcaAdaptationIdentifier
  ) throws -> OcaBlob {
    switch adaptation {
    case MilanAdaptation.identifier:
      guard let external = MilanMediaStreamEndpointIDExternal(string: string) else {
        throw Ocp1Error.status(.parameterError)
      }
      return try external.blob
    default:
      guard let bytes = OcaBlob(hexString: string) else { throw Ocp1Error.status(.parameterError) }
      return bytes
    }
  }

  /// The readable form of an external endpoint ID for the adaptation; printable text
  /// is shown as text and anything else as hex.
  public static func description(of blob: OcaBlob, adaptation: OcaAdaptationIdentifier) -> String {
    switch adaptation {
    case MilanAdaptation.identifier:
      if let external = try? blob.decode(MilanMediaStreamEndpointIDExternal.self) {
        return external == .unbound ? "" : external.description
      }
    default:
      if let text = String(bytes: blob, encoding: .utf8), !text.isEmpty,
         text.allSatisfy({ !$0.isNewline && ($0.isLetter || $0.isNumber || $0.isPunctuation || $0.isSymbol || $0 == " ") })
      {
        return text
      }
    }
    return blob.map { String(format: "%02x", $0) }.joined()
  }
}

/// Session status adaptation data is adaptation-specific; this renders the forms the
/// library knows so tools can show them without decoding them.
public enum OcaSessionStatusDescription {
  public static func description(of blob: OcaBlob, sessionType: OcaString) -> String? {
    switch sessionType {
    case MilanAdaptation.sessionType:
      guard let milan = try? blob.decode(MilanSessionStatusAdaptationData.self) else { return nil }
      var text = "\(milan.substate)"
      if milan.srpFailureCode != 0 { text += " srp=\(milan.srpFailureCode)" }
      if milan.msrpAccumulatedLatency != 0 { text += " latency=\(milan.msrpAccumulatedLatency)ns" }
      return text
    default:
      return nil
    }
  }
}

extension OcaBlob {
  init?(hexString: String) {
    let digits = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
    guard digits.count % 2 == 0 else { return nil }
    var bytes = [UInt8]()
    var index = digits.startIndex
    while index < digits.endIndex {
      let next = digits.index(index, offsetBy: 2)
      guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
      bytes.append(byte)
      index = next
    }
    self.init(bytes)
  }
}
