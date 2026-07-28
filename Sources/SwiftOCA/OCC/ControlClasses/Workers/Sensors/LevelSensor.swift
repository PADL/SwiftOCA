//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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

import BinaryParsing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

open class OcaLevelSensor: OcaSensor, @unchecked
Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.2") }

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1")
  )
  public var reading: OcaBoundedProperty<OcaDB>.PropertyValue
}

extension OcaPropertyChangedEventData<OcaDB>: _Ocp1Encodable {
  @_spi(SwiftOCAPrivate) @inlinable
  public func encode(into bytes: inout [UInt8]) {
    propertyID.encode(into: &bytes)
    var packedValue: UInt32 = propertyValue.bitPattern.bigEndian
    withUnsafeBytes(of: &packedValue) {
      bytes += $0
    }
    bytes += [changeType.rawValue]
  }
}

extension OcaPropertyChangedEventData<OcaDB>: _Ocp1Decodable {
  @_spi(SwiftOCAPrivate)
  public init(bytes: borrowing Data) throws {
    self = try Ocp1Error.mapping { [bytes = copy bytes] in
      try bytes.withParserSpan { try Self(parsing: &$0) }
    }
  }

  @_spi(SwiftOCAPrivate) @inlinable
  public init(parsing input: inout ParserSpan) throws {
    try self.init(
      propertyID: OcaPropertyID(parsing: &input),
      propertyValue: OcaDB(bitPattern: OcaUint32(parsingBigEndian: &input)),
      changeType: OcaPropertyChangeType(parsing: &input)
    )
  }
}
