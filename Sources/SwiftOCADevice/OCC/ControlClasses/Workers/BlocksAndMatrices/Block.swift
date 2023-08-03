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

import AsyncExtensions
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

    open func add(actionObject object: ActionObject) async throws {
        precondition(object != self)
        guard !actionObjects.contains(object) else {
            throw Ocp1Error.objectNotUnique
        }

        if let object = object as? OcaWorker {
            object.owner = objectNumber
        }

        if object.deviceDelegate == nil {
            object.deviceDelegate = deviceDelegate
            if let deviceDelegate, object.objectNumber == OcaInvalidONo {
                try await deviceDelegate.register(object: object, addToRootBlock: false)
            }
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
        rootObject: OcaBlock,
        keyPath: KeyPath<OcaBlock, [T]>,
        _ block: (_ member: T, _ container: OcaBlock) async throws -> ()
    ) async rethrows {
        for member in rootObject[keyPath: keyPath] {
            if let member = member as? OcaBlock {
                try await applyRecursive(rootObject: member, keyPath: keyPath, block)
            } else {
                try await block(member, rootObject)
            }
        }
    }

    func applyRecursive<T: OcaRoot>(
        keyPath: KeyPath<OcaBlock, [T]>,
        _ block: (_ member: T, _ container: OcaBlock) async throws -> ()
    ) async rethrows {
        try await applyRecursive(
            rootObject: self,
            keyPath: keyPath,
            block
        )
    }

    func filterRecursive<T: OcaRoot>(
        keyPath: KeyPath<OcaBlock, [T]>,
        _ isIncluded: @escaping (T, OcaBlock) async throws -> Bool
    ) async rethrows -> [T] {
        var members = [T]()

        try await applyRecursive(keyPath: keyPath) { member, container in
            if try await isIncluded(member, container) {
                members.append(member)
            }
        }

        return members
    }

    func mapRecursive<T: OcaRoot, U>(
        keyPath: KeyPath<OcaBlock, [T]>,
        _ transform: (T, OcaBlock) async throws -> U
    ) async rethrows -> [U] {
        var members = [U]()

        try await applyRecursive(keyPath: keyPath) { member, container in
            try await members.append(transform(member, container))
        }

        return members
    }

    func getActionObjectsRecursive(from controller: any AES70Controller) async throws
        -> OcaList<OcaBlockMember>
    {
        await mapRecursive(keyPath: \.actionObjects) { (member: ActionObject, container: OcaBlock) in
            OcaBlockMember(
                memberObjectIdentification: member.objectIdentification,
                containerObjectNumber: container.objectNumber
            )
        }
    }

    func getSignalPathsRecursive(from controller: any AES70Controller) async throws
        -> OcaMap<OcaUint16, OcaSignalPath>
    {
        throw Ocp1Error.notImplemented
    }

    func find(
        actionObjectsByRole searchName: OcaString,
        nameComparisonType: OcaStringComparisonType,
        searchClassID: OcaClassID,
        resultFlags: OcaObjectSearchResultFlags
    ) async throws -> AnyAsyncSequence<OcaObjectSearchResult> {
        actionObjects.filter { member in
            member.compare(
                searchName: searchName,
                keyPath: \.role,
                nameComparisonType: nameComparisonType,
                searchClassID: searchClassID
            )
        }.async.map { member in
            await member.makeSearchResult(with: resultFlags)
        }.eraseToAnyAsyncSequence()
    }

    func findRecursive(
        actionObjectsByRole searchName: OcaString,
        nameComparisonType: OcaStringComparisonType,
        searchClassID: OcaClassID,
        resultFlags: OcaObjectSearchResultFlags
    ) async throws -> AnyAsyncSequence<OcaObjectSearchResult> {
        await filterRecursive(keyPath: \.actionObjects) { member, _ in
            member.compare(
                searchName: searchName,
                keyPath: \.role,
                nameComparisonType: nameComparisonType,
                searchClassID: searchClassID
            )
        }.async.map { member in
            await member.makeSearchResult(with: resultFlags)
        }.eraseToAnyAsyncSequence()
    }

    func find(
        actionObjectsByRolePath searchPath: OcaNamePath,
        resultFlags: OcaObjectSearchResultFlags
    ) async throws -> AnyAsyncSequence<OcaObjectSearchResult> {
        await filterRecursive(keyPath: \.actionObjects) { member, _ in
            await member.rolePath == searchPath
        }.async.map { member in
            await member.makeSearchResult(with: resultFlags)
        }.eraseToAnyAsyncSequence()
    }

    func findRecursive(
        actionObjectsByLabel searchName: OcaString,
        nameComparisonType: OcaStringComparisonType,
        searchClassID: OcaClassID,
        resultFlags: OcaObjectSearchResultFlags
    ) async throws -> AnyAsyncSequence<OcaObjectSearchResult> {
        await filterRecursive(keyPath: \.actionObjects) { member, _ in
            if let agent = member as? OcaAgent {
                return agent.compare(
                    searchName: searchName,
                    keyPath: \OcaAgent.label,
                    nameComparisonType: nameComparisonType,
                    searchClassID: searchClassID
                )
            } else if let worker = member as? OcaWorker {
                return worker.compare(
                    searchName: searchName,
                    keyPath: \OcaAgent.label,
                    nameComparisonType: nameComparisonType,
                    searchClassID: searchClassID
                )
            } else {
                return false
            }
        }.async.map { member in
            await member.makeSearchResult(with: resultFlags)
        }.eraseToAnyAsyncSequence()
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: any AES70Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
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
        case OcaMethodID("3.7"):
            try await ensureWritable(by: controller)
            let path: OcaSignalPath = try decodeCommand(command)
            let index: OcaUint16 = signalPaths.keys.sorted().last ?? 1
            signalPaths[index] = path
            return try encodeResponse(index)
        case OcaMethodID("3.8"):
            try await ensureWritable(by: controller)
            let index: OcaUint16 = try decodeCommand(command)
            if !signalPaths.keys.contains(index) {
                throw Ocp1Error.status(.parameterOutOfRange)
            }
            signalPaths.removeValue(forKey: index)
        case OcaMethodID("3.9"):
            try await ensureReadable(by: controller)
            return try encodeResponse(signalPaths)
        case OcaMethodID("3.10"):
            try await ensureReadable(by: controller)
            let signalPaths: [OcaUint16: OcaSignalPath] =
                try await getSignalPathsRecursive(from: controller)
            return try encodeResponse(signalPaths)
        // 3.15 GetGlobalType
        // 3.16 GetONoMap
        case OcaMethodID("3.17"):
            let params: SwiftOCA.OcaBlock
                .FindActionObjectsByRoleParameters = try decodeCommand(command)
            let searchResult = try await find(
                actionObjectsByRole: params.searchName,
                nameComparisonType: params.nameComparisonType,
                searchClassID: params.searchClassID,
                resultFlags: params.resultFlags
            )
            return try await encodeResponse(searchResult.collect())
        case OcaMethodID("3.18"):
            let params: SwiftOCA.OcaBlock
                .FindActionObjectsByRoleParameters = try decodeCommand(command)
            let searchResult = try await findRecursive(
                actionObjectsByRole: params.searchName,
                nameComparisonType: params.nameComparisonType,
                searchClassID: params.searchClassID,
                resultFlags: params.resultFlags
            )
            return try await encodeResponse(searchResult.collect())
        case OcaMethodID("3.19"):
            let params: SwiftOCA.OcaBlock
                .FindActionObjectsByRoleParameters = try decodeCommand(command)
            let searchResult = try await findRecursive(
                actionObjectsByLabel: params.searchName,
                nameComparisonType: params.nameComparisonType,
                searchClassID: params.searchClassID,
                resultFlags: params.resultFlags
            )
            return try await encodeResponse(searchResult.collect())
        case OcaMethodID("3.20"):
            let params: SwiftOCA.OcaBlock
                .FindActionObjectsByRolePathParameters = try decodeCommand(command)
            let searchResult = try await find(
                actionObjectsByRolePath: params.searchPath,
                resultFlags: params.resultFlags
            )
            return try await encodeResponse(searchResult.collect())
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
        return Ocp1Response()
    }

    override public var isContainer: Bool {
        true
    }
}

