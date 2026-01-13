import Foundation

// https://stackoverflow.com/questions/39075043/how-to-convert-data-to-hex-string-in-swift

extension Data {
  struct HexEncodingOptions: OptionSet {
    let rawValue: Int
    static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
  }

  func hexEncodedString(options: HexEncodingOptions = []) -> String {
    let hexDigits = options.contains(.upperCase) ? "0123456789ABCDEF" : "0123456789abcdef"
    if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
      let utf8Digits = Array(hexDigits.utf8)
      return String(unsafeUninitializedCapacity: 2 * count) { ptr -> Int in
        var p = ptr.baseAddress!
        for byte in self {
          p[0] = utf8Digits[Int(byte / 16)]
          p[1] = utf8Digits[Int(byte % 16)]
          p += 2
        }
        return 2 * self.count
      }
    } else {
      let utf16Digits = Array(hexDigits.utf16)
      var chars: [unichar] = []
      chars.reserveCapacity(2 * count)
      for byte in self {
        chars.append(utf16Digits[Int(byte / 16)])
        chars.append(utf16Digits[Int(byte % 16)])
      }
      return String(utf16CodeUnits: chars, count: chars.count)
    }
  }

  init(hexString: String) throws {
    guard hexString.count % 2 == 0 else { throw Ocp1Error.status(.badFormat) }

    var data = Data(capacity: hexString.count / 2)
    for i in stride(from: 0, to: hexString.count, by: 2) {
      let startIndex = hexString.index(hexString.startIndex, offsetBy: i)
      let endIndex = hexString.index(startIndex, offsetBy: 2)
      let byteString = String(hexString[startIndex..<endIndex])
      guard let byte = UInt8(byteString, radix: 16) else { throw Ocp1Error.status(.badFormat) }
      data.append(byte)
    }

    self = data
  }
}

extension [UInt8] {
  init(hexString: String) throws {
    self = try Array(Data(hexString: hexString))
  }
}
