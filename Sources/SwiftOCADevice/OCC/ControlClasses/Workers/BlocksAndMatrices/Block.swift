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

import Foundation
import SwiftOCA

open class OcaBlock<Member: OcaRoot>: OcaWorker {
    override open class var classID: OcaClassID { OcaClassID("1.1.3") }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.1")
    )
    public var type: OcaONo = OcaInvalidONo

    public private(set) var members = [Member]()

    open func add(member object: Member) {
        precondition(object != self)
        if let object = object as? OcaWorker {
            object.owner = objectNumber
        }
        members.append(object)
    }

    open func remove(member object: Member) {
        guard let index = members.firstIndex(of: object) else {
            return
        }
        if let object = object as? OcaWorker, object.owner == objectNumber {
            object.owner = OcaInvalidONo
        }
        members.remove(at: index)
    }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.3"),
        getMethodID: OcaMethodID("3.16")
    )
    public var signalPaths = OcaMap<OcaUint16, OcaSignalPath>()

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.4"),
        getMethodID: OcaMethodID("3.11")
    )
    public var mostRecentParamSetIdentifier: OcaLibVolIdentifier?

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.5"),
        getMethodID: OcaMethodID("3.15")
    )
    public var globalType: OcaGlobalTypeIdentifier?

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.6"),
        getMethodID: OcaMethodID("3.16")
    )
    public var oNoMap = OcaMap<OcaProtoONo, OcaONo>()

    func applyRecursive(
        members: [Member],
        _ block: (_ member: Member) async throws -> ()
    ) async throws {
        for member in members {
            precondition(member != self)
            if let member = member as? OcaBlock {
                try await applyRecursive(members: member.members, block)
            } else {
                try await block(member)
            }
        }
    }

    func applyRecursive(
        _ block: (_ member: Member) async throws -> ()
    ) async throws {
        try await applyRecursive(members: members, block)
    }

    func getRecursive(from controller: AES70OCP1Controller) async throws
        -> OcaList<OcaBlockMember>
    {
        var members = [OcaBlockMember]()

        try await applyRecursive { member in
            precondition(member != self)
            members
                .append(OcaBlockMember(
                    memberObjectIdentification: member.objectIdentification,
                    containerObjectNumber: objectNumber
                ))
        }

        return members
    }

    func getRecursive(from controller: AES70OCP1Controller) async throws
        -> OcaMap<OcaUint16, OcaSignalPath>
    {
        throw Ocp1Error.notImplemented
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: AES70OCP1Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("3.5"):
            try await ensureReadable(by: controller)
            let members = members.map(\.objectIdentification)
            return try encodeResponse(members)
        case OcaMethodID("3.6"):
            try await ensureReadable(by: controller)
            let members: [OcaBlockMember] = try await getRecursive(from: controller)
            return try encodeResponse(members)
        case OcaMethodID("3.10"):
            try await ensureReadable(by: controller)
            let members: [OcaUint16: OcaSignalPath] = try await getRecursive(from: controller)
            return try encodeResponse(members)
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }

    override public var isContainer: Bool {
        true
    }
}
