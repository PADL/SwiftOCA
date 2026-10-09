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

public enum OcaTimeSourceAvailability: OcaUint8, Codable, Sendable, CaseIterable {
  case unavailable = 0
  case available = 1
}

public enum OcaTimeProtocol: OcaUint8, Codable, Sendable, CaseIterable {
  case undefined = 0
  case none = 1
  case `private` = 2
  case ntp = 3
  case sntp = 4
  case ieee1588_2002 = 5
  case ieee1588_2008 = 6
  case ieee_avb = 7
  case streamEndpoint = 8
  case aes11 = 9
  case genlock = 10
  case expansionBase = 128
}

public enum OcaTimeDeliveryMechanism: OcaUint8, Codable, Sendable, CaseIterable {
  case undefined = 0
  case local = 1
  case `private` = 2
  case ntp = 3
  case sntp = 4
  case ieee1588v1 = 5
  case ieee1588v2 = 6
  case ieee1588v2_1 = 7
  case ieee8021AS = 8 // gPTP
  case streamEndpoint = 9
  case aes11 = 11
  case terrestrialRadio = 12
  case gps = 13
  case galileo = 14
  case glonass = 15
  case beidou = 16
  case inrss = 17
  case expansionBase = 128
}

public typealias OcaSDPString = OcaString

public enum OcaTimeReferenceType: OcaUint8, Codable, Sendable, CaseIterable {
  case undefined = 0
  case local = 1
  case `private` = 2
  case tai = 3
  case _expansionBase = 128
}

public enum OcaTimeSourceSyncStatus: OcaUint8, Codable, Sendable, CaseIterable {
  case undefined = 0
  case unsynchronized = 1
  case synchronizing = 2
  case synchronized = 3
}

public struct OcaTimeDeliveryParameters_StreamEndpoint: Codable, Sendable {
  public let endpointOwner: OcaONo
  public let endpointID: OcaMediaStreamEndpointID
}

@OcaClass
open class OcaTimeSource: OcaAgent, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.2.16") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var availability: OcaProperty<OcaTimeSourceAvailability>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.2"),
    setMethodID: OcaMethodID("3.3"),
    ocp2GetName: "Mechanism",
    ocp2SetName: "Mechanism"
  )
  public var timeDeliveryMechanism: OcaProperty<OcaTimeDeliveryMechanism>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.4"),
    setMethodID: OcaMethodID("3.5"),
    ocp2GetName: "Parameters",
    ocp2SetName: "Parameters"
  )
  public var referenceSDPDescription: OcaProperty<OcaSDPString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.4"),
    getMethodID: OcaMethodID("3.6"),
    setMethodID: OcaMethodID("3.7")
  )
  public var referenceType: OcaProperty<OcaTimeReferenceType>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.5"),
    getMethodID: OcaMethodID("3.8"),
    setMethodID: OcaMethodID("3.9"),
    ocp2GetName: "ID",
    ocp2SetName: "ID"
  )
  public var referenceID: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.6"),
    getMethodID: OcaMethodID("3.10")
  )
  public var syncStatus: OcaProperty<OcaTimeSourceSyncStatus>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.7"),
    getMethodID: OcaMethodID("3.12"),
    setMethodID: OcaMethodID("3.13"),
    ocp2GetName: "Record",
    ocp2SetName: "Record"
  )
  public var timeDeliveryParameters: OcaProperty<OcaParameterRecord>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.8"),
    getMethodID: OcaMethodID("3.14"),
    setMethodID: OcaMethodID("3.15")
  )
  public var `protocol`: OcaProperty<OcaTimeProtocol>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("3.9"),
    getMethodID: OcaMethodID("3.16"),
    setMethodID: OcaMethodID("3.17")
  )
  public var parameters: OcaProperty<OcaSDPString>.PropertyValue

  @OcaMethod("3.11", name: "Reset")
  public func reset() async throws
}

// the model deprecates these
@_spi(SwiftOCAPrivate)
extension OcaTimeReferenceType: OcaDeprecated {}
@_spi(SwiftOCAPrivate)
extension OcaTimeProtocol: OcaDeprecated {}
