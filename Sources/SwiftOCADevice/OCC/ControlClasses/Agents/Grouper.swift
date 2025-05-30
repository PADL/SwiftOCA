//
// Copyright (c) 2024-2025 PADL Software Pty Ltd
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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@_spi(SwiftOCAPrivate)
import SwiftOCA
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif

@_spi(SwiftOCAPrivate)
public actor OcaConnectionBroker {
  static let shared = OcaConnectionBroker()

  private var connections = [OcaNetworkHostID: Ocp1Connection]()

  @_spi(SwiftOCAPrivate)
  public func connection<T: OcaRoot>(
    for objectPath: OcaOPath,
    type: T.Type
  ) async throws -> Ocp1Connection {
    if let connection = connections[objectPath.hostID] {
      return connection
    }

    let serviceNameOrID = try Ocp1Decoder()
      .decode(OcaString.self, from: Data(objectPath.hostID))

    // CM2: OcaNetworkHostID (deprecated)
    // CM3: ServiceID from OcaControlNetwork (let's asssume this is a hostname)
    // CM4: OcaControlNetwork ServiceName

    var addrInfo: UnsafeMutablePointer<addrinfo>?

    if getaddrinfo(serviceNameOrID, nil, nil, &addrInfo) < 0 {
      throw Ocp1Error.remoteDeviceResolutionFailed
    }

    defer {
      freeaddrinfo(addrInfo)
    }

    guard let firstAddr = addrInfo else {
      throw Ocp1Error.remoteDeviceResolutionFailed
    }

    for addr in sequence(first: firstAddr, next: { $0.pointee.ai_next }) {
      let connection: Ocp1Connection
      let data = Data(bytes: addr.pointee.ai_addr, count: Int(addr.pointee.ai_addrlen))
      let options = Ocp1ConnectionOptions(flags: [
        .retainObjectCacheAfterDisconnect,
        .automaticReconnect,
        .refreshSubscriptionsOnReconnection,
      ])

      switch addr.pointee.ai_socktype {
      case SwiftOCA.SOCK_STREAM:
        connection = try await Ocp1TCPConnection(deviceAddress: data, options: options)
      case SwiftOCA.SOCK_DGRAM:
        connection = try await Ocp1UDPConnection(deviceAddress: data, options: options)
      default:
        continue
      }

      try await connection.connect()

      connections[objectPath.hostID] = connection

      let classIdentification = try await connection
        .getClassIdentification(objectNumber: objectPath.oNo)
      guard classIdentification.isSubclass(of: T.classIdentification) else {
        throw Ocp1Error.status(.invalidRequest)
      }

      return connection
    }

    throw Ocp1Error.remoteDeviceResolutionFailed
  }

  func isOnline(_ objectPath: OcaOPath) async -> Bool {
    if let connection = connections[objectPath.hostID] {
      return await connection.isConnected
    }

    return false
  }

  @_spi(SwiftOCAPrivate)
  public func remove(connection aConnection: Ocp1Connection) async throws {
    for (hostID, connection) in connections {
      guard connection == aConnection else { continue }
      try await connection.disconnect()
      connections[hostID] = nil
    }
  }
}

open class OcaGrouper<CitizenType: OcaRoot>: OcaAgent {
  override open class var classID: OcaClassID { OcaClassID("1.2.2") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  // AES70-2023 only allows actuator groupers so we don't expose the property setter
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.12")
  )
  public var actuatorOrSensor = true

