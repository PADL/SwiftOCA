#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension [UInt8] {
  var hexString: String {
    let hexDigits: StaticString = "0123456789abcdef"
    return hexDigits.withUTF8Buffer { utf8Digits in
      String(unsafeUninitializedCapacity: 2 * count) { ptr -> Int in
        var p = ptr.baseAddress!
        for byte in self {
          p[0] = utf8Digits[Int(byte >> 4)]
          p[1] = utf8Digits[Int(byte & 0xF)]
          p += 2
        }
        return 2 * self.count
      }
    }
  }

  init(hexString: String) throws {
    guard hexString.count % 2 == 0 else { throw Ocp1Error.status(.badFormat) }

    var bytes = [UInt8]()
    bytes.reserveCapacity(hexString.count / 2)
    for i in stride(from: 0, to: hexString.count, by: 2) {
      let startIndex = hexString.index(hexString.startIndex, offsetBy: i)
      let endIndex = hexString.index(startIndex, offsetBy: 2)
      let byteString = String(hexString[startIndex..<endIndex])
      guard let byte = UInt8(byteString, radix: 16) else { throw Ocp1Error.status(.badFormat) }
      bytes.append(byte)
    }

    self = bytes
  }
}

package extension FixedWidthInteger {
  func hexString(width: Int, uppercase: Bool = false) -> String {
    let s = String(self, radix: 16, uppercase: uppercase)
    guard width > s.count else { return s }
    return String(repeating: "0", count: width - s.count) + s
  }
}

extension Data {
  var hexString: String {
    Array(self).hexString
  }

  init(hexString: String) throws {
    self = try Data([UInt8](hexString: hexString))
  }
}