public extension OcaRoot {
    private func makePath<T: OcaRoot, U>(
        rootObject: T,
        keyPath: KeyPath<T, U>
    ) async -> [U] {
        var path = [rootObject[keyPath: keyPath]]

        if let object = rootObject as? OcaOwnable,
           object.owner != OcaInvalidONo,
           let container = await deviceDelegate?.objects[object.owner] as? T
        {
            path.insert(contentsOf: await makePath(rootObject: container, keyPath: keyPath), at: 0)
        }

        return path
    }

    var objectNumberPath: OcaONoPath {
        get async {
            await makePath(rootObject: self, keyPath: \.objectNumber)
        }
    }

    var rolePath: OcaNamePath {
        get async {
            await makePath(rootObject: self, keyPath: \.role)
        }
    }
}

private extension OcaRoot {
    func compare<T: OcaRoot>(
        searchName: OcaString,
        keyPath: KeyPath<T, String>,
        nameComparisonType: OcaStringComparisonType,
        searchClassID: OcaClassID
    ) -> Bool {
        guard objectIdentification.classIdentification.classID == searchClassID else {
            return false
        }

        let value = (self as! T)[keyPath: keyPath]

        switch nameComparisonType {
        case .exact:
            return value == searchName
        case .substring:
            return value.hasPrefix(searchName)
        case .contains:
            return value.contains(searchName)
        case .exactCaseInsensitive:
            return value.lowercased().hasPrefix(searchName.lowercased())
        case .substringCaseInsensitive:
            return value.lowercased().hasPrefix(searchName.lowercased())
        case .containsCaseInsensitive:
            return value.lowercased().contains(searchName.lowercased())
        }
    }

    func makeSearchResult(with resultFlags: OcaObjectSearchResultFlags) async
        -> OcaObjectSearchResult
    {
        var oNo: OcaONo?
        var classIdentification: OcaClassIdentification?
        var containerPath: OcaONoPath?
        var role: OcaString?
        var label: OcaString?

        if resultFlags.contains(.oNo) {
            oNo = objectNumber
        }
        if resultFlags.contains(.classIdentification) {
            classIdentification = objectIdentification.classIdentification
        }
        if resultFlags.contains(.containerPath) {
            containerPath = await objectNumberPath
        }
        if resultFlags.contains(.role) {
            role = self.role
        }
        if resultFlags.contains(.label), let worker = self as? OcaWorker {
            label = worker.label
        }

        return OcaObjectSearchResult(
            oNo: oNo,
            classIdentification: classIdentification,
            containerPath: containerPath,
            role: role,
            label: label
        )
    }
}
