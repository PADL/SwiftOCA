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

/// Controller proxy for AES70-23's DanteOcaMediaTransportApplication (1.7.1.A.2300), which
/// adds channel-based routing to CM4. The draft's method IDs are provisional (4.1-4.8 in
/// table order); its ChannelEndpoints property is modelled as the map its accessors use.
open class DanteOcaMediaTransportApplication: OcaMediaTransportApplication, @unchecked Sendable {
  override open class var classID: OcaClassID { DanteAdaptation.mediaTransportApplicationClassID }

  public typealias ChannelEndpointMap = OcaMap<OcaID16, OcaChannelEndpoint>
  public typealias ChannelEndpointOperatingStateMap = OcaMap<OcaID16, OcaAdaptationData>

  public struct SetChannelEndpointParameters: OcaParametersReflectable {
    public let id: OcaID16
    public let channelEndpoint: OcaChannelEndpoint

    public init(id: OcaID16, channelEndpoint: OcaChannelEndpoint) {
      self.id = id
      self.channelEndpoint = channelEndpoint
    }
  }

  @OcaProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var channelEndpoints: OcaMapProperty<OcaID16, OcaChannelEndpoint>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.8")
  )
  public var channelEndpointOperatingStates: OcaMapProperty<OcaID16, OcaAdaptationData>
    .PropertyValue

  public func getChannelEndpoint(_ id: OcaID16) async throws -> OcaChannelEndpoint {
    try await sendCommandRrq(methodID: OcaMethodID("4.3"), parameters: id)
  }

  public func setChannelEndpoint(_ id: OcaID16, _ channelEndpoint: OcaChannelEndpoint) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("4.4"),
      parameters: SetChannelEndpointParameters(id: id, channelEndpoint: channelEndpoint)
    )
  }

  /// Stops any media flow on the channel endpoint and clears its configuration.
  public func clearChannelEndpoint(_ id: OcaID16) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("4.5"), parameters: id)
  }

  /// Installs a Dante subscription (AES70-23 §9.2.3): SetChannelEndpoint with the
  /// transmit channel as the receive channel endpoint's RemoteAddress.
  public func subscribe(channelEndpoint id: OcaID16, to address: DanteChannelAddress) async throws {
    var endpoint = try await getChannelEndpoint(id)
    var data = (try? endpoint.adaptationData.decode(DanteChannelEndpointAdaptationData.self))
      ?? DanteChannelEndpointAdaptationData(mediaProtocol: .atp)
    data.remoteAddress = address
    endpoint.adaptationData = try data.blob
    try await setChannelEndpoint(id, endpoint)
  }

  /// `address` is "<channel>@<device>".
  public func subscribe(channelEndpoint id: OcaID16, to address: String) async throws {
    guard let address = DanteChannelAddress(string: address) else {
      throw Ocp1Error.status(.parameterError)
    }
    try await subscribe(channelEndpoint: id, to: address)
  }

  public func add(channelEndpoint: OcaChannelEndpoint) async throws -> OcaID16 {
    try await sendCommandRrq(methodID: OcaMethodID("4.6"), parameters: channelEndpoint)
  }

  public func delete(channelEndpoint id: OcaID16) async throws {
    try await sendCommandRrq(methodID: OcaMethodID("4.7"), parameters: id)
  }
}
