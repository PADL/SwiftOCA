//
// Copyright (c) 2023 PADL Software Pty Ltd
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

open class OcaLevelSensor: OcaSensor, @unchecked Sendable {
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
  @_spi(SwiftOCAPrivate) @inlinable
  public init(bytes: borrowing[UInt8]) throws {
    guard bytes.count >= 9 else {
      throw Ocp1Error.pduTooShort
    }

    let propertyID = try OcaPropertyID(bytes: bytes)
    let propertyValue = bytes.withUnsafeBytes {
      let value = OcaUint32(bigEndian: $0.load(fromByteOffset: 4, as: OcaUint32.self))
      return OcaDB(bitPattern: value)
    }
    guard let changeType = OcaPropertyChangeType(rawValue: bytes[8]) else {
      throw Ocp1Error.status(.badFormat)
    }

    self.init(
      propertyID: propertyID,
      propertyValue: propertyValue,
      changeType: changeType
    )
  }
}
