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

public struct OcaModelDescription: Codable, Sendable, CustomStringConvertible {
  public let manufacturer: OcaString
  public let name: OcaString
  public let version: OcaString

  public var description: String {
    "\(manufacturer) \(name) \(version)"
  }

  public init(manufacturer: OcaString, name: OcaString, version: OcaString) {
    self.manufacturer = manufacturer
    self.name = name
    self.version = version
  }
}

public struct OcaModelGUID: Hashable, Codable, Sendable, CustomStringConvertible {
  public typealias ModelCode = (OcaUint8, OcaUint8, OcaUint8, OcaUint8)

  public enum CodingKeys: CodingKey {
    case reserved
    case mfrCode
    case modelCode
  }

  public static func == (lhs: OcaModelGUID, rhs: OcaModelGUID) -> Bool {
    lhs.reserved == 0 && rhs.reserved == 0 &&
      lhs.mfrCode == rhs.mfrCode &&
      lhs.modelCode.0 == rhs.modelCode.0 &&
      lhs.modelCode.1 == rhs.modelCode.1 &&
      lhs.modelCode.2 == rhs.modelCode.2 &&
      lhs.modelCode.3 == rhs.modelCode.3
  }

  public func hash(into hasher: inout Hasher) {
    mfrCode.hash(into: &hasher)
    modelCode.0.hash(into: &hasher)
    modelCode.1.hash(into: &hasher)
    modelCode.2.hash(into: &hasher)
    modelCode.3.hash(into: &hasher)
  }

  public let reserved: OcaUint8
  public let mfrCode: OcaOrganizationID
  public let modelCode: ModelCode

  public var description: String {
    mfrCode.description + String(
      format: "%02X%02X%02X%02X",
      modelCode.0,
      modelCode.1,
      modelCode.2,
      modelCode.3
    )
  }

  public init(reserved: OcaUint8 = 0, mfrCode: OcaOrganizationID, modelCode: ModelCode) {
    self.reserved = reserved
    self.mfrCode = mfrCode
    self.modelCode = modelCode
  }

  public init(_ hexString: String) throws {
    guard hexString.count == 14 else { throw Ocp1Error.status(.badFormat) }

    let mfrCodeHex = String(hexString.prefix(6))
    let modelCodeHex = String(hexString.suffix(8))

    reserved = 0
    mfrCode = try OcaOrganizationID(mfrCodeHex)

    let modelCodeBytes = try [UInt8](hexString: modelCodeHex)
    guard modelCodeBytes.count == 4 else { throw Ocp1Error.status(.badFormat) }

    modelCode = (modelCodeBytes[0], modelCodeBytes[1], modelCodeBytes[2], modelCodeBytes[3])
  }

  @available(*, deprecated)
  public init(reserved: OcaUint8 = 0, mfrCode: OcaOrganizationID, modelCode: OcaUint32) {
    self.reserved = reserved
    self.mfrCode = mfrCode
    self.modelCode.0 = OcaUint8((modelCode >> 0) & 0xFF)
    self.modelCode.1 = OcaUint8((modelCode >> 8) & 0xFF)
    self.modelCode.2 = OcaUint8((modelCode >> 16) & 0xFF)
    self.modelCode.3 = OcaUint8((modelCode >> 24) & 0xFF)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    reserved = try container.decode(OcaUint8.self, forKey: .reserved)
    mfrCode = try container.decode(OcaOrganizationID.self, forKey: .mfrCode)

    var modelCodeContainer = try container.nestedUnkeyedContainer(forKey: .modelCode)
    modelCode = try (
      modelCodeContainer.decode(OcaUint8.self),
      modelCodeContainer.decode(OcaUint8.self),
      modelCodeContainer.decode(OcaUint8.self),
      modelCodeContainer.decode(OcaUint8.self)
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(reserved, forKey: .reserved)
    try container.encode(mfrCode, forKey: .mfrCode)

    var modelCodeContainer = container.nestedUnkeyedContainer(forKey: .modelCode)
    try modelCodeContainer.encode(modelCode.0)
    try modelCodeContainer.encode(modelCode.1)
    try modelCodeContainer.encode(modelCode.2)
    try modelCodeContainer.encode(modelCode.3)
  }
}
