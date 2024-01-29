//
// Copyright (c) 2024 PADL Software Pty Ltd
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

open class OcaGrouper: OcaAgent {
    override public class var classID: OcaClassID { OcaClassID("1.2.2") }
    override public class var classVersion: OcaClassVersionNumber { 3 }

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
    final class Group: Sendable {
        let index: OcaUint16
        let name: OcaString
        let proxy: Proxy?

        public init(grouper: OcaGrouper, index: OcaUint16, name: OcaString) async throws {
            self.index = index
            self.name = name
            if grouper.mode == .masterSlave {
                let proxy = try await Proxy(grouper)
                self.proxy = proxy
                proxy.group = self
            } else {
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
    }

    // at some point, when remote connections are supported, then we will maintain a lookaside
    // table (either globally or in the device?) that maps a OcaOPath hostID to an OcaConnection.

    @OcaDevice
    final class Citizen: Sendable {
        enum Target {
            case local(OcaRoot)
            case remote(OcaOPath)

            var objectPath: OcaOPath {
                switch self {
                case let .local(object):
                    return OcaOPath(hostID: OcaBlob(), oNo: object.objectNumber)
                case let .remote(path):
                    return path
                }
            }

            var classIdentification: OcaClassIdentification {
                get async throws {
                    switch self {
                    case let .local(object):
                        return await object.objectIdentification.classIdentification
                    case .remote:
                        throw Ocp1Error.notImplemented
                    }
                }
            }

            var online: OcaBoolean {
                switch self {
                case .local:
                    return true
                case .remote:
                    return false
                }
            }

            init(_ objectPath: OcaOPath, device: OcaDevice) async throws {
                if objectPath.hostID.isEmpty {
                    guard let object = await device.resolve(objectNumber: objectPath.oNo) else {
                        throw Ocp1Error.status(.badONo)
                    }
                    self = .local(object)
                } else {
                    throw Ocp1Error.notImplemented
                }
            }
        }

        let index: OcaUint16
        let target: Target

        init(index: OcaUint16, target: Target) {
            self.index = index
            self.target = target
        }

        var ocaGrouperCitizen: OcaGrouperCitizen {
            OcaGrouperCitizen(index: index, objectPath: target.objectPath, online: target.online)
        }
    }

    typealias Enrollment = (Group, Citizen)

    private var groups = [OcaUint16: Group]()
    private var citizens = [OcaUint16: Citizen]()
    private var enrollments = [Enrollment]()
    private var nextGroupIndex: OcaUint16 = 0
    private var nextCitizenIndex: OcaUint16 = 0

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
        try await notifySubscribers(group: group, changeType: .itemAdded)
        return SwiftOCA.OcaGrouper.AddGroupParameters(index: group.index, proxyONo: group.proxyONo)
    }

    func deleteGroup(index: OcaUint16) async throws {
        guard let group = groups[index] else {
            throw Ocp1Error.status(.invalidRequest)
        }
        if let proxy = group.proxy {
            try await deviceDelegate?.deregister(object: proxy)
        }
        try await notifySubscribers(group: group, changeType: .itemDeleted)
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
        try await notifySubscribers(citizen: citizen, changeType: .itemAdded)
        return citizen.index
    }

    func deleteCitizen(index: OcaUint16) async throws {
        guard let citizen = citizens[index] else {
            throw Ocp1Error.status(.invalidRequest)
        }
        try await notifySubscribers(citizen: citizen, changeType: .citizenDeleted)
        try await notifySubscribers(citizen: citizen, changeType: .itemDeleted)
        citizens[index] = nil
    }

    var citizenCount: OcaUint16 { OcaUint16(citizens.count) }

    func getCitizenList() -> [OcaGrouperCitizen] {
        citizens.map { _, value in
            value.ocaGrouperCitizen
        }
    }

    func getEnrollment(_ enrollment: OcaGrouperEnrollment) -> OcaBoolean {
        enrollments.contains(where: {
            $0.0.index == enrollment.groupIndex && $0.1.index == enrollment.citizenIndex
        })
    }

