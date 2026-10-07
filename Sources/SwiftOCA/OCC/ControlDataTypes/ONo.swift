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

#if canImport(Foundation)
import Foundation
#endif

/// An object number. A distinct type so object numbers can be found in values at
/// run time; it codes exactly as a `UInt32`.
@frozen
public struct OcaONo: RawRepresentable, FixedWidthInteger, UnsignedInteger, Hashable, Sendable,
  Codable
{
  public typealias IntegerLiteralType = UInt32
  public typealias Magnitude = OcaONo
  public typealias Words = UInt32.Words

  public var rawValue: UInt32

  @inlinable @inline(__always)
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  @inlinable @inline(__always)
  public init(_ rawValue: UInt32) { self.rawValue = rawValue }

  @inlinable @inline(__always)
  public init(integerLiteral value: UInt32) { rawValue = value }

  @inlinable @inline(__always)
  public init(_truncatingBits bits: UInt) { rawValue = UInt32(_truncatingBits: bits) }

  @inlinable
  public init<T: BinaryInteger>(_ source: T) { rawValue = UInt32(source) }

  @inlinable
  public init?<T: BinaryInteger>(exactly source: T) {
    guard let value = UInt32(exactly: source) else { return nil }
    rawValue = value
  }

  @inlinable
  public init<T: BinaryInteger>(truncatingIfNeeded source: T) {
    rawValue = UInt32(truncatingIfNeeded: source)
  }

  @inlinable
  public init<T: BinaryInteger>(clamping source: T) { rawValue = UInt32(clamping: source) }

  @inlinable
  public init<T: BinaryFloatingPoint>(_ source: T) { rawValue = UInt32(source) }

  @inlinable
  public init?<T: BinaryFloatingPoint>(exactly source: T) {
    guard let value = UInt32(exactly: source) else { return nil }
    rawValue = value
  }

  /// Decimal, as `description` writes it, or hexadecimal after `0x`, either of them
  /// between angle brackets as `oNoString` writes it.
  public init?(_ description: String) {
    var digits = Substring(description)
    if digits.hasPrefix("<"), digits.hasSuffix(">") { digits = digits.dropFirst().dropLast() }
    let hex = digits.hasPrefix("0x") || digits.hasPrefix("0X")
    guard let value = hex ? UInt32(digits.dropFirst(2), radix: 16) : UInt32(digits) else { return nil }
    rawValue = value
  }

  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(UInt32.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  @inlinable public static var bitWidth: Int { UInt32.bitWidth }
  @inlinable public var words: Words { rawValue.words }
  @inlinable public var magnitude: OcaONo { self }
  @inlinable public var trailingZeroBitCount: Int { rawValue.trailingZeroBitCount }
  @inlinable public var nonzeroBitCount: Int { rawValue.nonzeroBitCount }
  @inlinable public var leadingZeroBitCount: Int { rawValue.leadingZeroBitCount }
  @inlinable public var byteSwapped: OcaONo { OcaONo(rawValue.byteSwapped) }
  @inlinable public var description: String { rawValue.description }
  /// The object number in hexadecimal, as `0x1000`, as object numbers are often written.
  public var hexDescription: String { "0x" + String(rawValue, radix: 16) }
  /// The object number in eight hexadecimal digits between angle brackets, as `<0x00001000>`.
  public var oNoString: String { "<0x\(hexString(width: 8))>" }
  @inlinable public func hash(into hasher: inout Hasher) { rawValue.hash(into: &hasher) }

  @inlinable
  public func addingReportingOverflow(_ rhs: OcaONo) -> (partialValue: OcaONo, overflow: Bool) {
    let (value, overflow) = rawValue.addingReportingOverflow(rhs.rawValue)
    return (OcaONo(value), overflow)
  }

  @inlinable
  public func subtractingReportingOverflow(_ rhs: OcaONo)
    -> (partialValue: OcaONo, overflow: Bool)
  {
    let (value, overflow) = rawValue.subtractingReportingOverflow(rhs.rawValue)
    return (OcaONo(value), overflow)
  }

  @inlinable
  public func multipliedReportingOverflow(by rhs: OcaONo)
    -> (partialValue: OcaONo, overflow: Bool)
  {
    let (value, overflow) = rawValue.multipliedReportingOverflow(by: rhs.rawValue)
    return (OcaONo(value), overflow)
  }

  @inlinable
  public func dividedReportingOverflow(by rhs: OcaONo) -> (partialValue: OcaONo, overflow: Bool) {
    let (value, overflow) = rawValue.dividedReportingOverflow(by: rhs.rawValue)
    return (OcaONo(value), overflow)
  }

  @inlinable
  public func remainderReportingOverflow(dividingBy rhs: OcaONo)
    -> (partialValue: OcaONo, overflow: Bool)
  {
    let (value, overflow) = rawValue.remainderReportingOverflow(dividingBy: rhs.rawValue)
    return (OcaONo(value), overflow)
  }

  @inlinable
  public func multipliedFullWidth(by other: OcaONo) -> (high: OcaONo, low: OcaONo) {
    let (high, low) = rawValue.multipliedFullWidth(by: other.rawValue)
    return (OcaONo(high), OcaONo(low))
  }

  @inlinable
  public func dividingFullWidth(_ dividend: (high: OcaONo, low: OcaONo))
    -> (quotient: OcaONo, remainder: OcaONo)
  {
    let (quotient, remainder) = rawValue.dividingFullWidth((dividend.high.rawValue, dividend.low.rawValue))
    return (OcaONo(quotient), OcaONo(remainder))
  }

  @inlinable public static func == (lhs: OcaONo, rhs: OcaONo) -> Bool { lhs.rawValue == rhs.rawValue }
  @inlinable public static func < (lhs: OcaONo, rhs: OcaONo) -> Bool { lhs.rawValue < rhs.rawValue }

  @inlinable
  public static func + (lhs: OcaONo, rhs: OcaONo) -> OcaONo { OcaONo(lhs.rawValue + rhs.rawValue) }
  @inlinable
  public static func - (lhs: OcaONo, rhs: OcaONo) -> OcaONo { OcaONo(lhs.rawValue - rhs.rawValue) }
  @inlinable
  public static func * (lhs: OcaONo, rhs: OcaONo) -> OcaONo { OcaONo(lhs.rawValue * rhs.rawValue) }
  @inlinable
  public static func / (lhs: OcaONo, rhs: OcaONo) -> OcaONo { OcaONo(lhs.rawValue / rhs.rawValue) }
  @inlinable
  public static func % (lhs: OcaONo, rhs: OcaONo) -> OcaONo { OcaONo(lhs.rawValue % rhs.rawValue) }
  @inlinable public static func += (lhs: inout OcaONo, rhs: OcaONo) { lhs.rawValue += rhs.rawValue }
  @inlinable public static func -= (lhs: inout OcaONo, rhs: OcaONo) { lhs.rawValue -= rhs.rawValue }
  @inlinable public static func *= (lhs: inout OcaONo, rhs: OcaONo) { lhs.rawValue *= rhs.rawValue }
  @inlinable public static func /= (lhs: inout OcaONo, rhs: OcaONo) { lhs.rawValue /= rhs.rawValue }
  @inlinable public static func %= (lhs: inout OcaONo, rhs: OcaONo) { lhs.rawValue %= rhs.rawValue }
  @inlinable public static func &= (lhs: inout OcaONo, rhs: OcaONo) { lhs.rawValue &= rhs.rawValue }
  @inlinable public static func |= (lhs: inout OcaONo, rhs: OcaONo) { lhs.rawValue |= rhs.rawValue }
  @inlinable public static func ^= (lhs: inout OcaONo, rhs: OcaONo) { lhs.rawValue ^= rhs.rawValue }
  @inlinable public static prefix func ~ (x: OcaONo) -> OcaONo { OcaONo(~x.rawValue) }

  @inlinable
  public static func &>>= (lhs: inout OcaONo, rhs: OcaONo) { lhs.rawValue &>>= rhs.rawValue }
  @inlinable
  public static func &<<= (lhs: inout OcaONo, rhs: OcaONo) { lhs.rawValue &<<= rhs.rawValue }
}

#if canImport(Foundation)
public extension OcaONo {
  /// The object number a number from a JSON container holds, as `UInt32(truncating:)`.
  init(truncating number: NSNumber) { self.init(rawValue: number.uint32Value) }
}
#endif
