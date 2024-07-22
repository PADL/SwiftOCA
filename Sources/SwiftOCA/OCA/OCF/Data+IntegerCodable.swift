import Foundation

public extension Data {
  enum Endianness {
    case little
    case big
  }

  // https://forums.swift.org/t/raw-buffer-pointer-load-alignment/7005/7
  func decodeInteger<T: FixedWidthInteger>(index: Int, endianness: Endianness = .big) -> T {
    withUnsafeBytes { pointer in
      precondition(index >= 0)
      precondition(index <= self.count - MemoryLayout<T>.size)

      var value = T()
      Swift.withUnsafeMutableBytes(of: &value) { valuePtr in
        valuePtr
          .copyBytes(from: UnsafeRawBufferPointer(
            start: pointer.baseAddress!
              .advanced(by: index),
            count: MemoryLayout<T>.size
          ))
      }
      switch endianness {
      case .little:
        return value.littleEndian /* does nothing on little endian, swaps on big */
      case .big:
        return value.bigEndian /* does nothing on big endian, swaps on little */
      }
    }
  }

  mutating func encodeInteger<T: FixedWidthInteger>(
    _ value: T,
    index: Int,
    endianness: Endianness = .big
  ) {
    precondition(index >= 0)
    precondition(index <= count - MemoryLayout<T>.size)

    let lastIndex = index + MemoryLayout<T>.size
    let byteSwappedValue: T = switch endianness {
    case .little:
      value.littleEndian /* does nothing on little endian, swaps on big */
    case .big:
      value.bigEndian /* does nothing on big endian, swaps on little */
    }

    replaceSubrange(
      index..<lastIndex,
      with: withUnsafePointer(to: byteSwappedValue) { unbound -> Data in
        unbound
          .withMemoryRebound(
            to: UInt8.self,
            capacity: MemoryLayout<T>.size
          ) { bytes -> Data in
            Data(bytes: bytes, count: MemoryLayout<T>.size)
          }
      }
    )
  }
}
