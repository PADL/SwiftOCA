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

  open func add(port label: OcaString, mode: OcaPortMode) async throws -> OcaPortID {
    throw Ocp1Error.status(.notImplemented)
  }

  open func delete(port id: OcaPortID) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Returns the given descriptor with its IDInternal set to the allocated endpoint ID,
  /// having stored it with `initialStatus` as its state.
  open func add(
    endpoint: OcaMediaStreamEndpoint,
    initialStatus: OcaMediaStreamEndpointState
  ) async throws -> OcaMediaStreamEndpoint {
    throw Ocp1Error.status(.notImplemented)
  }

  open func delete(endpoint id: OcaMediaStreamEndpointID) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func applyEndpointCommand(
    _ id: OcaMediaStreamEndpointID,
    command: OcaMediaStreamEndpointCommand
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func setEndpoint(_ id: OcaMediaStreamEndpointID, userLabel: OcaString) async throws {
    var endpoint = try endpoint(id)
    endpoint.userLabel = userLabel
    try update(endpoint: endpoint)
  }

  open func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    mediaStreamMode: OcaMediaStreamMode
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    channelMap: OcaMultiMap<OcaUint16, OcaPortID>
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func setEndpoint(_ id: OcaMediaStreamEndpointID, alignmentLevel: OcaDBFS) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  open func setEndpoint(
    _ id: OcaMediaStreamEndpointID,
    adaptationData: OcaAdaptationData
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Default: the time source of the OcaMediaClock3 referenced by the endpoint's ClockONo.
  open func getEndpointTimeSource(
    _ id: OcaMediaStreamEndpointID
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

  open func attachEndpointCounterNotifier(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16,
    to oNo: OcaONo
  ) async throws {
    var counterSet = try endpointCounterSet(endpointID)
    guard counterSet.attach(notifier: oNo, to: counterID) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    update(endpointID: endpointID, counterSet: counterSet)
  }

  open func detachEndpointCounterNotifier(
    endpointID: OcaMediaStreamEndpointID,
    counterID: OcaID16,
    from oNo: OcaONo
  ) async throws {
    var counterSet = try endpointCounterSet(endpointID)
    guard counterSet.detach(notifier: oNo, from: counterID) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    update(endpointID: endpointID, counterSet: counterSet)
  }

  open func resetEndpointCounterSet(
    _ id: OcaMediaStreamEndpointID,
    counterID: OcaID16
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  // MARK: - Command dispatch

  @OcaDeviceMethod(Parameters.addPort, access: .write)
  func addPort(_ parameters: Parameters.AddPortParameters, from controller: any OcaController) async throws -> OcaPortID {
    try await add(port: parameters.name, mode: parameters.mode)
  }

  @OcaDeviceMethod(Parameters.deletePort, access: .write)
  func deletePort(_ portID: OcaPortID, from controller: any OcaController) async throws {
    try await delete(port: portID)
  }

  @OcaDeviceMethod(Parameters.getPortName, access: .read)
  func getPortName(_ parameters: OcaGetPortNameParameters, from controller: any OcaController) throws -> OcaString {
    try portName(of: parameters.portID)
  }

  @OcaDeviceMethod(Parameters.setPortName, access: .write)
  func setPortName(_ parameters: OcaSetPortNameParameters, from controller: any OcaController) throws {
    try setName(parameters.name, ofPort: parameters.portID)
  }

  @OcaDeviceMethod(Parameters.setPortClockMapEntry, access: .write)
  func setPortClockMapEntry(
    _ parameters: OcaSetPortClockMapEntryParameters,
    from controller: any OcaController
  ) {
    setPortClockMapEntry(parameters)
  }

  @OcaDeviceMethod(Parameters.deletePortClockMapEntry, access: .write)
  func deletePortClockMapEntry(_ portID: OcaPortID, from controller: any OcaController) {
    deletePortClockMapEntry(for: portID)
  }

  @OcaDeviceMethod(Parameters.getPortClockMapEntry, access: .read)
  func getPortClockMapEntry(_ portID: OcaPortID, from controller: any OcaController) throws
    -> OcaPortClockMapEntry
  {
    try portClockMapEntry(for: portID)
  }

  @OcaDeviceMethod(Parameters.getMaxEndpointCounts, access: .read)
  func getMaxEndpointCounts(from controller: any OcaController) -> Parameters.MaxEndpointCounts {
    .init(maxOutputCount: maxOutputEndpoints, maxInputCount: maxInputEndpoints)
  }

  @OcaDeviceMethod(Parameters.getMediaStreamModeCapability, access: .read)
  func getMediaStreamModeCapability(_ id: OcaID16, from controller: any OcaController) throws
    -> OcaMediaStreamModeCapability
  {
    guard let capability = mediaStreamModeCapabilities.first(where: { $0.id == id }) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return capability
  }

  @OcaDeviceMethod(Parameters.getEndpoint, access: .read)
  func getEndpoint(_ id: OcaMediaStreamEndpointID, from controller: any OcaController) throws
    -> OcaMediaStreamEndpoint
  {
    try endpoint(id)
  }

  @OcaDeviceMethod(Parameters.getEndpointStatus, access: .read)
  func getEndpointStatus(_ id: OcaMediaStreamEndpointID, from controller: any OcaController) throws
    -> OcaMediaStreamEndpointStatus
  {
    try endpointStatus(id)
  }

  @OcaDeviceMethod(Parameters.addEndpoint, access: .write)
  func addEndpoint(_ parameters: Parameters.AddEndpointParameters, from controller: any OcaController) async throws
    -> OcaMediaStreamEndpoint
  {
    try await add(endpoint: parameters.endpoint, initialStatus: parameters.initialStatus)
  }

  @OcaDeviceMethod(Parameters.deleteEndpoint, access: .write)
  func deleteEndpoint(_ id: OcaMediaStreamEndpointID, from controller: any OcaController) async throws {
    try await delete(endpoint: id)
  }

  @OcaDeviceMethod(Parameters.applyEndpointCommand, access: .write)
  func applyEndpointCommand(
    _ parameters: Parameters.ApplyEndpointCommandParameters,
    from controller: any OcaController
  ) async throws {
    try await applyEndpointCommand(parameters.endpointID, command: parameters.command)
  }

  @OcaDeviceMethod(Parameters.setEndpointUserLabel, access: .write)
  func setEndpointUserLabel(
    _ parameters: Parameters.SetEndpointUserLabelParameters,
    from controller: any OcaController
  ) async throws {
    try await setEndpoint(parameters.endpointID, userLabel: parameters.label)
  }

  @OcaDeviceMethod(Parameters.setEndpointMediaStreamMode, access: .write)
  func setEndpointMediaStreamMode(
    _ parameters: Parameters.SetEndpointMediaStreamModeParameters,
    from controller: any OcaController
  ) async throws {
    try await setEndpoint(parameters.endpointID, mediaStreamMode: parameters.streamMode)
  }

  @OcaDeviceMethod(Parameters.setEndpointChannelMap, access: .write)
  func setEndpointChannelMap(
    _ parameters: Parameters.SetEndpointChannelMapParameters,
    from controller: any OcaController
  ) async throws {
    try await setEndpoint(parameters.endpointID, channelMap: parameters.channelMap)
  }

  @OcaDeviceMethod(Parameters.setEndpointAlignmentLevel, access: .write)
  func setEndpointAlignmentLevel(
    _ parameters: Parameters.SetEndpointAlignmentLevelParameters,
    from controller: any OcaController
  ) async throws {
    try await setEndpoint(parameters.endpointID, alignmentLevel: parameters.level)
  }

  @OcaDeviceMethod(Parameters.getEndpointTimeSource, access: .read)
  func getEndpointTimeSource(_ id: OcaMediaStreamEndpointID, from controller: any OcaController) async throws
    -> Parameters.EndpointTimeSource
  {
    try await getEndpointTimeSource(id)
  }

  @OcaDeviceMethod(Parameters.setEndpointAdaptationData, access: .write)
  func setEndpointAdaptationData(
    _ parameters: Parameters.SetEndpointAdaptationDataParameters,
    from controller: any OcaController
  ) async throws {
    try await setEndpoint(parameters.endpointID, adaptationData: parameters.data)
  }

  @OcaDeviceMethod(Parameters.getEndpointCounterSet, access: .read)
  func getEndpointCounterSet(_ id: OcaMediaStreamEndpointID, from controller: any OcaController) throws
    -> OcaCounterSet
  {
    try endpointCounterSet(id)
  }

  @OcaDeviceMethod(Parameters.getEndpointCounter, access: .read)
  func getEndpointCounter(
    _ parameters: Parameters.EndpointCounterParameters,
    from controller: any OcaController
  ) throws -> OcaCounter {
    guard let counter = try endpointCounterSet(parameters.endpointID).counter(id: parameters.counterID) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return counter
  }

  @OcaDeviceMethod(Parameters.attachEndpointCounterNotifier, access: .write)
  func attachEndpointCounterNotifier(
    _ parameters: Parameters.EndpointCounterNotifierParameters,
    from controller: any OcaController
  ) async throws {
    try await attachEndpointCounterNotifier(
      endpointID: parameters.endpointID,
      counterID: parameters.counterID,
      to: parameters.notifierONo
    )
  }

  @OcaDeviceMethod(Parameters.detachEndpointCounterNotifier, access: .write)
  func detachEndpointCounterNotifier(
    _ parameters: Parameters.EndpointCounterNotifierParameters,
    from controller: any OcaController
  ) async throws {
    try await detachEndpointCounterNotifier(
      endpointID: parameters.endpointID,
      counterID: parameters.counterID,
      from: parameters.notifierONo
    )
  }

  @OcaDeviceMethod(Parameters.resetEndpointCounterSet, access: .write)
  func resetEndpointCounterSet(
    _ parameters: Parameters.EndpointCounterParameters,
    from controller: any OcaController
  ) async throws {
    try await resetEndpointCounterSet(parameters.endpointID, counterID: parameters.counterID)
  }
}
