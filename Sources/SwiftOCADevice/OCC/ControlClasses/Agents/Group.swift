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

import Foundation
@_spi(SwiftOCAPrivate)
import SwiftOCA

public let OcaGroupExceptionEventID = OcaEventID(defLevel: 3, eventIndex: 1)

open class OcaGroup<Member: OcaRoot>: OcaAgent {
    override open class var classID: OcaClassID { OcaClassID("1.2.22") }
    override open class var classVersion: OcaClassVersionNumber { 3 }

    public private(set) var members = [Member]()

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.3"),
        getMethodID: OcaMethodID("3.7"),
        setMethodID: OcaMethodID("3.8")
    )
    public var aggregationMode: OcaString?

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.4"),
        getMethodID: OcaMethodID("3.9"),
        setMethodID: OcaMethodID("3.10")
    )
    public var saturationMode: OcaString?

    open func set(members: [Member]) async throws {
        guard members.allSatisfy({ $0.objectNumber != OcaInvalidONo }) else {
            throw Ocp1Error.status(.badONo)
        }
        self.members = members
        try? await notifySubscribers(actionObjects: members, changeType: .itemChanged)
    }

    open func add(member: Member) async throws {
        guard member.objectNumber != OcaInvalidONo else {
            throw Ocp1Error.status(.badONo)
        }

        guard member != self, !members.contains(member) else {
            throw Ocp1Error.status(.parameterError)
        }

        members.append(member)
        try? await notifySubscribers(actionObjects: members, changeType: .itemAdded)
    }

    open func delete(member: Member) async throws {
        guard member.objectNumber != OcaInvalidONo else {
            throw Ocp1Error.status(.badONo)
        }

        guard members.contains(member) else {
            throw Ocp1Error.status(.parameterError)
        }

        members.removeAll { $0 == member }
        try? await notifySubscribers(actionObjects: members, changeType: .itemDeleted)
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: any OcaController
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("3.1"):
            try decodeNullCommand(command)
            try await ensureReadable(by: controller, command: command)
            return try encodeResponse(members.map(\.objectNumber))
        case OcaMethodID("3.2"):
            let memberONos: [OcaONo] = try decodeCommand(command)
            let members = try await memberONos.asyncMap { @Sendable memberONo in
                guard let member = await deviceDelegate?
                    .resolve(objectNumber: memberONo) as? Member
                else {
                    throw Ocp1Error.invalidObject(memberONo)
                }
                return member
            }
            try await ensureWritable(by: controller, command: command)
            try await set(members: members)
            return Ocp1Response()
        case OcaMethodID("3.3"):
            let memberONo: OcaONo = try decodeCommand(command)
            guard let member = await deviceDelegate?.resolve(objectNumber: memberONo) as? Member
            else {
                throw Ocp1Error.invalidObject(memberONo)
            }
            try await ensureWritable(by: controller, command: command)
            try await add(member: member)
            return Ocp1Response()
        case OcaMethodID("3.4"):
            let memberONo: OcaONo = try decodeCommand(command)
            guard let member = await deviceDelegate?.resolve(objectNumber: memberONo) as? Member
            else {
                throw Ocp1Error.invalidObject(memberONo)
            }
            try await ensureWritable(by: controller, command: command)
            try await delete(member: member)
            return Ocp1Response()
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }
}

extension OcaGroup {
    func notifySubscribers(
        actionObjects: [Member],
        changeType: OcaPropertyChangeType
    ) async throws {
        let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
        let parameters = OcaPropertyChangedEventData<[Member]>(
            propertyID: OcaPropertyID("3.1"),
            propertyValue: actionObjects,
            changeType: changeType
        )

        try await deviceDelegate?.notifySubscribers(
            event,
            parameters: parameters
        )
    }
}

public protocol OcaGroupPeerToPeerMember: OcaRoot {
    var group: OcaGroup<Self>? { get set }
}

extension OcaGroupPeerToPeerMember {
    func handleCommandForEachPeerToPeerMember(
        _ command: Ocp1Command,
        from controller: any OcaController
    ) async throws -> Ocp1Response {
        guard let group else {
            return try await handleCommand(command, from: controller)
        }

        do {
            return try await OcaGroup<Self>.handleCommand(command, from: controller, in: group)
        } catch Ocp1Error.invalidProxyMethodResponse {
            return try await handleCommand(command, from: controller)
        }
    }
}

