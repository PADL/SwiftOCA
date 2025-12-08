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

public enum OcaResetCause: OcaUint8, Sendable, Codable, CaseIterable {
  case powerOn = 0
  case internalError = 1
  case upgrade = 2
  case externalRequest = 3
}

open class OcaDeviceManager: OcaManager, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.3.1") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.2")
  )
  public var modelGUID: OcaProperty<OcaModelGUID>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.3")
  )
  public var serialNumber: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.6")
  )
  public var modelDescription: OcaProperty<OcaModelDescription>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.4"),
    getMethodID: OcaMethodID("3.4"),
    setMethodID: OcaMethodID("3.5")
  )
  public var deviceName: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.5"),
    getMethodID: OcaMethodID("3.1")
  )
  public var version: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.6"),
    getMethodID: OcaMethodID("3.7"),
    setMethodID: OcaMethodID("3.8")
  )
  public var deviceRole: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.7"),
    getMethodID: OcaMethodID("3.9"),
    setMethodID: OcaMethodID("3.10")
  )
  public var userInventoryCode: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.8"),
    getMethodID: OcaMethodID("3.11"),
    setMethodID: OcaMethodID("3.12")
  )
  public var enabled: OcaProperty<OcaBoolean>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.9"),
    getMethodID: OcaMethodID("3.13")
  )
  public var state: OcaProperty<OcaDeviceState>.PropertyValue

  @OcaProperty(propertyID: OcaPropertyID("3.10"))
  public var busy: OcaProperty<OcaBoolean>.PropertyValue

  public typealias ResetKey = (
    OcaUint8,
    OcaUint8,
    OcaUint8,
    OcaUint8,
    OcaUint8,
    OcaUint8,
    OcaUint8,
    OcaUint8,
    OcaUint8,
    OcaUint8,
    OcaUint8,
    OcaUint8,
    OcaUint8,
    OcaUint8,
    OcaUint8,
    OcaUint8
  )

  public struct SetResetKeyParameters: Ocp1ParametersReflectable, Codable {
    public let key: ResetKey
    public let address: OcaNetworkAddress

    public init(key: ResetKey, address: OcaNetworkAddress) {
      self.key = key
      self.address = address
    }

    public var keyBytes: [OcaUint8] {
      Self._resetKeyToBytes(key)
    }

    public enum CodingKeys: CodingKey {
      case key
      case address
    }

    private static func _resetKeyToBytes(_ key: ResetKey) -> [OcaUint8] {
      [key.0, key.1, key.2, key.3, key.4, key.5, key.6, key.7,
       key.8, key.9, key.10, key.11, key.12, key.13, key.14, key.15]
    }

    private static func _decodeResetKey(
      from container: inout UnkeyedDecodingContainer
    ) throws -> ResetKey {
      var key: ResetKey = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
      key.0 = try container.decode(OcaUint8.self)
      key.1 = try container.decode(OcaUint8.self)
      key.2 = try container.decode(OcaUint8.self)
      key.3 = try container.decode(OcaUint8.self)
      key.4 = try container.decode(OcaUint8.self)
      key.5 = try container.decode(OcaUint8.self)
      key.6 = try container.decode(OcaUint8.self)
      key.7 = try container.decode(OcaUint8.self)
      key.8 = try container.decode(OcaUint8.self)
      key.9 = try container.decode(OcaUint8.self)
      key.10 = try container.decode(OcaUint8.self)
      key.11 = try container.decode(OcaUint8.self)
      key.12 = try container.decode(OcaUint8.self)
      key.13 = try container.decode(OcaUint8.self)
      key.14 = try container.decode(OcaUint8.self)
      key.15 = try container.decode(OcaUint8.self)
      return key
    }

    private static func _encodeResetKey(
      _ key: ResetKey,
      to container: inout UnkeyedEncodingContainer
    ) throws {
      for byte in _resetKeyToBytes(key) {
        try container.encode(byte)
      }
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      var keyContainer = try container.nestedUnkeyedContainer(forKey: .key)
      key = try Self._decodeResetKey(from: &keyContainer)
      address = try container.decode(OcaNetworkAddress.self, forKey: .address)
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      var keyContainer = container.nestedUnkeyedContainer(forKey: .key)
      try Self._encodeResetKey(key, to: &keyContainer)
      try container.encode(address, forKey: .address)
    }
  }

  // 3.14
  public func setResetKey(key: ResetKey, address: OcaNetworkAddress) async throws {
    let parameters = SetResetKeyParameters(key: key, address: address)
    try await sendCommandRrq(methodID: OcaMethodID("3.14"), parameters: parameters)
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.11"),
    getMethodID: OcaMethodID("3.15")
  )
  public var resetCause: OcaProperty<OcaResetCause>.PropertyValue

  // 3.16
  public func clearResetCause() async throws {
    throw Ocp1Error.notImplemented
  }

  @OcaProperty(
    propertyID: OcaPropertyID("3.12"),
    getMethodID: OcaMethodID("3.17"),
    setMethodID: OcaMethodID("3.18")
  )
  public var message: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.13"),
    getMethodID: OcaMethodID("3.19")
  )
  public var managers: OcaListProperty<OcaManagerDescriptor>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.14"),
    getMethodID: OcaMethodID("3.20")
  )
  public var deviceRevisionID: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.15"),
    getMethodID: OcaMethodID("3.21")
  )
  public var manufacturer: OcaProperty<OcaManufacturer>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.16"),
    getMethodID: OcaMethodID("3.22")
  )
  public var product: OcaProperty<OcaProduct>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.17"),
    getMethodID: OcaMethodID("3.23")
  )
  public var operationalState: OcaProperty<OcaDeviceOperationalState>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.18"),
    getMethodID: OcaMethodID("3.24"),
    setMethodID: OcaMethodID("3.25")
  )
  public var loggingEnabled: OcaProperty<OcaBoolean>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.19"),
    getMethodID: OcaMethodID("3.26")
  )
  public var mostRecentPatchDatasetONo: OcaProperty<OcaONo>.PropertyValue

  convenience init() {
    self.init(objectNumber: OcaDeviceManagerONo)
  }

  public func applyPatch(datasetONo: OcaONo) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("3.27"), parameters: datasetONo)
  }
}
