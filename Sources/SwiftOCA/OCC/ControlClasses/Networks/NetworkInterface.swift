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

open class OcaNetworkInterface: OcaRoot, OcaOwnablePrivate, @unchecked
Sendable {
  override open class var classID: OcaClassID {
    OcaClassID("1.6")
  }

  override open class var classVersion: OcaClassVersionNumber {
    3
  }

  @OcaProperty(
    propertyID: OcaPropertyID("2.1"),
    getMethodID: OcaMethodID("2.1"),
    setMethodID: OcaMethodID("2.2")
  )
  public var label: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.2"),
    getMethodID: OcaMethodID("2.3")
  )
  public var owner: OcaProperty<OcaONo>.PropertyValue

  public var path: (OcaNamePath, OcaONoPath) {
    get async throws {
      try await getPath(methodID: OcaMethodID("2.4"))
    }
  }

  @OcaProperty(
    propertyID: OcaPropertyID("2.3"),
    getMethodID: OcaMethodID("2.5"),
    setMethodID: OcaMethodID("2.6")
  )
  public var enabled: OcaProperty<OcaBoolean>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.4"),
    getMethodID: OcaMethodID("2.7"),
    setMethodID: OcaMethodID("2.8")
  )
  public var systemIOInterfaceName: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.5"),
    getMethodID: OcaMethodID("2.9"),
    setMethodID: OcaMethodID("2.10"),
    ocp2Name: "Id"
  )
  public var groupID: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.6"),
    getMethodID: OcaMethodID("2.11"),
    setMethodID: OcaMethodID("2.12")
  )
  public var precedence: OcaProperty<OcaUint16>.PropertyValue

  /// "OcaIP4" or "OcaIP6"
  @OcaProperty(
    propertyID: OcaPropertyID("2.7"),
    getMethodID: OcaMethodID("2.13"),
    ocp2Name: "Identifier"
  )
  public var adaptationIdentifier: OcaProperty<OcaAdaptationIdentifier>.PropertyValue

  /// adaptation-specific, e.g. encoded OcaIP4NetworkSettings or MilanNetworkInterfaceAdaptationData
  @OcaProperty(
    propertyID: OcaPropertyID("2.8"),
    getMethodID: OcaMethodID("2.14"),
    ocp2Name: "Settings"
  )
  public var currentAdaptationData: OcaProperty<OcaBlob>.PropertyValue

  /// adaptation-specific, e.g. encoded OcaIP4NetworkSettings or MilanNetworkInterfaceAdaptationData
  @OcaProperty(
    propertyID: OcaPropertyID("2.9"),
    getMethodID: OcaMethodID("2.15"),
    setMethodID: OcaMethodID("2.16"),
    ocp2Name: "Settings"
  )
  public var requestedAdaptationData: OcaProperty<OcaBlob>.PropertyValue

  /// adaptation-specific, e.g. encoded OcaIP4NetworkSettings or MilanNetworkInterfaceAdaptationData
  @OcaProperty(
    propertyID: OcaPropertyID("2.10"),
    getMethodID: OcaMethodID("2.17"),
    ocp2Name: "Pending"
  )
  public var networkSettingPending: OcaProperty<OcaBoolean>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.11"),
    getMethodID: OcaMethodID("2.18")
  )
  public var status: OcaProperty<OcaNetworkInterfaceStatus>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.12"),
    getMethodID: OcaMethodID("2.19")
  )
  public var errorCode: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.13"),
    getMethodID: OcaMethodID("2.20")
  )
  public var counterSet: OcaProperty<OcaCounterSet>.PropertyValue

  public func get(counter id: OcaID16) async throws -> OcaCounter {
    try await sendCommandRrq(methodID: OcaMethodID("2.21"), parameters: id)
  }

  public func attach(counter id: OcaID16, to oNo: OcaONo) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("2.22"),
      parameters: OcaCounterNotifierParameters(id: id, oNo: oNo)
    )
  }

  public func detach(counter id: OcaID16, from oNo: OcaONo) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("2.23"),
      parameters: OcaCounterNotifierParameters(id: id, oNo: oNo)
    )
  }

  /// Resets one counter, or all counters when `id` is zero.
  public func resetCounters(id: OcaID16 = 0) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("2.24"), parameters: id)
  }

  public func apply(command: OcaNetworkInterfaceCommand) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("2.25"), parameters: command)
  }
}

extension OcaNetworkInterface {
  @_spi(SwiftOCAPrivate)
  public func _getOwner(flags: OcaPropertyResolutionFlags = .defaultFlags) async throws
    -> OcaONo
  {
    guard objectNumber != OcaRootBlockONo else { throw Ocp1Error.status(.invalidRequest) }
    return try await $owner._getValue(self, flags: flags)
  }

  func _set(owner: OcaONo) {
    self.$owner.subject.send(.success(owner))
  }
}
