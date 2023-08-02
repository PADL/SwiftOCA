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

open class OcaBlock<ActionObject: OcaRoot>: OcaWorker {
    override open class var classID: OcaClassID { OcaClassID("1.1.3") }

    @OcaDeviceProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.1")
    )
    public var type: OcaONo = OcaInvalidONo

    public private(set) var actionObjects = [ActionObject]()

    open func add(actionObject object: ActionObject) throws {
        precondition(object != self)
        guard !actionObjects.contains(object) else {
            throw Ocp1Error.objectNotUnique
        }

        if let object = object as? OcaWorker {
            object.owner = objectNumber
        }
        actionObjects.append(object)
    }

    open func remove(actionObject object: ActionObject) throws {
        guard let index = actionObjects.firstIndex(of: object) else {
            throw Ocp1Error.objectNotPresent
        }
        if let object = object as? OcaWorker, object.owner == objectNumber {
            object.owner = OcaInvalidONo
        }
        actionObjects.remove(at: index)
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

    func applyRecursive<T: OcaRoot>(
        keyPath: KeyPath<OcaBlock, [T]>,
        members: [T],
        _ block: (_ member: T) async throws -> ()
    ) async throws {
        for member in members {
            precondition(member != self)
            if let member = member as? OcaBlock {
                try await applyRecursive(keyPath: keyPath, members: self[keyPath: keyPath], block)
            } else {
                try await block(member)
            }
        }
    }

    func applyRecursive<T: OcaRoot>(
        keyPath: KeyPath<OcaBlock, [T]>,
        _ block: (_ member: T) async throws -> ()
    ) async throws {
        try await applyRecursive(
            keyPath: keyPath,
            members: self[keyPath: keyPath],
            block
        )
    }

    func getActionObjectsRecursive(from controller: any AES70Controller) async throws
        -> OcaList<OcaBlockMember>
    {
        var members = [OcaBlockMember]()

        try await applyRecursive(keyPath: \.actionObjects) { (member: ActionObject) in
            precondition(member != self)
            members
                .append(OcaBlockMember(
                    memberObjectIdentification: member.objectIdentification,
                    containerObjectNumber: objectNumber
                ))
        }

        return members
    }

    func getSignalPathsRecursive(from controller: any AES70Controller) async throws
        -> OcaMap<OcaUint16, OcaSignalPath>
    {
        throw Ocp1Error.notImplemented
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: any AES70Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
        // 3.1 GetType
        // 3.2 ConstructActionObject
        // 3.3 ConstructBlockUsingFactory
        // 3.4 DeleteMember
        case OcaMethodID("3.5"):
            try await ensureReadable(by: controller)
            let actionObjects = actionObjects.map(\.objectIdentification)
            return try encodeResponse(actionObjects)
        case OcaMethodID("3.6"):
            try await ensureReadable(by: controller)
            let actionObjects: [OcaBlockMember] =
                try await getActionObjectsRecursive(from: controller)
            return try encodeResponse(actionObjects)
        // 3.7 AddSignalPath
        // 3.8 DeleteSignalPath
        // 3.9 GetSignalPaths
        case OcaMethodID("3.10"):
            try await ensureReadable(by: controller)
            let signalPaths: [OcaUint16: OcaSignalPath] =
                try await getSignalPathsRecursive(from: controller)
            return try encodeResponse(signalPaths)
        // 3.15 GetGlobalType
        // 3.16 GetONoMap
        // 3.17 FindActionObjectsByRole
        // 3.18 FindActionObjectsByRoleRecursive
        // 3.19 FindActionObjectsByLabelRecursive
        // 3.20 FindActionObjectsByRolePath
        // 3.21 GetConfigurability
        // 3.22 GetMostRecentParamDatasetONo
        // 3.23 ApplyParamDataset
        // 3.24 StoreCurrentParameterData
        // 3.25 FetchCurrentParameterData
        // 3.26 ApplyParameterData
        // 3.27 ConstructDataset
        // 3.28 DuplicateDataset
        // 3.29 GetDatasetObjects
        // 3.30 GetDatasetObjectsRecursive
        // 3.31 FindDatasets
        // 3.32 FindDatasetsRecursive
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }

    override public var isContainer: Bool {
        true
    }
}