open class _OcaPeerToPeerGroup<Member: OcaGroupPeerToPeerMember>: OcaGroup<Member> {
    public init(
        objectNumber: OcaONo? = nil,
        lockable: OcaBoolean = true,
        role: OcaString = "Peer-to-peer Group of \(Member.self)",
        deviceDelegate: OcaDevice? = nil,
        addToRootBlock: Bool = true
    ) async throws {
        try await super.init(
            objectNumber: objectNumber,
            lockable: lockable,
            role: role,
            deviceDelegate: deviceDelegate,
            addToRootBlock: addToRootBlock
        )
    }

    public required init(from decoder: Decoder) throws {
        throw Ocp1Error.notImplemented
    }

    override open func set(members: [Member]) async throws {
        members.forEach { $0.group = self }
        try await super.set(members: members)
    }

    override open func add(member: Member) async throws {
        member.group = self
        try await super.add(member: member)
    }

    override open func delete(member: Member) async throws {
        member.group = nil
        try await super.delete(member: member)
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: any OcaController
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("3.5"):
            try decodeNullCommand(command)
            try await ensureReadable(by: controller, command: command)
            return try encodeResponse(OcaInvalidONo)
        case OcaMethodID("3.6"):
            let _: OcaONo = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            throw Ocp1Error.status(.invalidRequest)
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }
}

open class _OcaGroupControllerGroup<Member: OcaRoot>: OcaGroup<Member> {
    private var groupController: GroupController?

    public init(
        objectNumber: OcaONo? = nil,
        lockable: OcaBoolean = true,
        role: OcaString = "Proxy Group of \(Member.self)",
        deviceDelegate: OcaDevice? = nil,
        addToRootBlock: Bool = true
    ) async throws {
        try await super.init(
            objectNumber: objectNumber,
            lockable: lockable,
            role: role,
            deviceDelegate: deviceDelegate,
            addToRootBlock: addToRootBlock
        )

        groupController = try await GroupController(self)
    }

    public required init(from decoder: Decoder) throws {
        throw Ocp1Error.notImplemented
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: any OcaController
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("3.5"):
            try decodeNullCommand(command)
            try await ensureReadable(by: controller, command: command)
            return try encodeResponse(groupController?.objectNumber ?? OcaInvalidONo)
        case OcaMethodID("3.6"):
            let _: OcaONo = try decodeCommand(command)
            try await ensureWritable(by: controller, command: command)
            throw Ocp1Error.status(.notImplemented)
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }

    @OcaDevice
    public class GroupController: OcaRoot {
        weak var group: _OcaGroupControllerGroup?

        init(_ group: _OcaGroupControllerGroup) async throws {
            try await super.init(
                lockable: group.lockable,
                role: "\(group.role) Group Controller",
                deviceDelegate: group.deviceDelegate,
                addToRootBlock: false
            )
            self.group = group
        }

        public required init(from decoder: Decoder) throws {
            throw Ocp1Error.notImplemented
        }

        override open func handleCommand(
            _ command: Ocp1Command,
            from controller: any OcaController
        ) async throws -> Ocp1Response {
            if command.methodID.defLevel == 1 {
                if command.methodID.methodIndex == 1 {
                    let response = Member.classIdentification
                    return try encodeResponse(response)
                } else {
                    return try await super.handleCommand(command, from: controller)
                }
            }

            guard let group else {
                throw Ocp1Error.status(.deviceError)
            }

            return try await OcaGroup<Member>.handleCommand(command, from: controller, in: group)
        }
    }
}

extension OcaGroup {
    static func handleCommand(
        _ command: Ocp1Command,
        from controller: any OcaController,
        in group: OcaGroup
    ) async throws -> Ocp1Response {
        var response: Ocp1Response?
        var exceptions = [OcaGroupException]()

        for member in group.members {
            if let response, response.parameters.parameterCount > 0 {
                // we have an existing response for a get request, multiple gets are unsupported
                throw Ocp1Error.invalidProxyMethodResponse
            }

            do {
                response = try await member.handleCommand(command, from: controller)
            } catch {
                let exceptionStatus: OcaStatus

                if let error = error as? Ocp1Error, case let .status(status) = error {
                    exceptionStatus = status
                } else {
                    exceptionStatus = .processingFailed
                }
                let exception = OcaGroupException(
                    oNo: member.objectNumber,
                    methodID: command.methodID,
                    status: exceptionStatus
                )
                exceptions.append(exception)
            }
        }

        if !exceptions.isEmpty {
            let exceptionData: [UInt8] = try Ocp1Encoder().encode(exceptions)
            let notification = Ocp1Notification2(
                event: OcaEvent(
                    emitterONo: group.objectNumber,
                    eventID: OcaGroupExceptionEventID
                ),
                notificationType: .event,
                data: Data(exceptionData)
            )
            try await controller.sendMessage(notification, type: .ocaNtf2)
        }

        return response ?? Ocp1Response()
    }
}
