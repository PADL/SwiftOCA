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

  /// Returns the given descriptor with its IDInternal set to the allocated endpoint ID.
  open func add(endpoint: OcaMediaStreamEndpoint) async throws -> OcaMediaStreamEndpoint {
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

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.1"):
      let parameters: Parameters.AddPortParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      return try await controller.encodeResponse(add(port: parameters.name, mode: parameters.mode))
    case OcaMethodID("3.2"):
      let portID: OcaPortID = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await delete(port: portID)
      return Ocp1Response()
    case OcaMethodID("3.4"):
      return try await controller.encodeResponse(
        handleGetPortName(command, from: controller),
        name: "Name"
      )
    case OcaMethodID("3.5"):
      let params: OcaSetPortNameParameters = try decodeCommand(command)
      try await handleSetPortName(
        command,
        from: controller,
        portID: params.portID,
        name: params.name
      )
      return Ocp1Response()
    case OcaMethodID("3.8"):
      try await handleSetPortClockMapEntry(command, from: controller)
      return Ocp1Response()
    case OcaMethodID("3.9"):
      try await handleDeletePortClockMapEntry(command, from: controller)
      return Ocp1Response()
    case OcaMethodID("3.10"):
      return try await controller.encodeResponse(
        handleGetPortClockMapEntry(command, from: controller),
        name: "Entry"
      )
    case OcaMethodID("3.11"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try controller.encodeResponse(
        Parameters.MaxEndpointCounts(
          maxInputEndpoints: maxInputEndpoints,
          maxOutputEndpoints: maxOutputEndpoints
        ),
        names: ["MaxInputCount", "MaxOutputCount"]
      )
    case OcaMethodID("3.17"):
      let id: OcaID16 = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      guard let capability = mediaStreamModeCapabilities.first(where: { $0.id == id }) else {
        throw Ocp1Error.status(.parameterOutOfRange)
      }
      return try controller.encodeResponse(capability, name: "Capability")
    case OcaMethodID("3.22"):
      let id: OcaMediaStreamEndpointID = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try controller.encodeResponse(endpoint(id), name: "Endpoint")
    case OcaMethodID("3.24"):
      let id: OcaMediaStreamEndpointID = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try controller.encodeResponse(endpointStatus(id), name: "Status")
    case OcaMethodID("3.25"):
      let endpoint: OcaMediaStreamEndpoint = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      return try await controller.encodeResponse(add(endpoint: endpoint), name: "Endpoint")
    case OcaMethodID("3.26"):
      let id: OcaMediaStreamEndpointID = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await delete(endpoint: id)
      return Ocp1Response()
    case OcaMethodID("3.27"):
      let parameters: Parameters.ApplyEndpointCommandParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await applyEndpointCommand(parameters.id, command: parameters.command)
      return Ocp1Response()
    case OcaMethodID("3.28"):
      let parameters: Parameters.SetEndpointUserLabelParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setEndpoint(parameters.id, userLabel: parameters.userLabel)
      return Ocp1Response()
    case OcaMethodID("3.29"):
      let parameters: Parameters.SetEndpointMediaStreamModeParameters =
        try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setEndpoint(parameters.id, mediaStreamMode: parameters.mediaStreamMode)
      return Ocp1Response()
    case OcaMethodID("3.30"):
      let parameters: Parameters.SetEndpointChannelMapParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setEndpoint(parameters.id, channelMap: parameters.channelMap)
      return Ocp1Response()
    case OcaMethodID("3.31"):
      let parameters: Parameters.SetEndpointAlignmentLevelParameters =
        try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setEndpoint(parameters.id, alignmentLevel: parameters.alignmentLevel)
      return Ocp1Response()
    case OcaMethodID("3.32"):
      let id: OcaMediaStreamEndpointID = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try await controller.encodeResponse(getEndpointTimeSource(id))
    case OcaMethodID("3.33"):
      let parameters: Parameters.SetEndpointAdaptationDataParameters =
        try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setEndpoint(parameters.id, adaptationData: parameters.adaptationData)
      return Ocp1Response()
    case OcaMethodID("3.35"):
      let id: OcaMediaStreamEndpointID = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try controller.encodeResponse(endpointCounterSet(id), name: "CounterSet")
    case OcaMethodID("3.36"):
      let parameters: Parameters.EndpointCounterParameters = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      guard let counter = try endpointCounterSet(parameters.endpointID)
        .counter(id: parameters.counterID)
      else {
        throw Ocp1Error.status(.parameterOutOfRange)
      }
      return try controller.encodeResponse(counter, name: "Counter")
    case OcaMethodID("3.37"):
      let parameters: Parameters.EndpointCounterNotifierParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await attachEndpointCounterNotifier(
        endpointID: parameters.endpointID,
        counterID: parameters.counterID,
        to: parameters.oNo
      )
      return Ocp1Response()
    case OcaMethodID("3.38"):
      let parameters: Parameters.EndpointCounterNotifierParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await detachEndpointCounterNotifier(
        endpointID: parameters.endpointID,
        counterID: parameters.counterID,
        from: parameters.oNo
      )
      return Ocp1Response()
    case OcaMethodID("3.39"):
      let parameters: Parameters.EndpointCounterParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await resetEndpointCounterSet(parameters.endpointID, counterID: parameters.counterID)
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
