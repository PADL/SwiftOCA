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

import SwiftOCA

@OcaDeviceMethods
open class OcaMediaTransportApplication: OcaNetworkApplication, OcaPortsRepresentable,
  OcaPortClockMapRepresentable
{
  public typealias Parameters = SwiftOCA.OcaMediaTransportApplication

  override open class var classID: OcaClassID { OcaClassID("1.7.1") }

  override open class var classVersion: OcaClassVersionNumber { 3 }

  override open class var transientPropertyIDs: Set<OcaPropertyID> { ["2.6", "3.11", "3.12"] }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.3"),
    ocp2GetName: "OcaPorts"
  )
  public var ports = [OcaPort]()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.6"),
    setMethodID: OcaMethodID("3.7"),
    ocp2GetName: "Map",
    ocp2SetName: "Map"
  )
  public var portClockMap = OcaMap<OcaPortID, OcaPortClockMapEntry>()

  @OcaDeviceProperty(propertyID: OcaPropertyID("3.3"))
  public var maxInputEndpoints: OcaUint16 = 0

  @OcaDeviceProperty(propertyID: OcaPropertyID("3.4"))
  public var maxOutputEndpoints: OcaUint16 = 0

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.5"),
    getMethodID: OcaMethodID("3.12"),
    ocp2GetName: "Value"
  )
  public var maxPortsPerChannel: OcaUint16 = 0

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.6"),
    getMethodID: OcaMethodID("3.13"),
    ocp2GetName: "Value"
  )
  public var maxChannelsPerEndpoint: OcaUint16 = 0

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.7"),
    getMethodID: OcaMethodID("3.15"),
    setMethodID: OcaMethodID("3.16"),
    ocp2GetName: "Capabilities",
    ocp2SetName: "Capabilities"
  )
  public var mediaStreamModeCapabilities = [OcaMediaStreamModeCapability]()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.8"),
    getMethodID: OcaMethodID("3.18"),
    setMethodID: OcaMethodID("3.19"),
    ocp2GetName: "Parameters",
    ocp2SetName: "Parameters"
  )
  public var transportTimingParameters = OcaMediaTransportTimingParameters()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.9"),
    getMethodID: OcaMethodID("3.20"),
    setMethodID: OcaMethodID("3.14"),
    ocp2GetName: "Limits",
    ocp2SetName: "Limits"
  )
  public var alignmentLevelLimits = OcaInterval<OcaDBFS>(min: -20.0, max: -20.0)

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.10"),
    getMethodID: OcaMethodID("3.21")
  )
  public var endpoints = [OcaMediaStreamEndpoint]()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.11"),
    getMethodID: OcaMethodID("3.23"),
    ocp2GetName: "Statuses"
  )
  public var endpointStatuses = OcaMediaStreamEndpointStatusMap()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.12"),
    getMethodID: OcaMethodID("3.34"),
    ocp2GetName: "Sets"
  )
  public var endpointCounterSets = OcaMap<OcaID16, OcaCounterSet>()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.13"),
    getMethodID: OcaMethodID("3.40"),
    setMethodID: OcaMethodID("3.41"),
    ocp2GetName: "ONos",
    ocp2SetName: "ONos"
  )
  public var transportSessionControlAgentONos = [OcaONo]()

  // MARK: - Endpoint access for subclasses

  public func endpointIndex(_ id: OcaMediaStreamEndpointID) throws -> Int {
    guard let index = endpoints.firstIndex(where: { $0.idInternal == id }) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return index
  }

  public func endpoint(_ id: OcaMediaStreamEndpointID) throws -> OcaMediaStreamEndpoint {
    try endpoints[endpointIndex(id)]
  }

  public func endpointStatus(_ id: OcaMediaStreamEndpointID) throws
    -> OcaMediaStreamEndpointStatus
  {
    guard let status = endpointStatuses[id] else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return status
  }

  public func endpointCounterSet(_ id: OcaMediaStreamEndpointID) throws -> OcaCounterSet {
    guard let counterSet = endpointCounterSets[OcaID16(truncatingIfNeeded: id)] else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return counterSet
  }

  /// Replaces the endpoint with the same internal ID; subscribers see the whole list.
  public func update(endpoint: OcaMediaStreamEndpoint) throws {
    let index = try endpointIndex(endpoint.idInternal)
    guard endpoints[index] != endpoint else { return }
    endpoints[index] = endpoint
  }

  public func update(
    endpointID id: OcaMediaStreamEndpointID,
    status: OcaMediaStreamEndpointStatus
  ) {
    guard endpointStatuses[id] != status else { return }
    endpointStatuses[id] = status
  }

  public func update(endpointID id: OcaMediaStreamEndpointID, counterSet: OcaCounterSet) {
    let key = OcaID16(truncatingIfNeeded: id)
    guard endpointCounterSets[key] != counterSet else { return }
    endpointCounterSets[key] = counterSet
  }

  public func insert(
    endpoint: OcaMediaStreamEndpoint,
    status: OcaMediaStreamEndpointStatus = .init(state: .notReady),
    counterSet: OcaCounterSet? = nil
  ) {
    if let index = endpoints.firstIndex(where: { $0.idInternal == endpoint.idInternal }) {
      endpoints[index] = endpoint
    } else {
      endpoints.append(endpoint)
    }
    endpointStatuses[endpoint.idInternal] = status
    if let counterSet {
      endpointCounterSets[OcaID16(truncatingIfNeeded: endpoint.idInternal)] = counterSet
    }
  }

  public func remove(endpointID id: OcaMediaStreamEndpointID) {
    endpoints.removeAll { $0.idInternal == id }
    endpointStatuses.removeValue(forKey: id)
    endpointCounterSets.removeValue(forKey: OcaID16(truncatingIfNeeded: id))
  }

  public func makeEndpointCounterSetID(endpointID id: OcaMediaStreamEndpointID) throws -> OcaBlob {
    try OcaMediaStreamEndpointCounterSetID(ownerONo: objectNumber, endpointID: id).blob
  }

  // MARK: - Overridable behaviour

  @OcaDeviceMethod(Parameters.Methods.addPort)
  open func addPort(name: OcaString, mode: OcaPortMode, from controller: any OcaController) async throws -> OcaPortID {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.deletePort)
  open func deletePort(id: OcaPortID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Returns the given descriptor with its IDInternal set to the allocated endpoint ID,
  /// having stored it with `initialStatus` as its state.
  @OcaDeviceMethod(Parameters.Methods.addEndpoint)
  open func addEndpoint(
    endpoint: OcaMediaStreamEndpoint,
    initialStatus: OcaMediaStreamEndpointState,
    from controller: any OcaController
  ) async throws -> OcaMediaStreamEndpoint {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.deleteEndpoint)
  open func deleteEndpoint(id: OcaMediaStreamEndpointID, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.applyEndpointCommand)
  open func applyEndpointCommand(
    endpointID: OcaMediaStreamEndpointID,
    command: OcaMediaStreamEndpointCommand,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.setEndpointUserLabel)
  open func setEndpointUserLabel(
    endpointID: OcaMediaStreamEndpointID,
    label: OcaString,
    from controller: any OcaController
  ) async throws {
    var endpoint = try endpoint(endpointID)
    endpoint.userLabel = label
    try update(endpoint: endpoint)
  }

  @OcaDeviceMethod(Parameters.Methods.setEndpointMediaStreamMode)
  open func setEndpointMediaStreamMode(
    endpointID: OcaMediaStreamEndpointID,
    streamMode: OcaMediaStreamMode,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.setEndpointChannelMap)
  open func setEndpointChannelMap(
    endpointID: OcaMediaStreamEndpointID,
    channelMap: OcaMultiMap<OcaUint16, OcaPortID>,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.setEndpointAlignmentLevel)
  open func setEndpointAlignmentLevel(
    endpointID: OcaMediaStreamEndpointID,
    level: OcaDBFS,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(Parameters.Methods.setEndpointAdaptationData)
  open func setEndpointAdaptationData(
    endpointID: OcaMediaStreamEndpointID,
    data: OcaAdaptationData,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Default: the time source of the OcaMediaClock3 referenced by the endpoint's ClockONo.
  @OcaDeviceMethod(Parameters.Methods.getEndpointTimeSource)
  open func getEndpointTimeSource(
    id: OcaMediaStreamEndpointID,
    from controller: any OcaController
  ) async throws -> Parameters.EndpointTimeSource {
    let endpoint = try endpoint(id)
    guard let clock = await deviceDelegate?.objects[endpoint.clockONo] as? OcaMediaClock3,
          let timeSource = await deviceDelegate?.objects[clock.timeSourceONo] as? OcaTimeSource
    else {
      throw Ocp1Error.status(.invalidRequest)
    }
    return Parameters.EndpointTimeSource(
      referenceType: timeSource.referenceType,
      referenceID: timeSource.referenceID
    )
  }

  @OcaDeviceMethod(Parameters.Methods.attachEndpointCounterNotifier)
  open func attachEndpointCounterNotifier(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16,
    notifierONo: OcaONo,
    from controller: any OcaController
  ) async throws {
    var counterSet = try endpointCounterSet(endpointID)
    guard counterSet.attach(notifier: notifierONo, to: counterID) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    update(endpointID: endpointID, counterSet: counterSet)
  }

  @OcaDeviceMethod(Parameters.Methods.detachEndpointCounterNotifier)
  open func detachEndpointCounterNotifier(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16,
    notifierONo: OcaONo,
    from controller: any OcaController
  ) async throws {
    var counterSet = try endpointCounterSet(endpointID)
    guard counterSet.detach(notifier: notifierONo, from: counterID) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    update(endpointID: endpointID, counterSet: counterSet)
  }

  @OcaDeviceMethod(Parameters.Methods.resetEndpointCounterSet)
  open func resetEndpointCounterSet(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  // MARK: - Command dispatch

  @OcaDeviceMethod(Parameters.Methods.getPortName)
  func getPortName(portID: OcaPortID, from controller: any OcaController) throws -> OcaString {
    try portName(of: portID)
  }

  @OcaDeviceMethod(Parameters.Methods.setPortName)
  func setPortName(portID: OcaPortID, name: OcaString, from controller: any OcaController) throws {
    try setName(name, ofPort: portID)
  }

  @OcaDeviceMethod(Parameters.Methods.setPortClockMapEntry)
  func setPortClockMapEntry(
    id: OcaPortID,
    entry: OcaPortClockMapEntry,
    from controller: any OcaController
  ) {
    portClockMap[id] = entry
  }

  @OcaDeviceMethod(Parameters.Methods.deletePortClockMapEntry)
  func deletePortClockMapEntry(id: OcaPortID, from controller: any OcaController) {
    deletePortClockMapEntry(for: id)
  }

  @OcaDeviceMethod(Parameters.Methods.getPortClockMapEntry)
  func getPortClockMapEntry(id: OcaPortID, from controller: any OcaController) throws
    -> OcaPortClockMapEntry
  {
    try portClockMapEntry(for: id)
  }

  @OcaDeviceMethod(Parameters.Methods.getMaxEndpointCounts)
  func getMaxEndpointCounts(from controller: any OcaController) -> Parameters.MaxEndpointCounts {
    .init(maxOutputCount: maxOutputEndpoints, maxInputCount: maxInputEndpoints)
  }

  @OcaDeviceMethod(Parameters.Methods.getMediaStreamModeCapability)
  func getMediaStreamModeCapability(capabilityID: OcaID16, from controller: any OcaController) throws
    -> OcaMediaStreamModeCapability
  {
    guard let capability = mediaStreamModeCapabilities.first(where: { $0.id == capabilityID }) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return capability
  }

  @OcaDeviceMethod(Parameters.Methods.getEndpoint)
  func getEndpoint(id: OcaMediaStreamEndpointID, from controller: any OcaController) throws
    -> OcaMediaStreamEndpoint
  {
    try endpoint(id)
  }

  @OcaDeviceMethod(Parameters.Methods.getEndpointStatus)
  func getEndpointStatus(id: OcaMediaStreamEndpointID, from controller: any OcaController) throws
    -> OcaMediaStreamEndpointStatus
  {
    try endpointStatus(id)
  }

  @OcaDeviceMethod(Parameters.Methods.getEndpointCounterSet)
  func getEndpointCounterSet(endpointID: OcaMediaStreamEndpointID, from controller: any OcaController) throws
    -> OcaCounterSet
  {
    try endpointCounterSet(endpointID)
  }

  @OcaDeviceMethod(Parameters.Methods.getEndpointCounter)
  func getEndpointCounter(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16,
    from controller: any OcaController
  ) throws -> OcaCounter {
    guard let counter = try endpointCounterSet(endpointID).counter(id: counterID) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return counter
  }
}