  // masterSlave vs peerToPeer is an implementation choice but cannot be set by the controller,
  // hence the property setter is also not exposed here
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.14")
  )
  public var mode: OcaGrouperMode = .masterSlave

  @OcaDevice
  final class Group: Sendable, Hashable {
    let index: OcaUint16
    let name: OcaString
    let proxy: Proxy?

    public init(grouper: OcaGrouper, index: OcaUint16, name: OcaString) async throws {
      self.index = index
      self.name = name
      switch grouper.mode {
      case .masterSlave:
        // In master-slave mode, each time a caller adds a group to a Grouper
        // instance, the Grouper instance creates an object known as a group
        // proxy. Thus, there is one group proxy instance per group. The class
        // of the group proxy is the same as the Grouper's citizen class. For
        // example, for a group of OcaGain actuators, the group proxy is an
        // OcaGain object. The purpose of the group proxy is to allow
        // controllers to access the group's setpoint (for actuator groups) or
        // reading (for sensor groups) in the same way as they would access
        // individual workers of the citizen class.
        let proxy = try await Proxy(grouper)
        self.proxy = proxy
        proxy.group = self
      case .peerToPeer:
        // In peer-to-peer mode, no group proxy is created. Instead, the group
        // setpoint is changed whenever any member's setpoint is changed. In
        // effect, all the group's members behave as though they were group
        // proxies
        proxy = nil
      }
    }

    var proxyONo: OcaONo {
      proxy?.objectNumber ?? OcaInvalidONo
    }

    var ocaGrouperGroup: OcaGrouperGroup {
      OcaGrouperGroup(
        index: index,
        name: name,
        proxyONo: proxyONo
      )
    }

    nonisolated static func == (
      lhs: OcaGrouper<CitizenType>.Group,
      rhs: OcaGrouper<CitizenType>.Group
    ) -> Bool {
      lhs.index == rhs.index
    }

    nonisolated func hash(into hasher: inout Hasher) {
      hasher.combine(index)
    }
  }

  @OcaDevice
  final class Citizen: Sendable, Hashable {
    enum Target {
      case local(CitizenType)
      case remote(OcaOPath)

      init(_ objectPath: OcaOPath, device: OcaDevice) async throws {
        if objectPath.hostID.isEmpty {
          guard let object = await device.resolve(objectNumber: objectPath.oNo) as? CitizenType
          else {
            throw Ocp1Error.invalidObject(objectPath.oNo)
          }
          guard await object.objectIdentification.classIdentification
            .isSubclass(of: CitizenType.classIdentification)
          else {
            throw Ocp1Error.status(.invalidRequest)
          }
          self = .local(object)
        } else {
          self = .remote(objectPath)
        }
      }

      var oNo: OcaONo {
        switch self {
        case let .local(object):
          object.objectNumber
        case let .remote(path):
          path.oNo
        }
      }
    }

    let index: OcaUint16
    let target: Target

    init(index: OcaUint16, target: Target) {
      self.index = index
      self.target = target
    }

    var objectPath: OcaOPath {
      switch target {
      case let .local(object):
        OcaOPath(hostID: OcaBlob(), oNo: object.objectNumber)
      case let .remote(path):
        path
      }
    }

    var online: OcaBoolean {
      get async {
        switch target {
        case .local:
          true
        case let .remote(path):
          await OcaConnectionBroker.shared.isOnline(path)
        }
      }
    }

    var ocaGrouperCitizen: OcaGrouperCitizen {
      get async {
        await OcaGrouperCitizen(
          index: index,
          objectPath: objectPath,
          online: online
        )
      }
    }

    var connection: Ocp1Connection {
      get async throws {
        switch target {
        case .local:
          throw Ocp1Error.invalidHandle
        case let .remote(path):
          try await OcaConnectionBroker.shared.connection(
            for: path,
            type: CitizenType.self
          )
        }
      }
    }

    nonisolated static func == (
      lhs: OcaGrouper<CitizenType>.Citizen,
      rhs: OcaGrouper<CitizenType>.Citizen
    ) -> Bool {
      lhs.index == rhs.index
    }

    nonisolated func hash(into hasher: inout Hasher) {
      hasher.combine(index)
    }
  }

  @OcaDevice
  fileprivate struct Enrollment: Sendable, Hashable {
    let group: Group
    let citizen: Citizen
    weak var subscriptionCancellable: Ocp1Connection.SubscriptionCancellable?

    init(group: Group, citizen: Citizen) {
      self.group = group
      self.citizen = citizen
    }

    nonisolated static func == (
      lhs: OcaGrouper<CitizenType>.Enrollment,
      rhs: OcaGrouper<CitizenType>.Enrollment
    ) -> Bool {
      lhs.group == rhs.group && lhs.citizen == rhs.citizen
    }

    nonisolated func hash(into hasher: inout Hasher) {
      hasher.combine(group)
      hasher.combine(citizen)
    }
  }

  private var groups = [OcaUint16: Group]()
  private var citizens = [OcaUint16: Citizen]()
  private var enrollments = Set<Enrollment>()
  private var nextGroupIndex: OcaUint16 = 0
  private var nextCitizenIndex: OcaUint16 = 0
  private var connectionStateMonitors = [Ocp1Connection: Task<(), Error>]()

  func allocateGroupIndex() -> OcaUint16 {
    defer { nextGroupIndex += 1 }
    return nextGroupIndex
  }

  func allocateCitizenIndex() -> OcaUint16 {
    defer { nextCitizenIndex += 1 }
    return nextCitizenIndex
  }

  func addGroup(name: OcaString) async throws -> SwiftOCA.OcaGrouper.AddGroupParameters {
    let group = try await Group(grouper: self, index: allocateGroupIndex(), name: name)
    groups[group.index] = group
    try await notifySubscribers(groups: Array(groups.values), changeType: .itemAdded)
    return SwiftOCA.OcaGrouper.AddGroupParameters(index: group.index, proxyONo: group.proxyONo)
  }

  func deleteGroup(index: OcaUint16) async throws {
    guard let group = groups[index] else {
      throw Ocp1Error.status(.invalidRequest)
    }
    if let proxy = group.proxy {
      try await deviceDelegate?.deregister(object: proxy)
    }
    try await notifySubscribers(groups: Array(groups.values), changeType: .itemDeleted)
    groups[index] = nil
  }

  var groupCount: OcaUint16 { OcaUint16(groups.count) }

  func getGroupList() -> [OcaGrouperGroup] {
    groups.map { _, value in
      value.ocaGrouperGroup
    }
  }

  func addCitizen(_ citizen: OcaGrouperCitizen) async throws -> OcaUint16 {
    guard let deviceDelegate else { throw Ocp1Error.notConnected }
    let citizen = try await Citizen(
      index: allocateCitizenIndex(),
      target: Citizen.Target(citizen.objectPath, device: deviceDelegate)
    )
    try await notifySubscribers(citizen: citizen, changeType: .citizenAdded)
    try await notifySubscribers(citizens: Array(citizens.values), changeType: .itemAdded)
    return citizen.index
  }

  func deleteCitizen(index: OcaUint16) async throws {
    guard let citizen = citizens[index] else {
      throw Ocp1Error.status(.invalidRequest)
    }
    try await notifySubscribers(citizen: citizen, changeType: .citizenDeleted)
    try await notifySubscribers(citizens: Array(citizens.values), changeType: .itemDeleted)
    citizens[index] = nil
  }

  var citizenCount: OcaUint16 { OcaUint16(citizens.count) }

  func getCitizenList() async -> [OcaGrouperCitizen] {
    var citizens = [OcaGrouperCitizen]()
    for (_, value) in self.citizens {
      await citizens.append(value.ocaGrouperCitizen)
    }
    return citizens
  }

  func getEnrollment(_ enrollment: OcaGrouperEnrollment) -> OcaBoolean {
    enrollments.contains(where: {
      $0.group.index == enrollment.groupIndex && $0.citizen.index == enrollment.citizenIndex
    })
  }

  func setEnrollment(_ enrollment: OcaGrouperEnrollment, isMember: OcaBoolean) async throws {
    guard let group = groups[enrollment.groupIndex],
          let citizen = citizens[enrollment.citizenIndex]
    else {
      throw Ocp1Error.status(.invalidRequest)
    }

    if isMember {
      enrollments.insert(Enrollment(group: group, citizen: citizen))
    } else {
      guard getEnrollment(enrollment) else { throw Ocp1Error.status(.invalidRequest) }
      guard let index = enrollments.firstIndex(where: {
        $0 == Enrollment(group: group, citizen: citizen)
      }) else {
        throw Ocp1Error.status(.invalidRequest)
      }
      enrollments.remove(at: index)
    }
    try await notifySubscribers(
      group: group,
      citizen: citizen,
      changeType: isMember ? .enrollment : .unEnrollment
    )
    try await notifySubscribers(
      enrollments: Array(enrollments),
      changeType: isMember ? .itemAdded : .itemDeleted
    )
  }

  func getGroupMemberList(group: Group) throws -> [Citizen] {
    enrollments.filter { $0.group.index == group.index }.map(\.citizen)
  }

  func getGroupMemberList(index: OcaUint16) async throws -> [OcaGrouperCitizen] {
    guard let group = groups[index] else {
      throw Ocp1Error.status(.invalidRequest)
    }
    return try await getGroupMemberList(group: group)
      .asyncMap { @Sendable in await $0.ocaGrouperCitizen }
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.1"):
      let name: OcaString = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      return try await encodeResponse(addGroup(name: name))
    case OcaMethodID("3.2"):
      let index: OcaUint16 = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await deleteGroup(index: index)
      return Ocp1Response()
    case OcaMethodID("3.3"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try encodeResponse(groupCount)
    case OcaMethodID("3.4"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try encodeResponse(getGroupList())
    case OcaMethodID("3.5"):
      let parameters: OcaGrouperCitizen = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      return try await encodeResponse(addCitizen(parameters))
    case OcaMethodID("3.6"):
      let index: OcaUint16 = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await deleteCitizen(index: index)
      return Ocp1Response()
    case OcaMethodID("3.7"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try encodeResponse(citizenCount)
    case OcaMethodID("3.8"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try await encodeResponse(getCitizenList())
    case OcaMethodID("3.9"):
      let enrollment: OcaGrouperEnrollment = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try encodeResponse(getEnrollment(enrollment))
    case OcaMethodID("3.10"):
      let parameters: SwiftOCA.OcaGrouper.SetEnrollmentParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setEnrollment(parameters.enrollment, isMember: parameters.isMember)
      return Ocp1Response()
    case OcaMethodID("3.11"):
      let index: OcaUint16 = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try await encodeResponse(getGroupMemberList(index: index))
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }

  public class Proxy: OcaRoot {
    weak var grouper: OcaGrouper<CitizenType>?
    weak var group: Group?

    init(
      _ grouper: OcaGrouper
    ) async throws {
      try await super.init(
        lockable: grouper.lockable,
        role: "\(grouper.role) Proxy",
        deviceDelegate: grouper.deviceDelegate,
        addToRootBlock: false
      )
      self.grouper = grouper
    }

    public required init(from decoder: Decoder) throws {
      throw Ocp1Error.notImplemented
    }

    @OcaDevice
    fileprivate final class Box {
      var lastStatus: OcaStatus?

      func handleCommand(
        _ command: Ocp1Command,
        from controller: any OcaController,
        proxy: Proxy,
        citizen: Citizen,
        grouper: OcaGrouper<CitizenType>?
      ) async {
        do {
          let command = Ocp1Command(
            commandSize: command.commandSize,
            handle: command.handle,
            targetONo: citizen.target.oNo, // map from proxy to target object number
            methodID: command.methodID,
            parameters: command.parameters
          )
          let response: Ocp1Response

          switch citizen.target {
          case let .local(object):
            response = try await object.handleCommand(command, from: controller)
          case .remote:
            try await grouper?._addConnectionStateMonitor(citizen.connection)
            response = try await citizen.connection.sendCommandRrq(command)
          }

          if response.parameters.parameterCount > 0 {
            throw Ocp1Error.invalidProxyMethodResponse
          } else if lastStatus != .ok {
            lastStatus = .partiallySucceeded
          } else {
            lastStatus = .ok
          }
        } catch let Ocp1Error.status(status) {
          if lastStatus == .ok {
            lastStatus = .partiallySucceeded
          } else if lastStatus != status {
            lastStatus = .processingFailed
          } else {
            lastStatus = status
          }
        } catch {
          lastStatus = .processingFailed // shouldn't happen
        }
      }

      func getResponse() throws -> Ocp1Response {
        if let lastStatus, lastStatus != .ok {
          throw Ocp1Error.status(lastStatus)
        }
        return Ocp1Response()
      }
    }

    override open func handleCommand(
      _ command: Ocp1Command,
      from controller: any OcaController
    ) async throws -> Ocp1Response {
      if command.methodID.defLevel == 1 {
        if command.methodID.methodIndex == 1 {
          let response = CitizenType.classIdentification
          return try encodeResponse(response)
        } else {
          return try await super.handleCommand(command, from: controller)
        }
      }

      guard let group else {
        throw Ocp1Error.status(.deviceError)
      }

      let box = Box()

      for citizen in try grouper?.getGroupMemberList(group: group) ?? [] {
        await box.handleCommand(
          command,
          from: controller,
          proxy: self,
          citizen: citizen,
          grouper: grouper
        )
        if let lastStatus = box.lastStatus, lastStatus != .ok {
          await deviceDelegate?.logger
            .info(
              "\(controller): failed to proxy group command \(command): \(lastStatus)"
            )
        }
      }

      return try box.getResponse()
    }
  }
}

private extension OcaGrouper {
  func _addConnectionStateMonitor(
    _ connection: Ocp1Connection
  ) {
    guard connectionStateMonitors[connection] == nil else {
      return
    }
    connectionStateMonitors[connection] = Task {
      var hasReconnectedAtLeastOnce = false

      for try await connectionState in await connection.connectionState {
        var changeType: OcaGrouperStatusChangeType?

        switch connectionState {
        case .notConnected:
          fallthrough
        case .connectionFailed:
          changeType = .citizenConnectionLost
        case .connected:
          if hasReconnectedAtLeastOnce { changeType = .citizenConnectionReEstablished }
        case .reconnecting:
          hasReconnectedAtLeastOnce = true
        default:
          break
        }

        if let changeType {
          try? await notifySubscribers(group: nil, changeType: changeType)
        }
      }
    }
  }

  func _removeConnectionStateMonitor(_ connection: Ocp1Connection) {
    if let monitor = connectionStateMonitors[connection] {
      monitor.cancel()
      connectionStateMonitors[connection] = nil
    }
  }

  func _removeConnectionStateMonitors() {
    for connection in connectionStateMonitors.keys {
      _removeConnectionStateMonitor(connection)
    }
  }
}

private extension OcaGrouper {
  func notifySubscribers(
    group: Group? = nil,
    citizen: Citizen? = nil,
    changeType: OcaGrouperStatusChangeType
  ) async throws {
    let event = OcaEvent(emitterONo: objectNumber, eventID: OcaGrouperStatusChangeEventID)
    let eventData = OcaGrouperStatusChangeEventData(
      groupIndex: group?.index ?? 0,
      citizenIndex: citizen?.index ?? 0,
      changeType: changeType
    )
    try await deviceDelegate?.notifySubscribers(
      event,
      parameters: Ocp1Encoder().encode(eventData)
    )
  }

  private func notifySubscribers(
    groups: [Group],
    changeType: OcaPropertyChangeType
  ) async throws {
    let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
    let parameters = OcaPropertyChangedEventData<[OcaGrouperGroup]>(
      propertyID: OcaPropertyID("3.2"),
      propertyValue: groups.map(\.ocaGrouperGroup),
      changeType: changeType
    )
    try await deviceDelegate?.notifySubscribers(
      event,
      parameters: parameters
    )
  }

  private func notifySubscribers(
    citizens: [Citizen],
    changeType: OcaPropertyChangeType
  ) async throws {
    let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
    let parameters = await OcaPropertyChangedEventData<[OcaGrouperCitizen]>(
      propertyID: OcaPropertyID("3.3"),
      propertyValue: citizens.asyncMap { @Sendable in await $0.ocaGrouperCitizen },
      changeType: changeType
    )
    try await deviceDelegate?.notifySubscribers(
      event,
      parameters: parameters
    )
  }

  private func notifySubscribers(
    enrollments: [Enrollment],
    changeType: OcaPropertyChangeType
  ) async throws {
    let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
    let parameters = OcaPropertyChangedEventData<[OcaGrouperEnrollment]>(
      propertyID: OcaPropertyID("3.4"),
      propertyValue: enrollments.map { OcaGrouperEnrollment(
        groupIndex: $0.group.index,
        citizenIndex: $0.citizen.index
      ) },
      changeType: changeType
    )
    try await deviceDelegate?.notifySubscribers(
      event,
      parameters: parameters
    )
  }
}

/// protocol for forwarding an event
private protocol _OcaEventForwarding {
  func forward(event: OcaEvent, eventData: OcaAnyPropertyChangedEventData) async throws
}

/// forward an event to a local object
extension OcaRoot: _OcaEventForwarding {
  func forward(event: OcaEvent, eventData: OcaAnyPropertyChangedEventData) async throws {
    guard event.emitterONo == objectNumber, event.eventID == OcaPropertyChangedEventID else {
      throw Ocp1Error.unhandledEvent
    }

    for (_, propertyKeyPath) in allDevicePropertyKeyPaths {
      let property = self[keyPath: propertyKeyPath] as! (any OcaDevicePropertyRepresentable)
      guard property.propertyID == eventData.propertyID else { continue }
      try await property.set(object: self, eventData: eventData)
    }
  }
}

/// forward an event to a remote  object (impementation is in SwiftOCA as it uses private API)
extension SwiftOCA.OcaRoot: _OcaEventForwarding {}

/// forward event to a specific local or remote citizen
extension OcaGrouper.Citizen: _OcaEventForwarding {
  func forward(event: OcaEvent, eventData: OcaAnyPropertyChangedEventData) async throws {
    let forwardingTarget: _OcaEventForwarding? = switch target {
    case let .local(object):
      object
    case let .remote(objectPath):
      try? await connection.resolve(cachedObject: objectPath.oNo)
    }

    try await forwardingTarget?.forward(
      event: OcaEvent(emitterONo: target.oNo, eventID: event.eventID),
      eventData: eventData
    )
  }
}

private protocol _OcaGrouperCitizen: _OcaEventForwarding {}

extension OcaGrouper.Citizen: _OcaGrouperCitizen {}

/// forward event to all citizens in array
extension Array where Element: _OcaGrouperCitizen {
  func forward(event: OcaEvent, eventData: OcaAnyPropertyChangedEventData) async {
    await withTaskGroup(of: Void.self) { taskGroup in
      for element in self {
        taskGroup.addTask {
          try? await element.forward(event: event, eventData: eventData)
        }
      }
    }
  }
}

private protocol _OcaPeerToPeerGrouperNotifiable: OcaRoot {
  var mode: OcaGrouperMode { get }

  func _onLocalEvent(_ event: OcaEvent, eventData: OcaAnyPropertyChangedEventData) async throws
}

/// forward local property events to local and remote objects in group
extension OcaGrouper: _OcaPeerToPeerGrouperNotifiable {
  func _onLocalEvent(_ event: OcaEvent, eventData: OcaAnyPropertyChangedEventData) async throws {
    func isLocalEvent(target: OcaGrouper.Citizen.Target, event: OcaEvent) -> Bool {
      if case let .local(object) = target, object.objectNumber == event.emitterONo {
        true
      } else {
        false
      }
    }

    await enrollments.map(\.citizen).filter { !isLocalEvent(target: $0.target, event: event) }
      .forward(
        event: event,
        eventData: eventData
      )
  }
}

/// forward remote property events to local and remote objects in group
private extension OcaGrouper.Enrollment {
  @Sendable
  private func _forward(
    event: OcaEvent,
    eventData: Data,
    grouper: OcaGrouper
  ) async throws {
    guard let peers = (try? grouper.getGroupMemberList(group: group).filter {
      $0.index != self.citizen.index
    }) else {
      return
    }

    let anyEventData = try OcaAnyPropertyChangedEventData(data: eventData)
    await peers.forward(event: event, eventData: anyEventData)
  }

  mutating func subscribe(grouper: OcaGrouper) async throws {
    guard subscriptionCancellable == nil else { return } // already subscribed

    let event = OcaEvent(emitterONo: citizen.objectPath.oNo, eventID: OcaPropertyChangedEventID)
    do {
      subscriptionCancellable = try await citizen.connection.addSubscription(
        label: "com.padl.SwiftOCADevice.OcaGrouper.\(group.index).\(citizen.index)",
        event: event,
        callback: { @Sendable [weak grouper, self] event, eventData in
          guard let grouper else { return }
          try await _forward(event: event, eventData: eventData, grouper: grouper)
        }
      )
    } catch Ocp1Error.alreadySubscribedToEvent {
    } catch Ocp1Error.status(.invalidRequest) {}
  }

  mutating func unsubscribe() async throws {
    guard let subscriptionCancellable else { throw Ocp1Error.notSubscribedToEvent }
    try await citizen.connection.removeSubscription(subscriptionCancellable)
    self.subscriptionCancellable = nil
  }
}

extension OcaDevice {
  private var _allPeerToPeerGroupers: [_OcaPeerToPeerGrouperNotifiable] {
    func isPeerToPeerGrouper(_ object: OcaRoot) -> Bool {
      guard let grouper = object as? _OcaPeerToPeerGrouperNotifiable else {
        return false
      }
      return grouper.mode == .peerToPeer
    }

    return objects.values
      .filter { isPeerToPeerGrouper($0) } as! [_OcaPeerToPeerGrouperNotifiable]
  }

  func _notifyPeerToPeerGroupers(
    _ event: OcaEvent,
    parameters: OcaPropertyChangedEventData<some Codable & Sendable>
  ) async throws {
    for grouper in _allPeerToPeerGroupers {
      try? await grouper._onLocalEvent(event, eventData: parameters.toAny())
    }
  }
}