    func setEnrollment(_ enrollment: OcaGrouperEnrollment, isMember: OcaBoolean) async throws {
        guard let group = groups[enrollment.groupIndex],
              let citizen = citizens[enrollment.citizenIndex]
        else {
            throw Ocp1Error.status(.invalidRequest)
        }

        if isMember {
            let citizenClassIdentification = try await citizen.target.classIdentification
            if let existingCitizens: [Citizen] = try? getGroupMemberList(group: group),
               let existingCitizen = existingCitizens.first
            {
                if try await citizenClassIdentification != existingCitizen.target
                    .classIdentification
                {
                    throw Ocp1Error.status(.invalidRequest)
                }
            } else {
                group.proxy?.citizenClassIdentification = citizenClassIdentification
            }
            enrollments.append((group, citizen))
        } else {
            guard getEnrollment(enrollment) else { throw Ocp1Error.status(.invalidRequest) }
            enrollments
                .removeAll(where: {
                    $0.0.index == enrollment.groupIndex && $0.1.index == enrollment.citizenIndex
                })
        }
        try await notifySubscribers(
            group: group,
            citizen: citizen,
            changeType: isMember ? .enrollment : .unEnrollment
        )
        try await notifySubscribers(
            enrollment: (group, citizen),
            changeType: isMember ? .itemAdded : .itemDeleted
        )
    }

    func getGroupMemberList(group: Group) throws -> [Citizen] {
        enrollments.filter { $0.0.index == group.index }.map(\.1)
    }

    func getGroupMemberList(index: OcaUint16) throws -> [OcaGrouperCitizen] {
        guard let group = groups[index] else {
            throw Ocp1Error.status(.invalidRequest)
        }
        return try getGroupMemberList(group: group).map(\.ocaGrouperCitizen)
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
            return try encodeResponse(getCitizenList())
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
            return try encodeResponse(getGroupMemberList(index: index))
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }

    public class Proxy: OcaRoot {
        weak var grouper: OcaGrouper?
        weak var group: Group?
        var citizenClassIdentification: OcaClassIdentification?

        init(
            _ grouper: OcaGrouper
        ) async throws {
            try await super.init(
                lockable: grouper.lockable,
                role: "\(grouper.role) Proxy",
                deviceDelegate: grouper.deviceDelegate,
                addToRootBlock: false
            )
        }

        public required init(from decoder: Decoder) throws {
            throw Ocp1Error.objectNotPresent
        }

        fileprivate actor CommandBox {
            var lastStatus: OcaStatus?

            func handleCommand(
                _ command: Ocp1Command,
                from controller: any OcaController,
                object: OcaRoot
            ) async throws {
                do {
                    let response = try await object.handleCommand(command, from: controller)
                    if response.parameters.parameterCount > 0 {
                        throw Ocp1Error.status(.invalidRequest)
                    }
                    if lastStatus != .ok {
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

            func getResponse() async throws -> Ocp1Response {
                if let lastStatus, lastStatus != .ok {
                    throw Ocp1Error.status(lastStatus)
                }
                return Ocp1Response()
            }
        }

        override public var objectIdentification: OcaObjectIdentification {
            OcaObjectIdentification(
                oNo: objectNumber,
                classIdentification: citizenClassIdentification ?? Self.classIdentification
            )
        }

        override open func handleCommand(
            _ command: Ocp1Command,
            from controller: any OcaController
        ) async throws -> Ocp1Response {
            if command.methodID.defLevel == 1 {
                return try await super.handleCommand(command, from: controller)
            }

            guard let group else {
                throw Ocp1Error.status(.deviceError)
            }

            let box = CommandBox()

            for citizen in try grouper?.getGroupMemberList(group: group) ?? [] {
                switch citizen.target {
                case let .local(object):
                    try await box.handleCommand(command, from: controller, object: object)
                case .remote:
                    throw Ocp1Error.notImplemented
                }
            }

            return try await box.getResponse()
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
        group: Group,
        changeType: OcaPropertyChangeType
    ) async throws {
        let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
        let parameters = OcaPropertyChangedEventData<OcaGrouperGroup>(
            propertyID: OcaPropertyID("3.2"),
            propertyValue: group.ocaGrouperGroup,
            changeType: changeType
        )
        try await deviceDelegate?.notifySubscribers(
            event,
            parameters: parameters
        )
    }

    private func notifySubscribers(
        citizen: Citizen,
        changeType: OcaPropertyChangeType
    ) async throws {
        let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
        let parameters = OcaPropertyChangedEventData<OcaGrouperCitizen>(
            propertyID: OcaPropertyID("3.3"),
            propertyValue: citizen.ocaGrouperCitizen,
            changeType: changeType
        )
        try await deviceDelegate?.notifySubscribers(
            event,
            parameters: parameters
        )
    }

    private func notifySubscribers(
        enrollment: Enrollment,
        changeType: OcaPropertyChangeType
    ) async throws {
        let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
        let parameters = OcaPropertyChangedEventData<OcaGrouperEnrollment>(
            propertyID: OcaPropertyID("3.4"),
            propertyValue: OcaGrouperEnrollment(
                groupIndex: enrollment.0.index,
                citizenIndex: enrollment.1.index
            ),
            changeType: changeType
        )
        try await deviceDelegate?.notifySubscribers(
            event,
            parameters: parameters
        )
    }
}
